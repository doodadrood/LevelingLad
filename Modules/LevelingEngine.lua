local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.LevelingEngine = {}

local EPSILON = 1e-9

-- ============================================================================
-- 1. Core Skill-Up Probability & Difficulty Mathematics
-- ============================================================================

function LL.LevelingEngine.GetDifficultyState(recipe, skill)
    if type(recipe) ~= "table" or type(skill) ~= "number" then
        return "GRAY"
    end
    -- Authoritative live-scan guard: if Blizzard reported this recipe as GRAY (Trivial) at or below
    -- `skill`, it can never grant skillups at `skill` or higher.
    if recipe.liveDifficulty == "GRAY" and type(recipe.scannedAtRank) == "number" and skill >= recipe.scannedAtRank then
        return "GRAY"
    end

    local gray = recipe.gray or 0
    local green = recipe.green or gray
    local yellow = recipe.yellow or green

    if skill >= gray then
        return "GRAY"
    elseif skill >= green then
        return "GREEN"
    elseif skill >= yellow then
        return "YELLOW"
    else
        return "ORANGE"
    end
end

-- Exact skillup probability curve P(Skillup | S):
--   Orange (S < T_yellow):           P = 1.0
--   Yellow (T_yellow <= S < T_green): P = max(0.50, (T_gray - S) / (T_gray - T_yellow))
--   Green  (T_green <= S < T_gray):   P = max(0.10, (T_gray - S) / (2 * (T_gray - T_yellow)))
--   Gray   (S >= T_gray):             P = 0.0
function LL.LevelingEngine.GetSkillupProbability(recipe, skill)
    local state = LL.LevelingEngine.GetDifficultyState(recipe, skill)
    if state == "ORANGE" then
        return 1.0
    elseif state == "GRAY" then
        return 0.0
    end

    local yellow = recipe.yellow or 0
    local gray = recipe.gray or yellow
    local span = gray - yellow

    if state == "YELLOW" then
        if span <= 0 then return 0.50 end
        local p = (gray - skill) / span
        return math.min(1.0, math.max(0.50, p))
    elseif state == "GREEN" then
        if span <= 0 then return 0.10 end
        local p = (gray - skill) / (2.0 * span)
        return math.min(0.50, math.max(0.10, p))
    end

    return 0.0
end

function LL.LevelingEngine.GetExpectedCraftsForPoint(recipe, skill)
    local p = LL.LevelingEngine.GetSkillupProbability(recipe, skill)
    if p <= 0 then
        return math.huge
    end
    return 1.0 / p
end

-- Calculates expected crafts to level from startSkill -> min(targetSkill, recipe.gray).
-- Enforces Hard Gray Cutoff: strictly 0 crafts allowed once skill >= recipe.gray.
-- Returns: expectedCrafts (integer), pointsGained, effectiveEndSkill, rawExpectedCrafts
function LL.LevelingEngine.CalculateExpectedCrafts(recipe, startSkill, targetSkill)
    if type(recipe) ~= "table" then
        return 0, 0, startSkill or 0, 0
    end
    startSkill = math.floor(tonumber(startSkill) or 0)
    targetSkill = math.floor(tonumber(targetSkill) or startSkill)
    local gray = recipe.gray or 0

    if startSkill >= gray or targetSkill <= startSkill then
        return 0, 0, startSkill, 0
    end

    local effectiveEnd = math.min(targetSkill, gray)
    local pointsGained = effectiveEnd - startSkill
    local rawExpected = 0.0

    for s = startSkill, effectiveEnd - 1 do
        local p = LL.LevelingEngine.GetSkillupProbability(recipe, s)
        if p <= 0 then
            effectiveEnd = s
            pointsGained = effectiveEnd - startSkill
            break
        end
        rawExpected = rawExpected + (1.0 / p)
    end

    if pointsGained <= 0 or rawExpected <= 0 then
        return 0, 0, startSkill, 0
    end

    local expectedCrafts = math.ceil(rawExpected - EPSILON)
    return expectedCrafts, pointsGained, effectiveEnd, rawExpected
end

-- ============================================================================
-- 2. Stepped Order-Book Walking & Material Price Resolution
-- ============================================================================

local function CloneListings(listings)
    local copy = {}
    for _, row in ipairs(listings or {}) do
        if type(row) == "table" and (row.unitPrice or 0) > 0 and (row.quantity or 0) > 0 then
            table.insert(copy, {
                unitPrice = math.floor(row.unitPrice),
                quantity = math.floor(row.quantity),
            })
        end
    end
    table.sort(copy, function(a, b) return a.unitPrice < b.unitPrice end)
    return copy
end

