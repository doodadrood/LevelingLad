local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.AHVerifier = {}

local verifierFrame = CreateFrame("Frame")
local isRunning = false
local runToken = 0
local startTime = 0
local verifyQueue = {}
local verifyIndex = 0
local currentQueryItem = nil
local onUpdateCallback = nil
local onFinishCallback = nil
local verifiedInSession = {}
local activeQueuedIds = {}
local knownItemKeys = {}
local activeSearchItemId = nil
local activeSearchItemKey = nil
local activeSearchDesiredQty = nil
local pendingOpenItemKey = nil
local pendingSearchCheck = nil
local openSearchToken = 0
local pendingCommodityConfirm = nil
local inFlightCommodityPurchase = nil
local inFlightItemPurchases = {}
local purchasedAuctionIds = {}
local purchaseDedupQueue = {}

local orderBookRevision = 0
local lastEvaluatedPool = nil
local lastPoolSignature = nil

local MAX_ORDERBOOK_ROWS = 60
local MAX_ORDERBOOK_QTY = 600
local MAX_VERIFY_QUEUE = 25
local PURCHASED_MAIL_TTL_SECONDS = 7200

local function SafeRegisterEvent(frame, eventName)
    if frame and frame.RegisterEvent then
        pcall(frame.RegisterEvent, frame, eventName)
    end
end

function LL.AHVerifier.GetOrderBookRevision()
    return orderBookRevision
end

function LL.AHVerifier.InvalidateEvaluatedPool()
    lastEvaluatedPool = nil
    lastPoolSignature = nil
end

function LL.AHVerifier.IsAuctionHouseOpen()
    if _G.AuctionHouseFrame and (not _G.AuctionHouseFrame.IsShown or _G.AuctionHouseFrame:IsShown()) then
        return true
    end
    if _G.AuctionFrame and (not _G.AuctionFrame.IsShown or _G.AuctionFrame:IsShown()) then
        return true
    end
    return false
end

function LL.AHVerifier.IsRunning()
    return isRunning
end