-- Walks a sorted AH order book tier-by-tier for neededQty units.
-- Returns: { filledQty, totalCost, avgUnitPrice, minUnitPrice, maxUnitPrice, tiers, exhausted }
function LL.LevelingEngine.WalkOrderBook(listings, neededQty, maxBudgetCopper)
    neededQty = math.max(0, math.floor(tonumber(neededQty) or 0))
    if neededQty == 0 then
        return {
            filledQty = 0, totalCost = 0, avgUnitPrice = 0,
            minUnitPrice = 0, maxUnitPrice = 0, tiers = {}, exhausted = false,
        }
    end

    local sorted = CloneListings(listings)
    local filledQty = 0
    local totalCost = 0
    local minPrice = nil
    local maxPrice = nil
    local tiers = {}

    for _, row in ipairs(sorted) do
        local rem = neededQty - filledQty
        if rem <= 0 then break end

        local canTake = math.min(rem, row.quantity)
        if type(maxBudgetCopper) == "number" then
            local budgetLeft = maxBudgetCopper - totalCost
            if budgetLeft < row.unitPrice then
                canTake = 0
            else
                canTake = math.min(canTake, math.floor(budgetLeft / row.unitPrice))
            end
        end

        if canTake > 0 then
            local tierCost = canTake * row.unitPrice
            filledQty = filledQty + canTake
            totalCost = totalCost + tierCost
            if not minPrice then minPrice = row.unitPrice end
            maxPrice = row.unitPrice
            table.insert(tiers, {
                unitPrice = row.unitPrice,
                quantity = canTake,
                totalCost = tierCost,
            })
        else
            break
        end
    end

    local avgPrice = (filledQty > 0) and math.floor((totalCost / filledQty) + 0.5) or 0
    return {
        filledQty = filledQty,
        totalCost = totalCost,
        avgUnitPrice = avgPrice,
        minUnitPrice = minPrice or 0,
        maxUnitPrice = maxPrice or 0,
        tiers = tiers,
        exhausted = (filledQty < neededQty),
    }
end

local function ConsumeOrderBookSupply(orderBookMap, itemId, qty)
    if type(orderBookMap) ~= "table" or not orderBookMap[itemId] or qty <= 0 then return end
    local list = orderBookMap[itemId]
    local rem = qty
    local remaining = {}
    for _, row in ipairs(list) do
        if rem > 0 then
            if row.quantity <= rem then
                rem = rem - row.quantity
            else
                table.insert(remaining, { unitPrice = row.unitPrice, quantity = row.quantity - rem })
                rem = 0
            end
        else
            table.insert(remaining, { unitPrice = row.unitPrice, quantity = row.quantity })
        end
    end
    orderBookMap[itemId] = remaining
end