function LL.AHVerifier.MakeItemKey(itemId)
    if itemId and knownItemKeys[itemId] then
        return knownItemKeys[itemId]
    end
    if _G.C_AuctionHouse and _G.C_AuctionHouse.MakeItemKey then
        local ok, key = pcall(_G.C_AuctionHouse.MakeItemKey, itemId)
        if ok and type(key) == "table" then
            return key
        end
    end
    return { itemID = itemId, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
end

local function HarvestBrowseResultItemKeys(results)
    if not results and _G.C_AuctionHouse and _G.C_AuctionHouse.GetBrowseResults then
        local ok, br = pcall(_G.C_AuctionHouse.GetBrowseResults)
        if ok and type(br) == "table" then
            results = br
        end
    end
    if type(results) ~= "table" then return end
    for _, row in ipairs(results) do
        local ik = type(row) == "table" and row.itemKey
        if type(ik) == "table" and type(ik.itemID) == "number" and ik.itemID > 0 then
            if not knownItemKeys[ik.itemID] or (ik.itemLevel or 0) > 0 or (ik.itemSuffix or 0) > 0 then
                knownItemKeys[ik.itemID] = ik
            end
        end
    end
end

local function IsBuyoutOnlyEnabled()
    if LevelingLad_DB and LevelingLad_DB.settings and LevelingLad_DB.settings.buyoutOnly == false then
        return false
    end
    return true
end

function LL.AHVerifier.RecordOrderBook(itemId, listings)
    if not itemId or itemId <= 0 or type(listings) ~= "table" then
        return
    end

    local byPrice = {}
    local merged = {}
    local minUnit = nil
    local totalCount = 0

    for _, row in ipairs(listings) do
        local up = row and row.unitPrice and math.floor(row.unitPrice)
        local qty = row and row.quantity and math.floor(row.quantity)
        if up and up > 0 and qty and qty > 0 then
            totalCount = totalCount + qty
            if not minUnit or up < minUnit then
                minUnit = up
            end
            if not byPrice[up] then
                byPrice[up] = { unitPrice = up, quantity = qty }
                table.insert(merged, byPrice[up])
            else
                byPrice[up].quantity = byPrice[up].quantity + qty
            end
        end
    end

    table.sort(merged, function(a, b) return a.unitPrice < b.unitPrice end)

    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.orderBookCache = LevelingLad_DB.orderBookCache or {}
    LevelingLad_DB.orderBookCache[itemId] = {
        timestamp = (_G.time and _G.time()) or 0,
        listings = merged,
        unavailable = (#merged == 0),
    }

    if minUnit and totalCount > 0 then
        _G.PCF_DB = _G.PCF_DB or {}
        _G.PCF_DB.prices = _G.PCF_DB.prices or {}
        _G.PCF_DB.prices[itemId] = {
            minBuyout = minUnit,
            minBid = minUnit,
            lastUpdated = (_G.time and _G.time()) or 0,
            count = totalCount,
            source = "Leveling Lad Live",
        }
    end

    orderBookRevision = orderBookRevision + 1
    LL.AHVerifier.InvalidateEvaluatedPool()
    if LL.InvalidateAHStatusCache then
        LL.InvalidateAHStatusCache()
    end
end

function LL.AHVerifier.EvictUnavailableItem(itemId)
    if not itemId or itemId <= 0 then return end
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.orderBookCache = LevelingLad_DB.orderBookCache or {}
    LevelingLad_DB.orderBookCache[itemId] = {
        timestamp = (_G.time and _G.time()) or 0,
        listings = {},
        unavailable = true,
    }
    orderBookRevision = orderBookRevision + 1
    LL.AHVerifier.InvalidateEvaluatedPool()
    if LL.InvalidateAHStatusCache then
        LL.InvalidateAHStatusCache()
    end
end

-- ============================================================================
-- Pool Signature & Fast O(M) Snooze Rotation Cache
-- ============================================================================

local function BuildPoolSignature(skillLine)
    local s = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local activeProf = LL.RecipeScanner and LL.RecipeScanner.GetActiveProfession and LL.RecipeScanner.GetActiveProfession() or { skillLine = 164, rank = 1, maxRank = 75 }
    local resolvedLine = LL.RecipeDatabase.ResolveSkillLineId(skillLine) or activeProf.skillLine or 164
    local rank, maxRank = LL.RecipeScanner and LL.RecipeScanner.GetProfessionSkill and LL.RecipeScanner.GetProfessionSkill(resolvedLine)
    local curSkill = rank or activeProf.rank or 1
    local targetSkill = LL.GetTargetSkill(curSkill, maxRank or activeProf.maxRank or 300)
    local ahStatus, ahInfo = "FRESH", nil
    if LL.GetAHDataStatus then
        ahStatus, ahInfo = LL.GetAHDataStatus()
    end

    return {
        dbRef = LevelingLad_DB,
        orderBookCacheRef = LevelingLad_DB and LevelingLad_DB.orderBookCache,
        orderBookRev = orderBookRevision,
        skillLine = resolvedLine,
        curSkill = curSkill,
        targetSkill = targetSkill,
        budget = LL.GetEffectiveBudget(),
        ahCut = LL.GetEffectiveAHCutRate(),
        mode = LL.GetPriceSourceMode and LL.GetPriceSourceMode() or "AUTO",
        ahStatus = ahStatus,
        lastScanTs = (ahInfo and ahInfo.lastScanTimestamp) or 0,
        itemCount = (ahInfo and ahInfo.itemCount) or 0,
        activeSource = (ahInfo and ahInfo.activeSource) or "None",
        pcfPricesRef = _G.PCF_DB and _G.PCF_DB.prices,
        atrTableRef = (LL.AuctionatorSource and LL.AuctionatorSource.GetRealmPriceTable and LL.AuctionatorSource.GetRealmPriceTable()) or nil,
        atrRev = (LL.AuctionatorSource and LL.AuctionatorSource.GetCacheRevision and LL.AuctionatorSource.GetCacheRevision()) or 0,
        recipeRev = (LL.RecipeScanner and LL.RecipeScanner.GetCacheRevision and LL.RecipeScanner.GetCacheRevision()) or 0,
        recoveryMode = s.recoveryMode or "VENDOR",
        riskTolerance = s.riskTolerance or "SAFE",
        includeTrainer = (s.includeTrainerRecipes ~= false),
        includeVendor = (s.includeVendorArbitrage ~= false),
        buyoutOnly = (s.buyoutOnly ~= false),
        topCount = s.topCount or 5,
    }
end

local function PoolSignaturesMatch(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end
    return true
end

function LL.AHVerifier.StoreEvaluatedPool(skillLine, evaluatedPool)
    if type(evaluatedPool) == "table" then
        lastEvaluatedPool = evaluatedPool
        lastPoolSignature = BuildPoolSignature(skillLine)
    end
end

-- ============================================================================
-- Stepped Tier Order-Book Verification & Dynamic Price Circuit Breaker
-- ============================================================================

function LL.AHVerifier.VerifyPlayWithCircuitBreaker(play, runnerUpCPSP, customOrderBooks)
    if type(play) ~= "table" or not play.recipe then
        return { verified = false, circuitBreakerTripped = false, pivotRecommended = false }
    end

    local recipe = play.recipe
    local startSkill = play.startSkill or 1
    local targetSkill = play.targetSkill or (startSkill + 1)
    local maxPoints = math.max(1, targetSkill - startSkill)
    local reagents = LL.RecipeDatabase.NormalizeReagents(recipe.reagents)
    local evalOpts = { customOrderBooks = customOrderBooks }
    local recoveryPerCraft = LL.LevelingEngine.GetCraftRecoveryValue(recipe, evalOpts)
    local effectiveBudget = LL.GetEffectiveBudget()

    local safePoints = 0
    local safeCrafts = 0
    local prevTotalNetCost = 0
    local tripped = false
    local tripReason = nil
    local tripAtSkill = nil
    local finalGross = 0
    local finalNet = 0
    local finalCPSP = math.huge
    local tiersByItem = {}
    local allItemsVerified = true

    for pts = 1, maxPoints do
        local craftsNeeded = LL.LevelingEngine.CalculateExpectedCrafts(recipe, startSkill, startSkill + pts)
        local grossForPts = 0
        local supplyOK = true
        local currentTiers = {}

        for _, reg in ipairs(reagents) do
            local qty = reg.count * craftsNeeded
            local acq = LL.LevelingEngine.ResolveReagentAcquisition(reg.itemId, qty, evalOpts)
            if not acq.available then
                supplyOK = false
                tripReason = "SUPPLY_EXHAUSTED"
                break
            end
            if not acq.verified then
                allItemsVerified = false
            end
            grossForPts = grossForPts + acq.totalCost
            currentTiers[reg.itemId] = acq.tiers
        end

        if not supplyOK then
            tripped = true
            tripAtSkill = startSkill + pts - 1
            break
        end

        if grossForPts > effectiveBudget then
            tripped = true
            tripReason = "BUDGET_EXCEEDED"
            tripAtSkill = startSkill + pts - 1
            break
        end

        local netForPts = grossForPts - (recoveryPerCraft * craftsNeeded)
        local cumulativeCPSP = netForPts / pts
        local marginalCPSP = (pts == 1) and cumulativeCPSP or (netForPts - prevTotalNetCost)

        if type(runnerUpCPSP) == "number" and runnerUpCPSP < math.huge then
            if cumulativeCPSP > (runnerUpCPSP + 1e-6) or marginalCPSP > (runnerUpCPSP + 1e-6) then
                tripped = true
                tripReason = "PRICE_SPIKE_EXCEEDS_RUNNER_UP"
                tripAtSkill = startSkill + pts - 1
                finalGross = grossForPts
                finalNet = netForPts
                finalCPSP = cumulativeCPSP
                tiersByItem = currentTiers
                break
            end
        end

        safePoints = pts
        safeCrafts = craftsNeeded
        prevTotalNetCost = netForPts
        finalGross = grossForPts
        finalNet = netForPts
        finalCPSP = cumulativeCPSP
        tiersByItem = currentTiers
    end

    local result = {
        verified = allItemsVerified,
        circuitBreakerTripped = tripped,
        pivotRecommended = tripped and (tripReason == "PRICE_SPIKE_EXCEEDS_RUNNER_UP" or tripReason == "SUPPLY_EXHAUSTED"),
        reason = tripReason or "OK",
        safePointsBeforeSpike = safePoints,
        safeCraftsBeforeSpike = safeCrafts,
        tripAtSkill = tripAtSkill,
        liveGrossCost = finalGross,
        liveNetCost = finalNet,
        liveCPSP = finalCPSP,
        runnerUpCPSP = runnerUpCPSP,
        tiersByItem = tiersByItem,
    }

    play.circuitBreaker = result
    play.verified = allItemsVerified
    return result
end

function LL.AHVerifier.EvaluateCircuitBreakersOnPlays(plays, customOrderBooks)
    if type(plays) ~= "table" or #plays == 0 then return plays, false end
    for _, p in ipairs(plays) do
        p.circuitBreakerNotice = nil
    end
    local pivoted = false
    local runnerUp = plays[2]
    local runnerUpCPSP = runnerUp and runnerUp.cpsp or nil

    local res = LL.AHVerifier.VerifyPlayWithCircuitBreaker(plays[1], runnerUpCPSP, customOrderBooks)
    if res.pivotRecommended and runnerUp then
        if (res.safeCraftsBeforeSpike or 0) == 0 then
            plays[1], plays[2] = plays[2], plays[1]
            plays[1].rank = 1
            plays[2].rank = 2
            plays[1].summaryLine = LL.LevelingEngine.FormatPlaySummary(1, plays[1])
            plays[2].summaryLine = LL.LevelingEngine.FormatPlaySummary(2, plays[2])
            plays[1].pivotedFromCircuitBreaker = true
            pivoted = true
        else
            plays[1].circuitBreakerNotice = string.format(
                "Price spikes after %dx crafts (%d->%d) — pivot to [%s] afterward!",
                res.safeCraftsBeforeSpike,
                plays[1].startSkill,
                plays[1].startSkill + res.safePointsBeforeSpike,
                runnerUp.recipeName or "Candidate #2"
            )
        end
    end

    return plays, pivoted
end

function LL.AHVerifier.RecalculateFromCache(professionOrLine)
    local active = LL.RecipeScanner and LL.RecipeScanner.GetActiveProfession and LL.RecipeScanner.GetActiveProfession()
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(professionOrLine) or (active and active.skillLine) or 164
    local topPlays, allEvaluated = LL.LevelingEngine.FindTopPlays(skillLine)
    topPlays = LL.AHVerifier.EvaluateCircuitBreakersOnPlays(topPlays)
    lastEvaluatedPool = allEvaluated
    lastPoolSignature = BuildPoolSignature(skillLine)
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.lastTopPlays = topPlays
    return topPlays, allEvaluated
end

-- Fast O(M) rotation for Snooze / Unsnooze: re-selects Top 5 directly from `lastEvaluatedPool`
-- without re-evaluating recipes or re-querying the AH when prices, skill, and settings match.
function LL.AHVerifier.RefreshForSnoozeChange(professionOrLine)
    local active = LL.RecipeScanner and LL.RecipeScanner.GetActiveProfession and LL.RecipeScanner.GetActiveProfession()
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(professionOrLine) or (active and active.skillLine) or 164
    if type(lastEvaluatedPool) == "table"
        and lastPoolSignature
        and LL.LevelingEngine
        and LL.LevelingEngine.SelectTopPlaysFromPool then
        local curSig = BuildPoolSignature(skillLine)
        if curSig.ahStatus ~= "NO_DATA" and PoolSignaturesMatch(lastPoolSignature, curSig) then
            local topPlays = LL.LevelingEngine.SelectTopPlaysFromPool(lastEvaluatedPool, curSig.topCount, false)
            topPlays = LL.AHVerifier.EvaluateCircuitBreakersOnPlays(topPlays)
            LevelingLad_DB = LevelingLad_DB or {}
            LevelingLad_DB.lastTopPlays = topPlays
            return topPlays, true
        end
    end
    local topPlays = LL.AHVerifier.RecalculateFromCache(skillLine)
    return topPlays, false
end

-- ============================================================================
-- Live Auction House Order-Book Scanning Loop (Legacy & Modern C_AuctionHouse)
-- ============================================================================

local function CollectLegacyQueryResults(targetItem)
    if not _G.GetNumAuctionItems or not _G.GetAuctionItemInfo then
        return false
    end
    local numBatch = _G.GetNumAuctionItems("list") or 0
    local buyoutOnly = IsBuyoutOnlyEnabled()
    local listings = {}
    local sawMatch = false

    for i = 1, numBatch do
        local name, _, count, _, _, _, _, minBid, _, buyoutPrice, _, _, _, _, _, _, itemId = _G.GetAuctionItemInfo("list", i)
        if (not itemId or itemId <= 0) and _G.GetAuctionItemLink then
            local link = _G.GetAuctionItemLink("list", i)
            if type(link) == "string" then
                itemId = tonumber(link:match("item:(%d+)"))
            end
        end
        local matchesId = (itemId and itemId == targetItem.itemId)
        local matchesName = (not itemId and name and targetItem.name and name:lower() == targetItem.name:lower())
        if matchesId or matchesName then
            sawMatch = true
            local effectivePrice = (buyoutPrice and buyoutPrice > 0) and buyoutPrice or nil
            if not effectivePrice and not buyoutOnly then
                effectivePrice = (minBid and minBid > 0) and minBid or nil
            end
            if effectivePrice and effectivePrice > 0 and count and count > 0 then
                local unitPrice = math.floor(effectivePrice / count)
                if unitPrice > 0 then
                    table.insert(listings, { unitPrice = unitPrice, quantity = count })
                end
            end
        end
    end

    if #listings > 0 then
        LL.AHVerifier.RecordOrderBook(targetItem.itemId, listings)
        verifiedInSession[targetItem.itemId] = true
        return true
    end
    if sawMatch then
        LL.AHVerifier.EvictUnavailableItem(targetItem.itemId)
    end
    return false
end

local function CollectModernCommodityResults(itemId)
    if not _G.C_AuctionHouse or not _G.C_AuctionHouse.GetNumCommoditySearchResults or not _G.C_AuctionHouse.GetCommoditySearchResultInfo then
        return false
    end
    local okNum, num = pcall(_G.C_AuctionHouse.GetNumCommoditySearchResults, itemId)
    if not okNum or not num or num <= 0 then
        if okNum and num == 0 then
            LL.AHVerifier.EvictUnavailableItem(itemId)
        end
        return false
    end
    local listings = {}
    local limit = math.min(num, MAX_ORDERBOOK_ROWS)
    local accumQty = 0
    for i = 1, limit do
        local okRow, row = pcall(_G.C_AuctionHouse.GetCommoditySearchResultInfo, itemId, i)
        if okRow and type(row) == "table" and row.unitPrice and row.unitPrice > 0 and row.quantity and row.quantity > 0 then
            local availQty = math.floor(row.quantity) - math.floor(tonumber(row.numOwnerItems) or 0)
            if availQty > 0 then
                table.insert(listings, { unitPrice = math.floor(row.unitPrice), quantity = availQty })
                accumQty = accumQty + availQty
                if accumQty >= MAX_ORDERBOOK_QTY then break end
            end
        end
    end
    if #listings > 0 then
        LL.AHVerifier.RecordOrderBook(itemId, listings)
        verifiedInSession[itemId] = true
        return true
    end
    LL.AHVerifier.EvictUnavailableItem(itemId)
    return false
end

local function CollectModernItemResults(itemId, itemKey)
    if not _G.C_AuctionHouse or not _G.C_AuctionHouse.GetNumItemSearchResults or not _G.C_AuctionHouse.GetItemSearchResultInfo then
        return false
    end
    itemKey = itemKey or activeSearchItemKey or LL.AHVerifier.MakeItemKey(itemId)
    local okNum, num = pcall(_G.C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not okNum or not num or num <= 0 then
        if okNum and num == 0 then
            LL.AHVerifier.EvictUnavailableItem(itemId)
        end
        return false
    end
    local buyoutOnly = IsBuyoutOnlyEnabled()
    local listings = {}
    local limit = math.min(num, MAX_ORDERBOOK_ROWS)
    local accumQty = 0
    for i = 1, limit do
        local okRow, row = pcall(_G.C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        if okRow and type(row) == "table" and not row.containsOwnerItem and not row.containsAccountItem then
            local buyout = (row.buyoutAmount and row.buyoutAmount > 0) and row.buyoutAmount or nil
            if not buyout and not buyoutOnly then
                buyout = row.bidAmount or row.minBid
            end
            local qty = (row.quantity and row.quantity > 0) and math.floor(row.quantity) or 1
            if buyout and buyout > 0 then
                table.insert(listings, { unitPrice = math.floor(buyout), quantity = qty })
                accumQty = accumQty + qty
                if accumQty >= MAX_ORDERBOOK_QTY then break end
            end
        end
    end
    if #listings > 0 then
        LL.AHVerifier.RecordOrderBook(itemId, listings)
        verifiedInSession[itemId] = true
        return true
    end
    LL.AHVerifier.EvictUnavailableItem(itemId)
    return false
end

local ScheduleNextVerification

local function FinalizeRun(reason, professionOrLine)
    isRunning = false
    currentQueryItem = nil
    runToken = runToken + 1

    local topPlays, allEvaluated = LL.LevelingEngine.FindTopPlays(professionOrLine)
    topPlays = LL.AHVerifier.EvaluateCircuitBreakersOnPlays(topPlays)
    lastEvaluatedPool = allEvaluated
    lastPoolSignature = BuildPoolSignature(professionOrLine)

    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.lastTopPlays = topPlays

    if onFinishCallback then
        onFinishCallback(topPlays, reason or "COMPLETE")
    end
    if LL.SideWindow and LL.SideWindow.RefreshIfShown then
        LL.SideWindow.RefreshIfShown()
    elseif LL.SideWindow and LL.SideWindow.Refresh then
        LL.SideWindow.Refresh()
    end
    if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
        LL.DetailWindow.RefreshIfShown()
    end
end

function LL.AHVerifier.Stop(reason)
    if not isRunning then return end
    FinalizeRun(reason or "STOPPED")
end

local activeVerifyProfession = nil

ScheduleNextVerification = function(delay)
    if not isRunning then return end
    local myToken = runToken

    if not _G.C_Timer or not _G.C_Timer.After then
        FinalizeRun("COMPLETE", activeVerifyProfession)
        return
    end

    _G.C_Timer.After(delay or 0.15, function()
        if not isRunning or runToken ~= myToken then return end

        local maxSec = (LevelingLad_DB and LevelingLad_DB.settings and LevelingLad_DB.settings.maxCalculationSeconds) or 90
        if (((_G.GetTime and _G.GetTime()) or 0) - startTime) >= maxSec then
            FinalizeRun("TIMEOUT", activeVerifyProfession)
            return
        end

        verifyIndex = verifyIndex + 1
        if verifyIndex > #verifyQueue then
            FinalizeRun("COMPLETE", activeVerifyProfession)
            return
        end

        local target = verifyQueue[verifyIndex]
        currentQueryItem = target

        if onUpdateCallback then
            onUpdateCallback(verifyIndex, #verifyQueue, target)
        elseif LL.SideWindow and LL.SideWindow.UpdateProgress then
            LL.SideWindow.UpdateProgress(verifyIndex, #verifyQueue, target)
        end

        if LL.AHVerifier.IsAuctionHouseOpen() then
            if _G.QueryAuctionItems and _G.CanSendAuctionQuery and (not _G.AuctionHouseFrame or not _G.AuctionHouseFrame:IsShown()) then
                if _G.CanSendAuctionQuery() then
                    SafeRegisterEvent(verifierFrame, "AUCTION_ITEM_LIST_UPDATE")
                    pcall(_G.QueryAuctionItems, target.name or "", nil, nil, 0, 0, 0, 0, false, -1, false)
                    _G.C_Timer.After(2.5, function()
                        if isRunning and runToken == myToken and currentQueryItem == target then
                            ScheduleNextVerification(0.05)
                        end
                    end)
                    return
                else
                    verifyIndex = verifyIndex - 1
                    ScheduleNextVerification(0.25)
                    return
                end
            elseif _G.C_AuctionHouse and _G.C_AuctionHouse.SendSearchQuery then
                if _G.C_AuctionHouse.IsThrottledMessageSystemReady and not _G.C_AuctionHouse.IsThrottledMessageSystemReady() then
                    verifyIndex = verifyIndex - 1
                    ScheduleNextVerification(0.25)
                    return
                end
                SafeRegisterEvent(verifierFrame, "COMMODITY_SEARCH_RESULTS_UPDATED")
                SafeRegisterEvent(verifierFrame, "ITEM_SEARCH_RESULTS_UPDATED")
                local itemKey = LL.AHVerifier.MakeItemKey(target.itemId)
                local sorts = { { sortOrder = 0, reverseSort = false } }
                pcall(_G.C_AuctionHouse.SendSearchQuery, itemKey, sorts, false)
                _G.C_Timer.After(2.5, function()
                    if isRunning and runToken == myToken and currentQueryItem == target then
                        ScheduleNextVerification(0.05)
                    end
                end)
                return
            end
        end

        FinalizeRun("AH_CLOSED", activeVerifyProfession)
    end)
end

function LL.AHVerifier.StartVerification(professionOrLine, callbacks)
    callbacks = callbacks or {}
    onUpdateCallback = callbacks.onUpdate
    onFinishCallback = callbacks.onFinish
    activeVerifyProfession = professionOrLine

    HarvestBrowseResultItemKeys()

    isRunning = true
    runToken = runToken + 1
    startTime = (_G.GetTime and _G.GetTime()) or 0
    verifiedInSession = {}
    verifyQueue = {}
    verifyIndex = 0
    currentQueryItem = nil
    activeQueuedIds = {}

    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local candidateCount = settings.verifyCandidateCount or 10
    local topCount = settings.topCount or 5

    local initialTop, initialAllEval = LL.LevelingEngine.FindTopPlays(professionOrLine, nil, nil, { limit = math.max(candidateCount, topCount) })
    local topN = {}
    for i = 1, math.min(topCount, #initialTop) do
        topN[i] = initialTop[i]
    end
    lastEvaluatedPool = initialAllEval
    lastPoolSignature = BuildPoolSignature(professionOrLine)
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.lastTopPlays = topN

    for _, play in ipairs(initialTop) do
        for _, shop in ipairs(play.shoppingList or {}) do
            if shop.source == "AH" and shop.itemId and not activeQueuedIds[shop.itemId] and #verifyQueue < MAX_VERIFY_QUEUE then
                if not LL.VendorDatabase.IsVendorReagent(shop.itemId) then
                    activeQueuedIds[shop.itemId] = true
                    table.insert(verifyQueue, {
                        itemId = shop.itemId,
                        name = shop.name,
                    })
                end
            end
        end
    end

    if #verifyQueue == 0 or not LL.AHVerifier.IsAuctionHouseOpen() or settings.orderBookVerify == false then
        FinalizeRun("COMPLETE", professionOrLine)
        return LevelingLad_DB.lastTopPlays
    end

    ScheduleNextVerification(0.05)
    return LevelingLad_DB.lastTopPlays
end

-- ============================================================================
-- 1-Click Auction House Navigation & "Buy Next" Purchasing
-- ============================================================================

local function SetDefaultCommoditiesUIQuantity(desiredQuantity, triggerChangeHandler)
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    local ahFrame = _G.AuctionHouseFrame
    local commFrame = ahFrame and ahFrame.CommoditiesBuyFrame
    if not commFrame or not commFrame.BuyDisplay then return end

    local qInput = commFrame.BuyDisplay.QuantityInput
    if qInput then
        if qInput.SetQuantity and triggerChangeHandler then
            pcall(qInput.SetQuantity, qInput, desiredQuantity)
        elseif qInput.InputBox then
            if qInput.InputBox.SetNumber then
                pcall(qInput.InputBox.SetNumber, qInput.InputBox, desiredQuantity)
            elseif qInput.InputBox.SetText then
                pcall(qInput.InputBox.SetText, qInput.InputBox, tostring(desiredQuantity))
            end
        elseif qInput.SetQuantity then
            pcall(qInput.SetQuantity, qInput, desiredQuantity)
        end
    end
    if triggerChangeHandler then
        if commFrame.OnQuantityChanged then
            pcall(commFrame.OnQuantityChanged, commFrame)
        elseif commFrame.BuyDisplay.OnQuantityChanged then
            pcall(commFrame.BuyDisplay.OnQuantityChanged, commFrame.BuyDisplay)
        end
    end
end

local OpenItemKeyInDefaultAH
local ScheduleSearchStallWatchdog

local function FlushPendingOpenItemKey()
    if not pendingOpenItemKey then return end
    if isRunning or not LL.AHVerifier.IsAuctionHouseOpen() then return end
    if _G.C_AuctionHouse and _G.C_AuctionHouse.IsThrottledMessageSystemReady and not _G.C_AuctionHouse.IsThrottledMessageSystemReady() then
        return
    end
    local req = pendingOpenItemKey
    pendingOpenItemKey = nil
    if req.token ~= openSearchToken then return end
    OpenItemKeyInDefaultAH(req.itemId, req.itemKey, req.desiredQuantity, req.token)
end

ScheduleSearchStallWatchdog = function(checkRef, delaySeconds)
    if not checkRef or not _G.C_Timer or not _G.C_Timer.After then return end
    _G.C_Timer.After(delaySeconds or 1.0, function()
        if isRunning or not pendingSearchCheck or pendingSearchCheck ~= checkRef or checkRef.token ~= openSearchToken then
            return
        end
        if not LL.AHVerifier.IsAuctionHouseOpen() or not _G.C_AuctionHouse or not _G.C_AuctionHouse.SendSearchQuery then
            pendingSearchCheck = nil
            return
        end
        if _G.C_AuctionHouse.IsThrottledMessageSystemReady and not _G.C_AuctionHouse.IsThrottledMessageSystemReady() then
            if checkRef.retries < 3 then
                checkRef.retries = checkRef.retries + 1
                ScheduleSearchStallWatchdog(checkRef, 0.35)
            else
                pendingSearchCheck = nil
            end
            return
        end

        pcall(_G.C_AuctionHouse.SendSearchQuery, checkRef.itemKey, { { sortOrder = 0, reverseSort = false } }, false)
        checkRef.retries = (checkRef.retries or 0) + 1
        if checkRef.retries < 2 then
            ScheduleSearchStallWatchdog(checkRef, 1.5)
        else
            pendingSearchCheck = nil
        end
    end)
end

OpenItemKeyInDefaultAH = function(itemId, itemKey, desiredQuantity, existingToken)
    if not _G.AuctionHouseFrame then return end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end

    local myToken = existingToken
    if not myToken then
        openSearchToken = openSearchToken + 1
        myToken = openSearchToken
    end

    activeSearchItemId = itemId
    activeSearchItemKey = itemKey
    activeSearchDesiredQty = desiredQuantity or 1
    knownItemKeys[itemId] = itemKey

    if _G.C_AuctionHouse and _G.C_AuctionHouse.IsThrottledMessageSystemReady and not _G.C_AuctionHouse.IsThrottledMessageSystemReady() then
        pendingOpenItemKey = {
            itemId = itemId,
            itemKey = itemKey,
            desiredQuantity = desiredQuantity,
            token = myToken,
        }
        SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.25, function()
                if pendingOpenItemKey and pendingOpenItemKey.token == myToken then
                    FlushPendingOpenItemKey()
                end
            end)
        end
        return
    end

    pendingOpenItemKey = nil
    local minPrice = LL.LevelingEngine.ResolveAHUnitPrice(itemId) or 0
    local checkRef = {
        itemId = itemId,
        itemKey = itemKey,
        desiredQuantity = desiredQuantity,
        token = myToken,
        retries = 0,
    }
    pendingSearchCheck = checkRef

    local ahFrame = _G.AuctionHouseFrame
    local alreadyShowingSameCommodity = ahFrame.CommoditiesBuyFrame
        and ahFrame.CommoditiesBuyFrame.IsShown and ahFrame.CommoditiesBuyFrame:IsShown()
        and ahFrame.CommoditiesBuyFrame.BuyList
        and ahFrame.CommoditiesBuyFrame.BuyList.itemID == itemId

    if alreadyShowingSameCommodity and _G.C_AuctionHouse and _G.C_AuctionHouse.SendSearchQuery then
        pcall(_G.C_AuctionHouse.SendSearchQuery, itemKey, { { sortOrder = 0, reverseSort = false } }, false)
        SetDefaultCommoditiesUIQuantity(desiredQuantity, false)
    elseif ahFrame.SelectBrowseResult then
        pcall(ahFrame.SelectBrowseResult, ahFrame, {
            itemKey = itemKey,
            minPrice = minPrice,
            totalQuantity = desiredQuantity,
        })
        SetDefaultCommoditiesUIQuantity(desiredQuantity, false)
    elseif _G.C_AuctionHouse and _G.C_AuctionHouse.SendSearchQuery then
        pcall(_G.C_AuctionHouse.SendSearchQuery, itemKey, { { sortOrder = 0, reverseSort = false } }, false)
    end

    ScheduleSearchStallWatchdog(checkRef, 0.8)
end

function LL.AHVerifier.SearchItemOnAH(itemId, itemName, itemLink, desiredQuantity)
    local meta = LL.VendorDatabase.GetItemMetadata(itemId, itemLink, true)
    local searchName = itemName or (meta and meta.name)
    if not searchName and type(itemLink) == "string" then
        searchName = itemLink:match("%[(.-)%]")
    end
    if (not searchName or searchName == "") and not itemId then
        print("|cffff5555[Leveling Lad]|r Could not determine reagent to search.")
        return false
    end

    desiredQuantity = math.max(1, math.floor(tonumber(desiredQuantity) or 1))
    activeSearchItemId = itemId
    purchasedAuctionIds = {}

    -- 1. Legacy AuctionFrame path
    if _G.AuctionFrame and (not _G.AuctionHouseFrame or not _G.AuctionHouseFrame:IsShown()) then
        if _G.AuctionFrameTab1 and _G.AuctionFrameTab1.Click and (not _G.AuctionFrameBrowse or not _G.AuctionFrameBrowse:IsShown()) then
            pcall(_G.AuctionFrameTab1.Click, _G.AuctionFrameTab1)
        end
        if _G.BrowseName and _G.BrowseName.SetText and searchName then
            pcall(_G.BrowseName.SetText, _G.BrowseName, searchName)
        end
        if _G.QueryAuctionItems and (not _G.CanSendAuctionQuery or _G.CanSendAuctionQuery()) then
            pcall(_G.QueryAuctionItems, searchName or "", nil, nil, 0, 0, 0, 0, false, -1, false)
            return true
        elseif _G.BrowseSearchButton and _G.BrowseSearchButton.Click then
            pcall(_G.BrowseSearchButton.Click, _G.BrowseSearchButton)
            return true
        end
        return true
    end

    -- 2. Modern WoW: Forever AuctionHouseFrame path
    if _G.AuctionHouseFrame then
        HarvestBrowseResultItemKeys()

        local searchBar = _G.AuctionHouseFrame.SearchBar
        if searchBar and searchBar.SearchBox and searchBar.SearchBox.SetText and searchName then
            pcall(searchBar.SearchBox.SetText, searchBar.SearchBox, searchName)
        end

        if itemId and itemId > 0 and _G.C_AuctionHouse then
            SafeRegisterEvent(verifierFrame, "COMMODITY_SEARCH_RESULTS_UPDATED")
            SafeRegisterEvent(verifierFrame, "ITEM_SEARCH_RESULTS_UPDATED")
            SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
            SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
            local itemKey = LL.AHVerifier.MakeItemKey(itemId)
            OpenItemKeyInDefaultAH(itemId, itemKey, desiredQuantity)
            return true
        end

        if _G.C_AuctionHouse and _G.C_AuctionHouse.SendBrowseQuery and searchName then
            pcall(_G.C_AuctionHouse.SendBrowseQuery, { searchString = searchName, sorts = {}, filters = {} })
            return true
        end
    end

    print(string.format("|cffff9900[Leveling Lad]|r Open the Auction House to search for [%s].", searchName or "Item"))
    return false
end

local function GetLoadedQualifyingCommodityQty(itemId, maxUnitPrice, neededQty, playerGold)
    if not _G.C_AuctionHouse or not _G.C_AuctionHouse.GetNumCommoditySearchResults or not _G.C_AuctionHouse.GetCommoditySearchResultInfo then
        return 0, 0, 0
    end
    local okNum, num = pcall(_G.C_AuctionHouse.GetNumCommoditySearchResults, itemId)
    if not okNum or not num or num <= 0 then
        return 0, 0, 0
    end

    local buyQty = 0
    local totalCost = 0

    for i = 1, num do
        local okRow, row = pcall(_G.C_AuctionHouse.GetCommoditySearchResultInfo, itemId, i)
        if okRow and type(row) == "table" and row.unitPrice and row.unitPrice > 0 and row.quantity and row.quantity > 0 then
            local availQty = math.floor(row.quantity) - math.floor(tonumber(row.numOwnerItems) or 0)
            if availQty > 0 and (not maxUnitPrice or maxUnitPrice <= 0 or row.unitPrice <= maxUnitPrice) then
                local remNeeded = neededQty - buyQty
                if remNeeded > 0 then
                    local maxAffordable = (playerGold and playerGold > totalCost)
                        and math.floor((playerGold - totalCost) / row.unitPrice)
                        or 0
                    local take = math.min(remNeeded, availQty, maxAffordable)
                    if take > 0 then
                        buyQty = buyQty + take
                        totalCost = totalCost + (take * row.unitPrice)
                    end
                end
            end
        end
    end

    return num, buyQty, totalCost
end

local function GetLoadedQualifyingItemAuction(itemId, maxUnitPrice, playerGold)
    if not _G.C_AuctionHouse or not _G.C_AuctionHouse.GetNumItemSearchResults or not _G.C_AuctionHouse.GetItemSearchResultInfo then
        return 0, nil, nil
    end

    local candidateKeys = {}
    if _G.AuctionHouseFrame and _G.AuctionHouseFrame.ItemBuyFrame and _G.AuctionHouseFrame.ItemBuyFrame.itemKey then
        local uiKey = _G.AuctionHouseFrame.ItemBuyFrame.itemKey
        if uiKey.itemID == itemId then
            table.insert(candidateKeys, uiKey)
        end
    end
    if activeSearchItemKey and activeSearchItemKey.itemID == itemId then
        table.insert(candidateKeys, activeSearchItemKey)
    end
    if knownItemKeys[itemId] then
        table.insert(candidateKeys, knownItemKeys[itemId])
    end
    table.insert(candidateKeys, { itemID = itemId, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 })

    local matchedKey = nil
    local num = 0
    for _, key in ipairs(candidateKeys) do
        local okNum, n = pcall(_G.C_AuctionHouse.GetNumItemSearchResults, key)
        if okNum and n and n > 0 then
            matchedKey = key
            num = n
            break
        end
    end

    if not matchedKey or num <= 0 then
        return 0, nil, nil
    end

    local bestResult = nil
    local bestUnitPrice = nil

    for i = 1, num do
        local okRow, row = pcall(_G.C_AuctionHouse.GetItemSearchResultInfo, matchedKey, i)
        if okRow and type(row) == "table" and not row.containsOwnerItem and not row.containsAccountItem then
            if not row.auctionID or not purchasedAuctionIds[row.auctionID] then
                local buyout = row.buyoutAmount
                if buyout and buyout > 0 and (not playerGold or buyout <= playerGold) then
                    local unitPrice = math.floor(buyout)
                    if not maxUnitPrice or maxUnitPrice <= 0 or unitPrice <= maxUnitPrice then
                        if not bestUnitPrice or unitPrice < bestUnitPrice then
                            bestUnitPrice = unitPrice
                            bestResult = row
                        end
                    end
                end
            end
        end
    end

    return num, bestResult, matchedKey
end

function LL.AHVerifier.GetBuyButtonLabel(item)
    if not item then return "Buy Next" end
    if item.source == "Vendor" then
        if (item.remainingToBuy or 0) <= 0 then
            return "Ready"
        end
        return "Buy Vendor"
    end
    if (item.remainingToBuy or 0) <= 0 then
        if (item.inMail or 0) > 0 and (item.haveInBags or 0) < (item.totalQuantity or 1) then
            return "Bought"
        end
        return "Ready"
    end
    if pendingCommodityConfirm and pendingCommodityConfirm.itemId == item.itemId then
        return string.format("Confirm (%d)", pendingCommodityConfirm.quantity)
    end
    if inFlightCommodityPurchase and inFlightCommodityPurchase.itemId == item.itemId then
        local now = (_G.GetTime and _G.GetTime()) or 0
        if (now - (inFlightCommodityPurchase.sentAt or 0)) <= 6.0 then
            return "Buying..."
        else
            inFlightCommodityPurchase = nil
        end
    end
    if _G.C_AuctionHouse then
        local maxAllowed = item.verified and item.maxUnitPrice or nil
        local needed = math.max(1, item.remainingToBuy or item.totalQuantity or 1)
        local gold = LL.Formatter.GetPlayerGold()
        local numComm, buyQty = GetLoadedQualifyingCommodityQty(item.itemId, maxAllowed, needed, gold)
        if numComm > 0 and buyQty > 0 then
            return string.format("Buy %dx", buyQty)
        end
        local numItem, bestAuction = GetLoadedQualifyingItemAuction(item.itemId, maxAllowed, gold)
        if numItem > 0 and bestAuction then
            return "Buy 1x"
        end
    end
    return "Buy Next"
end

-- Executes 1-click purchasing through NPC Merchant, Legacy AuctionFrame, or Modern C_AuctionHouse
function LL.AHVerifier.BuyNextCheapListing(itemId, itemName, maxUnitPrice, neededQty)
    if not itemId or itemId <= 0 then return false end
    neededQty = math.max(1, math.floor(tonumber(neededQty) or 1))
    local playerGold = LL.Formatter.GetPlayerGold()

    pendingOpenItemKey = nil
    pendingSearchCheck = nil

    -- 1. Open Merchant window path (works for NPC vendor reagents!)
    if _G.GetMerchantNumItems and _G.GetMerchantItemInfo and _G.BuyMerchantItem then
        local okNum, numMerchant = pcall(_G.GetMerchantNumItems)
        if okNum and type(numMerchant) == "number" and numMerchant > 0 then
            for i = 1, numMerchant do
                local link = _G.GetMerchantItemLink and _G.GetMerchantItemLink(i)
                local mId = link and tonumber(link:match("item:(%d+)"))
                local okM, mName, _, price, batchQty, numAvailable = pcall(_G.GetMerchantItemInfo, i)
                if okM and (mId == itemId or (not mId and mName and itemName and mName:lower() == itemName:lower())) then
                    batchQty = (batchQty and batchQty > 0) and batchQty or 1
                    local batches = math.max(1, math.ceil(neededQty / batchQty))
                    if numAvailable and numAvailable > 0 then
                        batches = math.min(batches, numAvailable)
                    end
                    pcall(_G.BuyMerchantItem, i, batches)
                    print(string.format("|cff00ccff[Leveling Lad]|r Purchased %dx [%s] from Merchant.", batches * batchQty, itemName or mName or ("Item #" .. itemId)))
                    return true, batches * batchQty, (price or 0) * batches, "BOUGHT"
                end
            end
        end
    end

    if LL.VendorDatabase and LL.VendorDatabase.IsVendorReagent(itemId) and not LL.AHVerifier.IsAuctionHouseOpen() then
        local info = LL.VendorDatabase.GetVendorInfo(itemId)
        print(string.format("|cffffcc00[Leveling Lad]|r Visit %s to buy %dx [%s] at vendor price (%s ea).",
            (info and info.vendor) or "an NPC Trade Vendor",
            neededQty,
            itemName or (info and info.name) or ("Item #" .. itemId),
            LL.Formatter.FormatMoney((info and info.price) or 0, true)
        ))
        return false, 0, 0, "VENDOR_CLOSED"
    end

    if not LL.AHVerifier.IsAuctionHouseOpen() then
        print("|cffff5555[Leveling Lad]|r Open the Auction House first to buy listings.")
        return false, 0, 0, "AH_CLOSED"
    end

    -- 2. Legacy AuctionFrame Buyout Path
    if _G.GetNumAuctionItems and _G.GetAuctionItemInfo and _G.PlaceAuctionBid and (not _G.AuctionHouseFrame or not _G.AuctionHouseFrame:IsShown()) then
        local numBatch = _G.GetNumAuctionItems("list") or 0
        local bestIdx = nil
        local bestUnitPrice = nil
        local bestBuyout = nil
        local bestCount = nil
        local anyMatchOnPage = false

        for i = 1, numBatch do
            local name, _, count, _, _, _, _, _, _, buyoutPrice, _, _, _, _, _, _, rowItemId = _G.GetAuctionItemInfo("list", i)
            if (not rowItemId or rowItemId <= 0) and _G.GetAuctionItemLink then
                local link = _G.GetAuctionItemLink("list", i)
                if type(link) == "string" then
                    rowItemId = tonumber(link:match("item:(%d+)"))
                end
            end
            local matches = (rowItemId and rowItemId == itemId)
                or (not rowItemId and name and itemName and name:lower() == itemName:lower())

            if matches then
                anyMatchOnPage = true
                if buyoutPrice and buyoutPrice > 0 and count and count > 0 and buyoutPrice <= playerGold then
                    local unitPrice = math.floor(buyoutPrice / count)
                    if not maxUnitPrice or maxUnitPrice <= 0 or unitPrice <= maxUnitPrice then
                        if not bestUnitPrice or unitPrice < bestUnitPrice or (unitPrice == bestUnitPrice and count <= neededQty) then
                            bestIdx = i
                            bestUnitPrice = unitPrice
                            bestBuyout = buyoutPrice
                            bestCount = count
                        end
                    end
                end
            end
        end

        if not anyMatchOnPage then
            LL.AHVerifier.SearchItemOnAH(itemId, itemName, nil, neededQty)
            print(string.format("|cff00ccff[Leveling Lad]|r Searching AH for [%s]... Click 'Buy Next' again once results load.", itemName or ("Item #" .. itemId)))
            return false, 0, 0, "SEARCH_STARTED"
        end

        if bestIdx and bestBuyout then
            if _G.SetSelectedAuctionItem then
                pcall(_G.SetSelectedAuctionItem, "list", bestIdx)
            end
            pcall(_G.PlaceAuctionBid, "list", bestIdx, bestBuyout)
            print(string.format(
                "|cff00ccff[Leveling Lad]|r Buying %dx [%s] for %s (%s ea).",
                bestCount,
                itemName or ("Item #" .. itemId),
                LL.Formatter.FormatMoney(bestBuyout),
                LL.Formatter.FormatMoney(bestUnitPrice)
            ))
            return true, bestCount, bestBuyout, "BOUGHT"
        else
            print(string.format(
                "|cffff5555[Leveling Lad]|r No listings on current page for [%s] within max price / wallet.",
                itemName or ("Item #" .. itemId)
            ))
            return false, 0, 0, "NO_CHEAP_LISTING"
        end
    end

    -- 3. Modern C_AuctionHouse + AuctionHouseFrame Path
    if _G.C_AuctionHouse then
        if pendingCommodityConfirm and pendingCommodityConfirm.itemId == itemId then
            if _G.C_AuctionHouse.IsThrottledMessageSystemReady and not _G.C_AuctionHouse.IsThrottledMessageSystemReady() then
                print("|cffff9900[Leveling Lad]|r Auction House is busy — click 'Confirm' again in a moment.")
                return false, 0, 0, "THROTTLED"
            end

            local conf = pendingCommodityConfirm
            pendingCommodityConfirm = nil
            inFlightCommodityPurchase = {
                itemId = conf.itemId,
                itemName = conf.itemName or itemName,
                quantity = conf.quantity,
                unitPrice = conf.unitPrice,
                totalPrice = conf.totalPrice,
                sentAt = (_G.GetTime and _G.GetTime()) or 0,
            }

            if _G.C_AuctionHouse.ConfirmCommoditiesPurchase then
                pcall(_G.C_AuctionHouse.ConfirmCommoditiesPurchase, conf.itemId, conf.quantity)
            end

            print(string.format(
                "|cff00ccff[Leveling Lad]|r Confirming purchase of %dx [%s] for %s (%s ea)...",
                conf.quantity,
                conf.itemName or itemName or ("Item #" .. itemId),
                LL.Formatter.FormatMoney(conf.totalPrice or (conf.unitPrice * conf.quantity)),
                LL.Formatter.FormatMoney(conf.unitPrice or 0)
            ))
            if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                LL.DetailWindow.RefreshIfShown()
            end
            return true, conf.quantity, conf.totalPrice or 0, "BOUGHT"
        end

        local numComm, buyQty, estTotalCost = GetLoadedQualifyingCommodityQty(itemId, maxUnitPrice, neededQty, playerGold)
        if numComm > 0 then
            if buyQty <= 0 then
                print(string.format(
                    "|cffff5555[Leveling Lad]|r No [%s] listings available within max price / wallet.",
                    itemName or ("Item #" .. itemId)
                ))
                return false, 0, 0, "NO_CHEAP_LISTING"
            end

            if _G.C_AuctionHouse.IsThrottledMessageSystemReady and not _G.C_AuctionHouse.IsThrottledMessageSystemReady() then
                print("|cffff9900[Leveling Lad]|r Auction House is busy — click again in a moment.")
                return false, 0, 0, "THROTTLED"
            end

            inFlightCommodityPurchase = nil
            SetDefaultCommoditiesUIQuantity(buyQty, true)

            SafeRegisterEvent(verifierFrame, "COMMODITY_PRICE_UPDATED")
            SafeRegisterEvent(verifierFrame, "COMMODITY_PRICE_UNAVAILABLE")
            SafeRegisterEvent(verifierFrame, "COMMODITY_PURCHASE_SUCCEEDED")
            SafeRegisterEvent(verifierFrame, "COMMODITY_PURCHASE_FAILED")

            local avgEstUnit = math.floor((estTotalCost / buyQty) + 0.5)
            pendingCommodityConfirm = {
                itemId = itemId,
                itemName = itemName,
                quantity = buyQty,
                unitPrice = avgEstUnit,
                totalPrice = estTotalCost,
                maxUnitPrice = maxUnitPrice,
            }

            if _G.C_AuctionHouse.StartCommoditiesPurchase then
                pcall(_G.C_AuctionHouse.StartCommoditiesPurchase, itemId, buyQty)
            end

            print(string.format(
                "|cff00ccff[Leveling Lad]|r Reserved %dx [%s] (~%s total, %s ea). Click 'Confirm (%d)' to complete buyout!",
                buyQty,
                itemName or ("Item #" .. itemId),
                LL.Formatter.FormatMoney(estTotalCost),
                LL.Formatter.FormatMoney(avgEstUnit),
                buyQty
            ))
            if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                LL.DetailWindow.RefreshIfShown()
            end
            return true, buyQty, estTotalCost, "QUOTE_STARTED"
        end

        local numItem, bestAuction = GetLoadedQualifyingItemAuction(itemId, maxUnitPrice, playerGold)
        if numItem > 0 then
            if not bestAuction or not bestAuction.auctionID or not bestAuction.buyoutAmount then
                print(string.format(
                    "|cffff5555[Leveling Lad]|r No remaining [%s] listings available within max price / wallet.",
                    itemName or ("Item #" .. itemId)
                ))
                return false, 0, 0, "NO_CHEAP_LISTING"
            end

            if _G.C_AuctionHouse.IsThrottledMessageSystemReady and not _G.C_AuctionHouse.IsThrottledMessageSystemReady() then
                print("|cffff9900[Leveling Lad]|r Auction House is busy — click again in a moment.")
                return false, 0, 0, "THROTTLED"
            end

            if _G.C_AuctionHouse.PlaceBid then
                purchasedAuctionIds[bestAuction.auctionID] = true
                inFlightItemPurchases[bestAuction.auctionID] = {
                    itemId = itemId,
                    itemName = itemName,
                    quantity = 1,
                    buyout = bestAuction.buyoutAmount,
                    sentAt = (_G.GetTime and _G.GetTime()) or 0,
                }
                pcall(_G.C_AuctionHouse.PlaceBid, bestAuction.auctionID, bestAuction.buyoutAmount)
                print(string.format(
                    "|cff00ccff[Leveling Lad]|r Buying 1x [%s] (auction #%s) for %s!",
                    itemName or ("Item #" .. itemId),
                    tostring(bestAuction.auctionID),
                    LL.Formatter.FormatMoney(bestAuction.buyoutAmount)
                ))
                if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                    LL.DetailWindow.RefreshIfShown()
                end
                return true, 1, bestAuction.buyoutAmount, "BOUGHT"
            end
        end

        LL.AHVerifier.SearchItemOnAH(itemId, itemName, nil, neededQty)
        print(string.format(
            "|cff00ccff[Leveling Lad]|r Opening [%s] (x%d) in the Auction House... Wait 1s for listings to appear, then click Buy!",
            itemName or ("Item #" .. itemId),
            neededQty
        ))
        return false, 0, 0, "OPENING_ITEM"
    end

    return false, 0, 0, "UNSUPPORTED"
end

-- ============================================================================
-- Purchased-In-Mailbox Tracking & Combat-Safe System Chat Parser
-- ============================================================================

local function GetCharMailTable(createIfMissing)
    if type(LevelingLad_DB) ~= "table" then return nil end
    if type(LevelingLad_DB.purchasedInMail) ~= "table" then
        if not createIfMissing then return nil end
        LevelingLad_DB.purchasedInMail = {}
    end
    local charKey = LL.GetCharacterKey()
    if type(LevelingLad_DB.purchasedInMail[charKey]) ~= "table" then
        if not createIfMissing then return nil end
        LevelingLad_DB.purchasedInMail[charKey] = {}
    end
    return LevelingLad_DB.purchasedInMail[charKey]
end

function LL.AHVerifier.ClearPurchasedTracker(itemId)
    local tbl = GetCharMailTable(false)
    if tbl then
        if itemId then
            tbl[itemId] = nil
        else
            local charKey = LL.GetCharacterKey()
            LevelingLad_DB.purchasedInMail[charKey] = {}
        end
    end
    if not itemId then
        purchaseDedupQueue = {}
        pendingCommodityConfirm = nil
        inFlightCommodityPurchase = nil
        inFlightItemPurchases = {}
    end
end

function LL.AHVerifier.GetPurchasedInMailInfo(itemId)
    if not itemId or itemId <= 0 then return 0, 0 end
    local tbl = GetCharMailTable(false)
    if not tbl then return 0, 0 end
    local entry = tbl[itemId]
    if type(entry) ~= "table" or (entry.count or 0) <= 0 then
        tbl[itemId] = nil
        return 0, 0
    end
    local now = (_G.time and _G.time()) or 0
    if (now - (entry.updatedAt or 0)) > PURCHASED_MAIL_TTL_SECONDS then
        tbl[itemId] = nil
        return 0, 0
    end

    local currentBags = LL.Formatter.GetInventoryCount(itemId, false)
    if type(entry.lastBagCount) == "number" and currentBags > entry.lastBagCount then
        local oldCount = entry.count or 0
        local gained = currentBags - entry.lastBagCount
        local newCount = math.max(0, oldCount - gained)
        if type(entry.spentCopper) == "number" and entry.spentCopper > 0 and oldCount > 0 then
            entry.spentCopper = math.floor((entry.spentCopper * (newCount / oldCount)) + 0.5)
        end
        entry.count = newCount
    end
    entry.lastBagCount = currentBags
    if entry.count <= 0 then
        tbl[itemId] = nil
        return 0, 0
    end
    return entry.count, tonumber(entry.spentCopper) or 0
end

function LL.AHVerifier.GetPurchasedInMailCount(itemId)
    local count = LL.AHVerifier.GetPurchasedInMailInfo(itemId)
    return count
end

function LL.AHVerifier.RecordConfirmedPurchase(itemId, itemName, qty, source, spentCopper)
    qty = math.floor(tonumber(qty) or 0)
    if not itemId or itemId <= 0 or qty <= 0 then return false end

    local now = (_G.GetTime and _G.GetTime()) or (_G.time and _G.time()) or 0
    local kept = {}
    for _, tok in ipairs(purchaseDedupQueue) do
        if tok.expiresAt and tok.expiresAt > now then
            table.insert(kept, tok)
        end
    end
    purchaseDedupQueue = kept

    if source == "EVENT" or source == "CHAT" then
        local opposite = (source == "EVENT") and "CHAT" or "EVENT"
        for idx, tok in ipairs(purchaseDedupQueue) do
            if tok.source == opposite and tok.itemId == itemId and tok.qty == qty then
                table.remove(purchaseDedupQueue, idx)
                return false
            end
        end
        table.insert(purchaseDedupQueue, { source = source, itemId = itemId, qty = qty, expiresAt = now + 6.0 })
    end

    local tbl = GetCharMailTable(true)
    if not tbl then return false end
    local existing, existingSpent = LL.AHVerifier.GetPurchasedInMailInfo(itemId)
    local currentBags = LL.Formatter.GetInventoryCount(itemId, false)
    local addedSpent = (type(spentCopper) == "number" and spentCopper > 0) and math.floor(spentCopper) or 0
    tbl[itemId] = {
        count = existing + qty,
        spentCopper = existingSpent + addedSpent,
        itemName = itemName,
        updatedAt = (_G.time and _G.time()) or 0,
        lastBagCount = currentBags,
    }

    if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
        LL.DetailWindow.RefreshIfShown()
    end
    return true
end

local function BuildAuctionWonPattern()
    local fmt = (type(_G.ERR_AUCTION_WON_S) == "string" and _G.ERR_AUCTION_WON_S ~= "")
        and _G.ERR_AUCTION_WON_S
        or "You won an auction for %s"
    local escaped = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    local pattern = escaped:gsub("%%%%s", "(.+)", 1)
    return "^" .. pattern .. "%.?$"
end

-- Combat-safe parser for WoW system chat messages such as:
--   "You won an auction for Mithril Ore (x29)" -> "Mithril Ore", 29, nil
--   "You won an auction for [Rough Stone] (x5)" -> "Rough Stone", 5, 2835
function LL.AHVerifier.ParseAuctionWonMessage(msg)
    if msg == nil or (LL.IsSecret and LL.IsSecret(msg)) then
        return nil, nil, nil
    end
    if type(msg) ~= "string" or msg == "" then
        return nil, nil, nil
    end
    local wonText = msg:match(BuildAuctionWonPattern())
    if not wonText or wonText == "" then
        wonText = msg:match("^You won an auction for (.+)%.?$")
    end
    if not wonText or wonText == "" then
        return nil, nil, nil
    end
    wonText = wonText:gsub("%.$", "")

    local qty = 1
    local stripped, countStr = wonText:match("^(.-)%s*%(x(%d+)%)%s*$")
    if not stripped then
        stripped, countStr = wonText:match("^(.-)%s*%((%d+)%)%s*$")
    end
    if stripped and countStr then
        wonText = stripped
        qty = math.max(1, tonumber(countStr) or 1)
    end

    local linkedItemId = tonumber(wonText:match("item:(%d+)"))
    local linkBracketName = wonText:match("%[(.-)%]")
    local cleanName = linkBracketName or wonText:gsub("^%s+", ""):gsub("%s+$", "")
    if cleanName == "" then
        return nil, nil, nil
    end
    return cleanName, qty, linkedItemId
end

local function ResolvePurchasedItemIdByName(itemName, linkedItemId)
    if linkedItemId and linkedItemId > 0 then
        return linkedItemId
    end
    if type(itemName) ~= "string" or itemName == "" then
        return nil
    end
    local lowerTarget = itemName:lower()

    if inFlightCommodityPurchase and inFlightCommodityPurchase.itemName
        and inFlightCommodityPurchase.itemName:lower() == lowerTarget then
        return inFlightCommodityPurchase.itemId
    end

    for _, entry in pairs(inFlightItemPurchases) do
        if entry and entry.itemName and entry.itemName:lower() == lowerTarget then
            return entry.itemId
        end
    end

    local function MatchInShoppingList(play)
        if type(play) ~= "table" or type(play.shoppingList) ~= "table" then return nil end
        for _, shop in ipairs(play.shoppingList) do
            if shop and shop.itemId and type(shop.name) == "string" and shop.name:lower() == lowerTarget then
                return shop.itemId
            end
        end
        return nil
    end

    if type(LevelingLad_DB) == "table" then
        local fromActive = MatchInShoppingList(LevelingLad_DB.activePlay)
        if fromActive then return fromActive end

        if type(LevelingLad_DB.lastTopPlays) == "table" then
            for _, p in ipairs(LevelingLad_DB.lastTopPlays) do
                local found = MatchInShoppingList(p)
                if found then return found end
            end
        end
        local fromRoadmap = MatchInShoppingList(LevelingLad_DB.lastRoadmap)
        if fromRoadmap then return fromRoadmap end

        if type(LevelingLad_DB.itemCache) == "table" then
            for cachedId, meta in pairs(LevelingLad_DB.itemCache) do
                if type(meta) == "table" and type(meta.name) == "string" and meta.name:lower() == lowerTarget then
                    return cachedId
                end
            end
        end
    end

    return nil
end

function LL.AHVerifier.Init()
    if LL.AHVerifier._initialized then return end
    LL.AHVerifier._initialized = true

    SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_CLOSED")
    SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
    SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_PURCHASE_COMPLETED")
    SafeRegisterEvent(verifierFrame, "COMMODITY_SEARCH_RESULTS_UPDATED")
    SafeRegisterEvent(verifierFrame, "ITEM_SEARCH_RESULTS_UPDATED")
    SafeRegisterEvent(verifierFrame, "COMMODITY_PURCHASE_SUCCEEDED")
    SafeRegisterEvent(verifierFrame, "COMMODITY_PURCHASE_FAILED")
    SafeRegisterEvent(verifierFrame, "COMMODITY_PRICE_UNAVAILABLE")
    SafeRegisterEvent(verifierFrame, "CHAT_MSG_SYSTEM")
    SafeRegisterEvent(verifierFrame, "MAIL_INBOX_UPDATE")

    verifierFrame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "AUCTION_HOUSE_CLOSED" then
            knownItemKeys = {}
            purchasedAuctionIds = {}
            pendingOpenItemKey = nil
            pendingSearchCheck = nil
            pendingCommodityConfirm = nil
            inFlightCommodityPurchase = nil
            inFlightItemPurchases = {}
            if isRunning then
                LL.AHVerifier.Stop("AH_CLOSED")
            end
            return
        end

        if event == "CHAT_MSG_SYSTEM" then
            if LL.IsSecret and LL.IsSecret(arg1) then
                return
            end
            local wonName, wonQty, linkedId = LL.AHVerifier.ParseAuctionWonMessage(arg1)
            if wonName and wonQty and wonQty > 0 then
                local resolvedId = ResolvePurchasedItemIdByName(wonName, linkedId)
                if resolvedId then
                    local matchedSpent = nil
                    if inFlightCommodityPurchase and inFlightCommodityPurchase.itemId == resolvedId
                        and inFlightCommodityPurchase.quantity == wonQty then
                        matchedSpent = inFlightCommodityPurchase.totalPrice
                        inFlightCommodityPurchase = nil
                    else
                        for aId, entry in pairs(inFlightItemPurchases) do
                            if entry and entry.itemId == resolvedId then
                                matchedSpent = entry.buyout
                                inFlightItemPurchases[aId] = nil
                                break
                            end
                        end
                    end
                    LL.AHVerifier.RecordConfirmedPurchase(resolvedId, wonName, wonQty, "CHAT", matchedSpent)
                end
            end
            return
        end

        if event == "MAIL_INBOX_UPDATE" then
            if _G.GetInboxNumItems then
                local okInbox, numItems, totalItems = pcall(_G.GetInboxNumItems)
                if okInbox and numItems == 0 and (totalItems == nil or totalItems == 0) then
                    local tbl = GetCharMailTable(false)
                    if tbl then
                        local now = (_G.time and _G.time()) or 0
                        for mItemId, entry in pairs(tbl) do
                            if type(entry) ~= "table" or (now - (entry.updatedAt or 0)) >= 3 then
                                tbl[mItemId] = nil
                            end
                        end
                    end
                end
            end
            if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                LL.DetailWindow.RefreshIfShown()
            end
            return
        end

        if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
            local auctionId = tonumber(arg1) or arg1
            local entry = (auctionId ~= nil) and inFlightItemPurchases[auctionId] or nil
            if entry then
                inFlightItemPurchases[auctionId] = nil
            else
                local now = (_G.GetTime and _G.GetTime()) or 0
                local oldestKey, oldestTime = nil, nil
                for aId, e in pairs(inFlightItemPurchases) do
                    if e and (now - (e.sentAt or 0)) <= 10.0 then
                        if not oldestTime or (e.sentAt or 0) < oldestTime then
                            oldestKey = aId
                            oldestTime = e.sentAt or 0
                        end
                    end
                end
                if oldestKey then
                    entry = inFlightItemPurchases[oldestKey]
                    inFlightItemPurchases[oldestKey] = nil
                end
            end
            if entry and entry.itemId then
                LL.AHVerifier.RecordConfirmedPurchase(entry.itemId, entry.itemName, entry.quantity or 1, "EVENT", entry.buyout)
            end
            return
        end

        if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
            FlushPendingOpenItemKey()
            return
        end

        if event == "AUCTION_HOUSE_BROWSE_RESULTS_UPDATED" or event == "AUCTION_HOUSE_BROWSE_RESULTS_ADDED" then
            HarvestBrowseResultItemKeys(type(arg1) == "table" and arg1 or nil)
            return
        end

        if event == "COMMODITY_PRICE_UPDATED" then
            local updatedUnitPrice, updatedTotalPrice = tonumber(arg1), tonumber(arg2)
            if pendingCommodityConfirm and updatedUnitPrice and updatedTotalPrice then
                pendingCommodityConfirm.unitPrice = updatedUnitPrice
                pendingCommodityConfirm.totalPrice = updatedTotalPrice
                if pendingCommodityConfirm.maxUnitPrice and pendingCommodityConfirm.maxUnitPrice > 0 and updatedUnitPrice > pendingCommodityConfirm.maxUnitPrice then
                    if _G.C_AuctionHouse and _G.C_AuctionHouse.CancelCommoditiesPurchase then
                        pcall(_G.C_AuctionHouse.CancelCommoditiesPurchase)
                    end
                    print(string.format(
                        "|cffff5555[Leveling Lad]|r Cancelled purchase: unit price jumped to %s (max expected %s).",
                        LL.Formatter.FormatMoney(updatedUnitPrice),
                        LL.Formatter.FormatMoney(pendingCommodityConfirm.maxUnitPrice)
                    ))
                    pendingCommodityConfirm = nil
                end
                if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                    LL.DetailWindow.RefreshIfShown()
                end
            end
            return
        elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" then
            pendingCommodityConfirm = nil
            inFlightCommodityPurchase = nil
            if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                LL.DetailWindow.RefreshIfShown()
            end
            return
        elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
            local completed = inFlightCommodityPurchase or pendingCommodityConfirm
            inFlightCommodityPurchase = nil
            pendingCommodityConfirm = nil
            if completed and completed.itemId then
                local spent = completed.totalPrice or ((completed.unitPrice or 0) * (completed.quantity or 1))
                LL.AHVerifier.RecordConfirmedPurchase(completed.itemId, completed.itemName, completed.quantity or 1, "EVENT", spent)
                print(string.format(
                    "|cff00ccff[Leveling Lad]|r Purchase confirmed: %dx [%s] — check your mailbox!",
                    completed.quantity or 1,
                    completed.itemName or ("Item #" .. tostring(completed.itemId))
                ))
            end
            if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                LL.DetailWindow.RefreshIfShown()
            end
            return
        end

        if event == "AUCTION_ITEM_LIST_UPDATE" then
            if isRunning and currentQueryItem then
                CollectLegacyQueryResults(currentQueryItem)
                currentQueryItem = nil
                ScheduleNextVerification(0.10)
            elseif LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                LL.DetailWindow.RefreshIfShown()
            end
            return
        end

        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
            local itemId = tonumber(arg1) or (currentQueryItem and currentQueryItem.itemId) or activeSearchItemId
            if itemId then
                if pendingSearchCheck and pendingSearchCheck.itemId == itemId then
                    pendingSearchCheck = nil
                end
                CollectModernCommodityResults(itemId)
                if isRunning and currentQueryItem and currentQueryItem.itemId == itemId then
                    currentQueryItem = nil
                    ScheduleNextVerification(0.10)
                else
                    if itemId == activeSearchItemId and activeSearchDesiredQty and activeSearchDesiredQty > 0 then
                        SetDefaultCommoditiesUIQuantity(activeSearchDesiredQty, true)
                    end
                    if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                        LL.DetailWindow.RefreshIfShown()
                    end
                end
            end
            return
        end

        if event == "ITEM_SEARCH_RESULTS_UPDATED" then
            local itemId = (type(arg1) == "table" and arg1.itemID) or tonumber(arg1) or (currentQueryItem and currentQueryItem.itemId) or activeSearchItemId
            local itemKey = (type(arg1) == "table") and arg1 or nil
            if itemId then
                if pendingSearchCheck and pendingSearchCheck.itemId == itemId then
                    pendingSearchCheck = nil
                end
                CollectModernItemResults(itemId, itemKey)
                if isRunning and currentQueryItem and currentQueryItem.itemId == itemId then
                    currentQueryItem = nil
                    ScheduleNextVerification(0.10)
                elseif LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
                    LL.DetailWindow.RefreshIfShown()
                end
            end
            return
        end
    end)

    LL.AHVerifier.frame = verifierFrame
end