local function GetOrderBookForItem(itemId, customOrderBooks)
    if type(customOrderBooks) == "table" and customOrderBooks[itemId] ~= nil then
        local custom = customOrderBooks[itemId]
        if type(custom) == "table" and custom.listings then
            return custom.listings, (custom.unavailable == true), true
        elseif type(custom) == "table" then
            return custom, (#custom == 0), true
        end
    end

    local ob = LevelingLad_DB and LevelingLad_DB.orderBookCache and LevelingLad_DB.orderBookCache[itemId]
    if type(ob) == "table" then
        local now = (_G.time and _G.time()) or 0
        if (now - (ob.timestamp or 0)) <= 600 then
            return ob.listings or {}, (ob.unavailable == true), true
        end
    end

    return nil, false, false
end

function LL.LevelingEngine.ResolveAHUnitPrice(itemId, customOrderBooks)
    if not itemId or itemId <= 0 then return nil, false end
    local listings, unavailable, isOrderBook = GetOrderBookForItem(itemId, customOrderBooks)
    if isOrderBook then
        if unavailable or not listings or #listings == 0 then
            return nil, true
        end
        local walked = LL.LevelingEngine.WalkOrderBook(listings, 1)
        if walked.filledQty >= 1 and walked.minUnitPrice > 0 then
            return walked.minUnitPrice, true
        end
        return nil, true
    end

    local external = LL.ResolveExternalAHPrice and LL.ResolveExternalAHPrice(itemId)
    if external and external > 0 then
        return external, false
    end
    return nil, false
end

-- Resolves total acquisition cost for neededQty units of a single reagent.
-- Enforces VendorDatabase prices whenever includeVendorArbitrage ~= false.
function LL.LevelingEngine.ResolveReagentAcquisition(itemId, neededQty, options)
    options = options or {}
    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local useVendor = (options.includeVendorArbitrage ~= false) and (settings.includeVendorArbitrage ~= false)

    if useVendor and LL.VendorDatabase and LL.VendorDatabase.IsVendorReagent(itemId) then
        local vendorPrice = LL.VendorDatabase.GetVendorBuyPrice(itemId)
        local vendorInfo = LL.VendorDatabase.GetVendorInfo(itemId)
        return {
            itemId = itemId,
            source = "Vendor",
            vendorHint = vendorInfo and vendorInfo.vendor or "NPC Vendor",
            unitPrice = vendorPrice,
            minUnitPrice = vendorPrice,
            maxUnitPrice = vendorPrice,
            avgUnitPrice = vendorPrice,
            filledQty = neededQty,
            totalCost = vendorPrice * neededQty,
            verified = true,
            available = true,
            tiers = { { unitPrice = vendorPrice, quantity = neededQty, totalCost = vendorPrice * neededQty } },
        }
    end

    local listings, unavailable, isOrderBook = GetOrderBookForItem(itemId, options.customOrderBooks)
    if isOrderBook then
        if unavailable or not listings or #listings == 0 then
            return { itemId = itemId, source = "AH", available = false, filledQty = 0, totalCost = 0, verified = true }
        end
        local walked = LL.LevelingEngine.WalkOrderBook(listings, neededQty)
        return {
            itemId = itemId,
            source = "AH",
            unitPrice = walked.avgUnitPrice,
            minUnitPrice = walked.minUnitPrice,
            maxUnitPrice = walked.maxUnitPrice,
            avgUnitPrice = walked.avgUnitPrice,
            filledQty = walked.filledQty,
            totalCost = walked.totalCost,
            verified = true,
            available = (walked.filledQty >= neededQty and walked.totalCost > 0),
            exhausted = walked.exhausted,
            tiers = walked.tiers,
        }
    end

    local flatPrice = LL.ResolveExternalAHPrice and LL.ResolveExternalAHPrice(itemId)
    if flatPrice and flatPrice > 0 then
        return {
            itemId = itemId,
            source = "AH",
            unitPrice = flatPrice,
            minUnitPrice = flatPrice,
            maxUnitPrice = flatPrice,
            avgUnitPrice = flatPrice,
            filledQty = neededQty,
            totalCost = flatPrice * neededQty,
            verified = false,
            available = true,
            tiers = { { unitPrice = flatPrice, quantity = neededQty, totalCost = flatPrice * neededQty } },
        }
    end

    return { itemId = itemId, source = "AH", available = false, filledQty = 0, totalCost = 0, verified = false }
end

-- Computes Resale Recovery value for 1 craft based on recoveryMode ("VENDOR" | "AH" | "NONE")
function LL.LevelingEngine.GetCraftRecoveryValue(recipe, options)
    options = options or {}
    if type(recipe) ~= "table" or not recipe.outputItemId or recipe.outputItemId <= 0 or recipe.isEnchant then
        return 0, "NONE"
    end

    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local mode = (options.recoveryMode or settings.recoveryMode or "VENDOR"):upper()
    local yield = math.max(1, tonumber(recipe.outputQty) or 1)

    if mode == "NONE" then
        return 0, "NONE"
    elseif mode == "AH" then
        local ahPrice = LL.LevelingEngine.ResolveAHUnitPrice(recipe.outputItemId, options.customOrderBooks)
        if ahPrice and ahPrice > 0 then
            local ahCut = LL.GetEffectiveAHCutRate and LL.GetEffectiveAHCutRate() or 0.05
            return math.floor((ahPrice * (1 - ahCut) * yield) + 0.5), "AH"
        end
        local vSell = LL.VendorDatabase.GetVendorSellPrice(recipe.outputItemId) or 0
        return math.floor((vSell * yield) + 0.5), "VENDOR"
    end

    local vendorSell = LL.VendorDatabase.GetVendorSellPrice(recipe.outputItemId) or 0
    return math.floor((vendorSell * yield) + 0.5), "VENDOR"
end

-- Computes single-craft gross mat cost, recovery, and net cost at unit (top-of-book) prices.
function LL.LevelingEngine.GetUnitCraftEconomics(recipe, options)
    local reagents = LL.RecipeDatabase.NormalizeReagents(recipe.reagents)
    if #reagents == 0 then return nil end

    local grossMatCost = 0
    for _, reg in ipairs(reagents) do
        local acq = LL.LevelingEngine.ResolveReagentAcquisition(reg.itemId, reg.count, options)
        if not acq.available then
            return nil
        end
        grossMatCost = grossMatCost + acq.totalCost
    end

    local recovery, recoverySource = LL.LevelingEngine.GetCraftRecoveryValue(recipe, options)
    local netCraftCost = grossMatCost - recovery
    return {
        grossMatCost = grossMatCost,
        recovery = recovery,
        recoverySource = recoverySource,
        netCraftCost = netCraftCost,
    }
end

function LL.LevelingEngine.GetSinglePointCPSP(recipe, skill, options)
    local p = LL.LevelingEngine.GetSkillupProbability(recipe, skill)
    if p <= 0 then return math.huge end
    local econ = LL.LevelingEngine.GetUnitCraftEconomics(recipe, options)
    if not econ then return math.huge end
    return econ.netCraftCost / p
end

-- ============================================================================
-- 3. Dynamic Horizon & "The Green/Yellow Trap" Trainer Lookahead
-- ============================================================================

function LL.LevelingEngine.CalculateDynamicHorizon(recipe, currentSkill, targetSkill, allCandidates, options)
    options = options or {}
    local gray = recipe.gray or 0
    if currentSkill >= gray or targetSkill <= currentSkill then
        return currentSkill, "GRAY_CAP", nil
    end

    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local includeTrainer = (options.includeTrainerRecipes ~= nil) and options.includeTrainerRecipes or (settings.includeTrainerRecipes ~= false)
    local riskTolerance = (options.riskTolerance or settings.riskTolerance or "SAFE"):upper()

    local maxEnd = math.min(targetSkill, gray)
    local capReason = (maxEnd == gray and targetSkill > gray) and "GRAY_CAP" or "TARGET_REACHED"
    local handoff = nil

    local econCache = options._econCache or {}
    local function FastPointCPSP(r, s)
        local p = LL.LevelingEngine.GetSkillupProbability(r, s)
        if p <= 0 then return math.huge end
        local key = r.recipeId or r.name
        local econ = econCache[key]
        if econ == nil then
            econ = LL.LevelingEngine.GetUnitCraftEconomics(r, options) or false
            econCache[key] = econ
        end
        if not econ then return math.huge end
        return econ.netCraftCost / p
    end

    for s = currentSkill + 1, maxEnd - 1 do
        local currState = LL.LevelingEngine.GetDifficultyState(recipe, s)
        local prevState = LL.LevelingEngine.GetDifficultyState(recipe, s - 1)
        local transitioned = (currState ~= prevState)
        local myCPSP = FastPointCPSP(recipe, s)

        local bestAlt = nil
        local bestAltCPSP = myCPSP

        if type(allCandidates) == "table" then
            for _, other in ipairs(allCandidates) do
                if other ~= recipe and (other.recipeId ~= recipe.recipeId or other.name ~= recipe.name) then
                    local req = other.minSkill or other.orange or 1
                    local isNewUnlock = (req > currentSkill and req <= s)
                    local allowed = (not isNewUnlock) or includeTrainer
                    if allowed and req <= s and s < (other.gray or 0) then
                        local otherState = LL.LevelingEngine.GetDifficultyState(other, s)
                        local otherCPSP = FastPointCPSP(other, s)

                        local isCheaper = (otherCPSP + EPSILON < bestAltCPSP)
                        local safeEscapeGreen = (riskTolerance == "SAFE" and transitioned and currState == "GREEN"
                            and (otherState == "ORANGE" or otherState == "YELLOW")
                            and otherCPSP < math.huge and bestAlt == nil)

                        if (isNewUnlock and isCheaper) or (transitioned and isCheaper) or safeEscapeGreen then
                            bestAltCPSP = otherCPSP
                            bestAlt = other
                        end
                    end
                end
            end
        end

        if bestAlt then
            local altReq = bestAlt.minSkill or bestAlt.orange or 1
            local isTrainerUnlock = (altReq > currentSkill)
            capReason = isTrainerUnlock and "TRAINER_HANDOFF" or "TRANSITION_HANDOFF"
            handoff = {
                atSkill = s,
                nextRecipe = bestAlt,
                nextRecipeName = bestAlt.name,
                nextRecipeId = bestAlt.recipeId,
                nextCPSP = bestAltCPSP,
                currentCPSPAtTransition = myCPSP,
                isTrainerUnlock = isTrainerUnlock,
                source = bestAlt.source or "Trainer",
            }
            return s, capReason, handoff
        end
    end

    return maxEnd, capReason, handoff
end

-- ============================================================================
-- 4. Full Play Evaluation (Stepped Order-Book, Budget Cap, Shopping List)
-- ============================================================================

function LL.LevelingEngine.ComputeLiveInventoryState(play)
    if type(play) ~= "table" or type(play.shoppingList) ~= "table" then
        return play
    end
    local totalCashRemaining = 0
    local allReady = true
    for _, item in ipairs(play.shoppingList) do
        local inBags = (LL.Formatter and LL.Formatter.GetInventoryCount and LL.Formatter.GetInventoryCount(item.itemId, false)) or 0
        local withBank = (LL.Formatter and LL.Formatter.GetInventoryCount and LL.Formatter.GetInventoryCount(item.itemId, true)) or inBags
        local inBank = math.max(0, withBank - inBags)
        local inMail, mailSpent = 0, 0
        if LL.AHVerifier and LL.AHVerifier.GetPurchasedInMailInfo then
            inMail, mailSpent = LL.AHVerifier.GetPurchasedInMailInfo(item.itemId)
        elseif LL.AHVerifier and LL.AHVerifier.GetPurchasedInMailCount then
            inMail = LL.AHVerifier.GetPurchasedInMailCount(item.itemId) or 0
        end
        local need = item.totalQuantity or 0
        local toBuy = math.max(0, need - inBags - inMail)

        item.haveInBags = inBags
        item.haveInBank = inBank
        item.inMail = inMail
        item.purchasedInMail = inMail
        item.mailSpentCopper = mailSpent
        item.remainingToBuy = toBuy
        item.ready = (toBuy <= 0)
        if not item.ready then
            allReady = false
            totalCashRemaining = totalCashRemaining + (toBuy * (item.avgUnitPrice or 0))
        end
    end
    play.allMatsReady = allReady
    play.remainingBuyCost = totalCashRemaining

    local craftableNow = math.huge
    for _, item in ipairs(play.shoppingList) do
        local perCraft = math.max(1, item.countPerCraft or 1)
        craftableNow = math.min(craftableNow, math.floor((item.haveInBags or 0) / perCraft))
    end
    if craftableNow == math.huge then craftableNow = 0 end
    play.craftableNow = math.min(play.expectedCrafts or 0, craftableNow)
    return play
end

function LL.LevelingEngine.EvaluateCandidatePlay(recipe, currentSkill, targetSkill, allCandidates, options)
    options = options or {}
    if type(recipe) ~= "table" then return nil end

    local minSkill = recipe.minSkill or recipe.orange or 1
    if currentSkill < minSkill then return nil end
    if currentSkill >= (recipe.gray or 0) then return nil end

    local reagents = LL.RecipeDatabase.NormalizeReagents(recipe.reagents)
    if #reagents == 0 then return nil end

    local horizonEnd, capReason, handoff = LL.LevelingEngine.CalculateDynamicHorizon(
        recipe, currentSkill, targetSkill, allCandidates, options
    )
    if horizonEnd <= currentSkill then
        return nil
    end

    local effectiveBudget = options.effectiveBudget
    if effectiveBudget == nil then
        effectiveBudget = LL.GetEffectiveBudget(options.budgetOverride)
    end

    local maxPoints = horizonEnd - currentSkill
    local bestEval = nil
    local budgetCapped = false
    local supplyCapped = false

    for pts = maxPoints, 1, -1 do
        local tryEnd = currentSkill + pts
        local expectedCrafts, pointsGained, actualEnd, rawExpected =
            LL.LevelingEngine.CalculateExpectedCrafts(recipe, currentSkill, tryEnd)

        if expectedCrafts > 0 and pointsGained > 0 then
            local shoppingList = {}
            local totalGrossMatCost = 0
            local outOfPocketCost = 0
            local allAvailable = true
            local allVerified = true

            for _, reg in ipairs(reagents) do
                local totalQty = reg.count * expectedCrafts
                local inBags = options.ignoreInventory and 0
                    or ((LL.Formatter and LL.Formatter.GetInventoryCount and LL.Formatter.GetInventoryCount(reg.itemId, false)) or 0)
                local inMail = options.ignoreInventory and 0
                    or ((LL.AHVerifier and LL.AHVerifier.GetPurchasedInMailCount and LL.AHVerifier.GetPurchasedInMailCount(reg.itemId)) or 0)
                local toBuy = math.max(0, totalQty - inBags - inMail)

                local acq = LL.LevelingEngine.ResolveReagentAcquisition(reg.itemId, totalQty, options)
                if not acq.available then
                    allAvailable = false
                    break
                end

                local buyCost = 0
                if toBuy > 0 then
                    if toBuy == totalQty then
                        buyCost = acq.totalCost
                    else
                        local buyAcq = LL.LevelingEngine.ResolveReagentAcquisition(reg.itemId, toBuy, options)
                        buyCost = buyAcq.available and buyAcq.totalCost or (toBuy * acq.avgUnitPrice)
                    end
                end

                totalGrossMatCost = totalGrossMatCost + acq.totalCost
                outOfPocketCost = outOfPocketCost + buyCost
                if not acq.verified then
                    allVerified = false
                end

                local meta = LL.VendorDatabase.GetItemMetadata(reg.itemId, nil, true)
                local link = LL.Formatter.BuildItemLink(reg.itemId, reg.name or (meta and meta.name))
                table.insert(shoppingList, {
                    itemId = reg.itemId,
                    name = reg.name or (meta and meta.name) or ("Item #" .. reg.itemId),
                    link = link,
                    icon = LL.Formatter.GetItemIcon(reg.itemId),
                    source = acq.source,
                    vendorHint = acq.vendorHint,
                    countPerCraft = reg.count,
                    totalQuantity = totalQty,
                    haveInBags = inBags,
                    inMail = inMail,
                    remainingToBuy = toBuy,
                    avgUnitPrice = acq.avgUnitPrice,
                    minUnitPrice = acq.minUnitPrice,
                    maxUnitPrice = acq.maxUnitPrice,
                    totalCost = acq.totalCost,
                    buyCost = buyCost,
                    tiers = acq.tiers,
                    verified = acq.verified,
                })
            end

            if not allAvailable then
                supplyCapped = true
            elseif outOfPocketCost > effectiveBudget then
                budgetCapped = true
            else
                local recoveryPerCraft, recoveryModeUsed = LL.LevelingEngine.GetCraftRecoveryValue(recipe, options)
                local totalRecovery = recoveryPerCraft * expectedCrafts
                local totalNetCost = totalGrossMatCost - totalRecovery
                local cpsp = totalNetCost / pointsGained
                local startDiff = LL.LevelingEngine.GetDifficultyState(recipe, currentSkill)
                local endDiff = LL.LevelingEngine.GetDifficultyState(recipe, math.max(currentSkill, actualEnd - 1))
                local postDiff = LL.LevelingEngine.GetDifficultyState(recipe, actualEnd)
                local outputLink = recipe.outputItemId
                    and LL.Formatter.BuildItemLink(recipe.outputItemId, recipe.name)
                    or string.format("|cffffd100[%s]|r", recipe.name or "Recipe")

                bestEval = {
                    recipe = recipe,
                    recipeId = recipe.recipeId,
                    recipeName = recipe.name,
                    profession = recipe.profession,
                    skillLine = recipe.skillLine,
                    outputItemId = recipe.outputItemId,
                    outputQty = recipe.outputQty or 1,
                    outputLink = outputLink,
                    icon = LL.Formatter.GetItemIcon(recipe.outputItemId),
                    startSkill = currentSkill,
                    targetSkill = actualEnd,
                    goalTargetSkill = targetSkill,
                    liveSkill = currentSkill,
                    pointsGained = pointsGained,
                    expectedCrafts = expectedCrafts,
                    rawExpectedCrafts = rawExpected,
                    startDifficulty = startDiff,
                    endDifficulty = endDiff,
                    postDifficulty = postDiff,
                    grossMatCost = totalGrossMatCost,
                    outOfPocketCost = outOfPocketCost,
                    recoveryPerCraft = recoveryPerCraft,
                    totalRecovery = totalRecovery,
                    recoveryMode = recoveryModeUsed,
                    netCost = totalNetCost,
                    cpsp = cpsp,
                    cpspRounded = (cpsp >= 0) and math.floor(cpsp + 0.5) or math.ceil(cpsp - 0.5),
                    verified = allVerified,
                    needsTrainer = (recipe.needsTrainer == true),
                    source = recipe.source or "Trainer",
                    capReason = budgetCapped and "BUDGET_CAP" or (supplyCapped and "SUPPLY_CAP" or capReason),
                    budgetCapped = budgetCapped,
                    supplyCapped = supplyCapped,
                    handoff = (pts == maxPoints) and handoff or nil,
                    shoppingList = shoppingList,
                }
                LL.LevelingEngine.ComputeLiveInventoryState(bestEval)
                break
            end
        end
    end

    return bestEval
end

local DIFF_SORT_RANK = { ORANGE = 1, YELLOW = 2, GREEN = 3, GRAY = 4 }

local function SortPlaysByCPSP(a, b)
    if math.abs((a.cpsp or math.huge) - (b.cpsp or math.huge)) > EPSILON then
        return (a.cpsp or math.huge) < (b.cpsp or math.huge)
    end
    local da = DIFF_SORT_RANK[a.startDifficulty] or 4
    local db = DIFF_SORT_RANK[b.startDifficulty] or 4
    if da ~= db then
        return da < db
    end
    if (a.netCost or 0) ~= (b.netCost or 0) then
        return (a.netCost or 0) < (b.netCost or 0)
    end
    return (a.pointsGained or 0) > (b.pointsGained or 0)
end

function LL.LevelingEngine.FormatPlaySummary(rank, play)
    if not play then return "" end
    local badge = LL.Formatter.FormatDifficultyBadge(play.startDifficulty, play.endDifficulty)
    local cpspStr = LL.Formatter.FormatNetCost(play.cpspRounded or play.cpsp, true)
    local totalStr = LL.Formatter.FormatNetCost(play.netCost, true)
    local trainerLabel = (play.source and play.source ~= "" and play.source ~= "Known") and play.source or "Trainer"
    local trainerTag = play.needsTrainer and string.format(" |cff00ccff[%s]|r", trainerLabel) or ""
    return string.format(
        "#%d %s — Craft %dx (%d->%d) %s | %s/pt (Total: %s)%s",
        rank or 1,
        play.outputLink or play.recipeName or "Recipe",
        play.expectedCrafts or 0,
        play.startSkill or 0,
        play.targetSkill or 0,
        badge,
        cpspStr,
        totalStr,
        trainerTag
    )
end

-- Selects up to `limit` non-snoozed plays from an already sorted `evaluated` pool in O(M).
function LL.LevelingEngine.SelectTopPlaysFromPool(evaluated, limit, ignoreSnoozed)
    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    limit = limit or settings.topCount or 5
    local topPlays = {}
    if type(evaluated) ~= "table" then
        return topPlays
    end
    local now = (_G.time and _G.time()) or 0
    if not ignoreSnoozed and LL.PruneExpiredSnoozes then
        LL.PruneExpiredSnoozes(now)
    end

    for _, p in ipairs(evaluated) do
        local snoozed = (not ignoreSnoozed) and LL.IsPlaySnoozed and LL.IsPlaySnoozed(p, now)
        if not snoozed then
            local idx = #topPlays + 1
            p.rank = idx
            p.summaryLine = LL.LevelingEngine.FormatPlaySummary(idx, p)
            table.insert(topPlays, p)
            if idx >= limit then
                break
            end
        end
    end
    return topPlays
end

-- Finds the Top N (default 5) cheapest leveling plays for the profession at currentSkill.
-- Hides snoozed plays from Top N unless `options.ignoreSnoozed == true` (Milestone Path sets ignoreSnoozed=true).
-- Returns: topPlays, allEvaluated
function LL.LevelingEngine.FindTopPlays(professionOrLine, currentSkill, targetSkill, options)
    options = options or {}
    local activeProf = LL.RecipeScanner and LL.RecipeScanner.GetActiveProfession and LL.RecipeScanner.GetActiveProfession() or { skillLine = 164, rank = 1, maxRank = 75 }
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(professionOrLine) or activeProf.skillLine or 164
    local detectedRank, detectedMax = LL.RecipeScanner and LL.RecipeScanner.GetProfessionSkill and LL.RecipeScanner.GetProfessionSkill(skillLine)

    currentSkill = math.floor(tonumber(currentSkill) or detectedRank or activeProf.rank or 1)
    local maxRank = detectedMax or activeProf.maxRank or 300
    targetSkill = LL.GetTargetSkill(currentSkill, maxRank, targetSkill)

    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local limit = options.limit or settings.topCount or 5
    local effectiveBudget = LL.GetEffectiveBudget(options.budgetOverride)
    local evalOpts = {
        budgetOverride = options.budgetOverride,
        effectiveBudget = effectiveBudget,
        customOrderBooks = options.customOrderBooks,
        recoveryMode = options.recoveryMode,
        riskTolerance = options.riskTolerance,
        includeTrainerRecipes = options.includeTrainerRecipes,
        includeVendorArbitrage = options.includeVendorArbitrage,
        ignoreInventory = options.ignoreInventory,
        _econCache = {},
    }

    local candidates = options.customRecipes
        or (LL.RecipeScanner and LL.RecipeScanner.GetRecipesForProfession and LL.RecipeScanner.GetRecipesForProfession(skillLine, evalOpts.includeTrainerRecipes))
        or LL.RecipeDatabase.GetRecipesForProfession(skillLine)

    local evaluated = {}
    for _, recipe in ipairs(candidates) do
        local play = LL.LevelingEngine.EvaluateCandidatePlay(recipe, currentSkill, targetSkill, candidates, evalOpts)
        if play then
            table.insert(evaluated, play)
        end
    end

    table.sort(evaluated, SortPlaysByCPSP)

    local topPlays = LL.LevelingEngine.SelectTopPlaysFromPool(evaluated, limit, options.ignoreSnoozed == true)
    return topPlays, evaluated
end

-- ============================================================================
-- 5. Milestone Pathing / Multi-Step Roadmap Planner (e.g., 1 -> 75, 1 -> 300)
-- ============================================================================

local function DeepCloneOrderBooks(sourceOrderBooks)
    local cloned = {}
    if type(sourceOrderBooks) == "table" then
        for itemId, entry in pairs(sourceOrderBooks) do
            if type(entry) == "table" and entry.listings then
                cloned[itemId] = { listings = CloneListings(entry.listings), unavailable = entry.unavailable }
            elseif type(entry) == "table" then
                cloned[itemId] = CloneListings(entry)
            end
        end
    end
    return cloned
end

-- Builds a chained multi-recipe leveling roadmap from startSkill to targetSkill.
--Snoozed Top 5 plays remain usable in Milestone Path (`ignoreSnoozed = true` by default).
function LL.LevelingEngine.PlanMilestonePath(professionOrLine, startSkill, targetSkill, options)
    options = options or {}
    local activeProf = LL.RecipeScanner and LL.RecipeScanner.GetActiveProfession and LL.RecipeScanner.GetActiveProfession() or { skillLine = 164, rank = 1, maxRank = 300 }
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(professionOrLine) or activeProf.skillLine or 164
    local profName = LL.RecipeDatabase.GetProfessionName(skillLine) or "Crafting"

    local detectedRank, detectedMax = LL.RecipeScanner and LL.RecipeScanner.GetProfessionSkill and LL.RecipeScanner.GetProfessionSkill(skillLine)
    local curSkill = math.floor(tonumber(startSkill) or detectedRank or activeProf.rank or 1)
    local goalSkill = LL.GetTargetSkill(curSkill, math.max(300, detectedMax or 300), targetSkill)

    local initialBudget = LL.GetEffectiveBudget(options.budgetOverride)
    local remainingBudget = initialBudget
    local virtualOrderBooks = options.customOrderBooks and DeepCloneOrderBooks(options.customOrderBooks) or nil

    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local includeTrainer = (options.includeTrainerRecipes ~= nil) and options.includeTrainerRecipes or (settings.includeTrainerRecipes ~= false)
    local ignoreSnoozed = (options.ignoreSnoozed ~= false)

    local candidates = options.customRecipes
        or (LL.RecipeScanner and LL.RecipeScanner.GetRecipesForProfession and LL.RecipeScanner.GetRecipesForProfession(skillLine, includeTrainer))
        or LL.RecipeDatabase.GetRecipesForProfession(skillLine)

    local steps = {}
    local aggregateReagents = {}
    local totalGrossCost = 0
    local totalRecovery = 0
    local totalNetCost = 0
    local totalCrafts = 0
    local stoppedReason = "TARGET_REACHED"
    local safetyIterations = 0
    local startAnchor = curSkill

    while curSkill < goalSkill and safetyIterations < 100 do
        safetyIterations = safetyIterations + 1

        local stepOpts = {
            budgetOverride = remainingBudget,
            effectiveBudget = remainingBudget,
            customOrderBooks = virtualOrderBooks,
            recoveryMode = options.recoveryMode,
            riskTolerance = options.riskTolerance,
            includeTrainerRecipes = includeTrainer,
            includeVendorArbitrage = options.includeVendorArbitrage,
            ignoreInventory = (options.ignoreInventory ~= false),
            ignoreSnoozed = ignoreSnoozed,
            customRecipes = candidates,
            limit = 1,
        }

        local topPlays = LL.LevelingEngine.FindTopPlays(skillLine, curSkill, goalSkill, stepOpts)
        local best = topPlays and topPlays[1]
        if not best or best.pointsGained <= 0 or best.expectedCrafts <= 0 then
            local unlimitedCheck = LL.LevelingEngine.FindTopPlays(skillLine, curSkill, goalSkill, {
                budgetOverride = 1e12,
                customOrderBooks = virtualOrderBooks,
                recoveryMode = options.recoveryMode,
                riskTolerance = options.riskTolerance,
                includeTrainerRecipes = includeTrainer,
                includeVendorArbitrage = options.includeVendorArbitrage,
                ignoreInventory = true,
                ignoreSnoozed = ignoreSnoozed,
                customRecipes = candidates,
                limit = 1,
            })
            if unlimitedCheck and unlimitedCheck[1] then
                stoppedReason = "BUDGET_EXHAUSTED"
            else
                stoppedReason = "NO_ELIGIBLE_RECIPE"
            end
            break
        end

        remainingBudget = math.max(0, remainingBudget - best.outOfPocketCost)
        if virtualOrderBooks then
            for _, shop in ipairs(best.shoppingList) do
                if shop.source == "AH" then
                    if virtualOrderBooks[shop.itemId] and virtualOrderBooks[shop.itemId].listings then
                        ConsumeOrderBookSupply(virtualOrderBooks[shop.itemId], "listings", shop.totalQuantity)
                    else
                        ConsumeOrderBookSupply(virtualOrderBooks, shop.itemId, shop.totalQuantity)
                    end
                end
            end
        end

        for _, shop in ipairs(best.shoppingList) do
            local agg = aggregateReagents[shop.itemId]
            if not agg then
                agg = {
                    itemId = shop.itemId,
                    name = shop.name,
                    link = shop.link,
                    icon = shop.icon,
                    source = shop.source,
                    vendorHint = shop.vendorHint,
                    countPerCraft = shop.countPerCraft,
                    totalQuantity = 0,
                    totalCost = 0,
                    minUnitPrice = shop.minUnitPrice,
                    maxUnitPrice = shop.maxUnitPrice,
                    verified = shop.verified,
                }
                aggregateReagents[shop.itemId] = agg
            end
            agg.totalQuantity = agg.totalQuantity + shop.totalQuantity
            agg.totalCost = agg.totalCost + shop.totalCost
            agg.minUnitPrice = math.min(agg.minUnitPrice or shop.minUnitPrice, shop.minUnitPrice or 0)
            agg.maxUnitPrice = math.max(agg.maxUnitPrice or shop.maxUnitPrice, shop.maxUnitPrice or 0)
            agg.avgUnitPrice = math.floor((agg.totalCost / math.max(1, agg.totalQuantity)) + 0.5)
            agg.verified = agg.verified and shop.verified
        end

        best.stepNumber = #steps + 1
        table.insert(steps, best)
        totalGrossCost = totalGrossCost + best.grossMatCost
        totalRecovery = totalRecovery + best.totalRecovery
        totalNetCost = totalNetCost + best.netCost
        totalCrafts = totalCrafts + best.expectedCrafts
        curSkill = best.targetSkill

        if best.budgetCapped and curSkill < goalSkill then
            stoppedReason = "BUDGET_EXHAUSTED"
            break
        end
    end

    local shoppingList = {}
    for _, item in pairs(aggregateReagents) do
        table.insert(shoppingList, item)
    end
    table.sort(shoppingList, function(a, b)
        if a.source ~= b.source then
            return a.source == "AH"
        end
        return (a.name or "") < (b.name or "")
    end)

    local pointsTotal = curSkill - startAnchor
    local roadmap = {
        isRoadmap = true,
        profession = profName,
        skillLine = skillLine,
        startSkill = startAnchor,
        requestedTargetSkill = goalSkill,
        reachedSkill = curSkill,
        pointsGained = pointsTotal,
        reachedTarget = (curSkill >= goalSkill),
        stoppedReason = (curSkill >= goalSkill) and "TARGET_REACHED" or stoppedReason,
        budgetExhausted = (stoppedReason == "BUDGET_EXHAUSTED"),
        initialBudget = initialBudget,
        remainingBudget = remainingBudget,
        totalCrafts = totalCrafts,
        totalGrossCost = totalGrossCost,
        totalRecovery = totalRecovery,
        totalNetCost = totalNetCost,
        avgCPSP = (pointsTotal > 0) and (totalNetCost / pointsTotal) or 0,
        steps = steps,
        shoppingList = shoppingList,
    }
    LL.LevelingEngine.ComputeLiveInventoryState(roadmap)
    return roadmap
end
