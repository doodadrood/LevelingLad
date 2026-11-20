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
local pendingCommodityPurchase = nil
local purchaseDedupQueue = {}

local MAX_ORDERBOOK_ROWS = 60
local MAX_ORDERBOOK_QTY = 600
local MAX_VERIFY_QUEUE = 25
local PURCHASED_MAIL_TTL_SECONDS = 7200

local function SafeRegisterEvent(frame, eventName)
    if frame and frame.RegisterEvent then
        pcall(frame.RegisterEvent, frame, eventName)
    end
end

local function SafeUnregisterEvent(frame, eventName)
    if frame and frame.UnregisterEvent then
        pcall(frame.UnregisterEvent, frame, eventName)
    end
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
end

-- ============================================================================
-- Stepped Tier Order-Book Verification & Dynamic Price Circuit Breaker
-- ============================================================================

-- Walks live AH order books tier-by-tier for `play` and checks whether a price spike
-- in deeper tiers pushes cumulative or marginal CPSP above `runnerUpCPSP` (Candidate #2).
-- Returns a verification result table with `circuitBreakerTripped`, `pivotRecommended`,
-- `safeCraftsBeforeSpike`, `liveNetCost`, `liveCPSP`, and `tiersByItem`.
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

        -- Circuit Breaker check: if deeper tier spikes cumulative OR marginal CPSP above candidate #2
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

-- Runs circuit-breaker validation across the ranked Top N plays and pivots if #1 spikes past #2
function LL.AHVerifier.EvaluateCircuitBreakersOnPlays(plays, customOrderBooks)
    if type(plays) ~= "table" or #plays == 0 then return plays, false end
    local pivoted = false
    local runnerUp = plays[2]
    local runnerUpCPSP = runnerUp and runnerUp.cpsp or nil

    local res = LL.AHVerifier.VerifyPlayWithCircuitBreaker(plays[1], runnerUpCPSP, customOrderBooks)
    if res.pivotRecommended and runnerUp then
        -- If 0 crafts are safe before the spike, pivot candidate #2 to #1!
        if (res.safeCraftsBeforeSpike or 0) == 0 then
            plays[1], plays[2] = plays[2], plays[1]
            plays[1].rank = 1
            plays[2].rank = 2
            plays[1].pivotedFromCircuitBreaker = true
            pivoted = true
        else
            -- Partial crafts are still cheaper than #2 before the spike tier hits
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

    local topPlays = LL.LevelingEngine.FindTopPlays(professionOrLine)
    topPlays = LL.AHVerifier.EvaluateCircuitBreakersOnPlays(topPlays)

    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.lastTopPlays = topPlays

    if onFinishCallback then
        onFinishCallback(topPlays, reason or "COMPLETE")
    end
    if LL.SideWindow and LL.SideWindow.Refresh then
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

    local initialTop = LL.LevelingEngine.FindTopPlays(professionOrLine, nil, nil, { limit = math.max(candidateCount, topCount) })
    local topN = {}
    for i = 1, math.min(topCount, #initialTop) do
        topN[i] = initialTop[i]
    end
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
-- 1-Click Auction House Search Integration
-- ============================================================================

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

    -- 1. Legacy AuctionFrame path
    if _G.AuctionFrame and (not _G.AuctionHouseFrame or not _G.AuctionHouseFrame:IsShown()) then
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
        local searchBar = _G.AuctionHouseFrame.SearchBar
        if searchBar and searchBar.SearchBox and searchBar.SearchBox.SetText and searchName then
            pcall(searchBar.SearchBox.SetText, searchBar.SearchBox, searchName)
        end

        if itemId and itemId > 0 and _G.C_AuctionHouse then
            local itemKey = LL.AHVerifier.MakeItemKey(itemId)
            activeSearchItemKey = itemKey
            if _G.AuctionHouseFrame.SelectBrowseResult then
                local minPrice = LL.LevelingEngine.ResolveAHUnitPrice(itemId) or 0
                pcall(_G.AuctionHouseFrame.SelectBrowseResult, _G.AuctionHouseFrame, {
                    itemKey = itemKey,
                    minPrice = minPrice,
                    totalQuantity = desiredQuantity,
                })
                return true
            elseif _G.C_AuctionHouse.SendSearchQuery then
                pcall(_G.C_AuctionHouse.SendSearchQuery, itemKey, { { sortOrder = 0, reverseSort = false } }, false)
                return true
            end
        end

        if _G.C_AuctionHouse and _G.C_AuctionHouse.SendBrowseQuery and searchName then
            pcall(_G.C_AuctionHouse.SendBrowseQuery, { searchString = searchName, sorts = {}, filters = {} })
            return true
        end
    end

    print(string.format("|cffff9900[Leveling Lad]|r Open the Auction House to search for [%s].", searchName or "Item"))
    return false
end

-- ============================================================================
-- Purchased-In-Mailbox Tracking (Auto-Decrements on Bag Arrival)
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
        pendingCommodityPurchase = nil
    end
end

function LL.AHVerifier.GetPurchasedInMailCount(itemId)
    if not itemId or itemId <= 0 then return 0 end
    local tbl = GetCharMailTable(false)
    if not tbl then return 0 end
    local entry = tbl[itemId]
    if type(entry) ~= "table" or (entry.count or 0) <= 0 then
        tbl[itemId] = nil
        return 0
    end
    local now = (_G.time and _G.time()) or 0
    if (now - (entry.updatedAt or 0)) > PURCHASED_MAIL_TTL_SECONDS then
        tbl[itemId] = nil
        return 0
    end

    local currentBags = LL.Formatter.GetInventoryCount(itemId, false)
    if type(entry.lastBagCount) == "number" and currentBags > entry.lastBagCount then
        local gained = currentBags - entry.lastBagCount
        entry.count = math.max(0, (entry.count or 0) - gained)
    end
    entry.lastBagCount = currentBags
    if entry.count <= 0 then
        tbl[itemId] = nil
        return 0
    end
    return entry.count
end

function LL.AHVerifier.RecordConfirmedPurchase(itemId, itemName, qty, source)
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
    local existing = LL.AHVerifier.GetPurchasedInMailCount(itemId)
    local currentBags = LL.Formatter.GetInventoryCount(itemId, false)
    tbl[itemId] = {
        count = existing + qty,
        itemName = itemName,
        updatedAt = (_G.time and _G.time()) or 0,
        lastBagCount = currentBags,
    }

    if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
        LL.DetailWindow.RefreshIfShown()
    end
    return true
end

function LL.AHVerifier.Init()
    if LL.AHVerifier._initialized then return end
    LL.AHVerifier._initialized = true

    SafeRegisterEvent(verifierFrame, "AUCTION_HOUSE_CLOSED")
    SafeRegisterEvent(verifierFrame, "COMMODITY_PURCHASE_SUCCEEDED")
    SafeRegisterEvent(verifierFrame, "CHAT_MSG_SYSTEM")

    verifierFrame:SetScript("OnEvent", function(_, event, arg1)
        if event == "AUCTION_HOUSE_CLOSED" then
            if isRunning then
                LL.AHVerifier.Stop("AH_CLOSED")
            end
            return
        end

        if event == "AUCTION_ITEM_LIST_UPDATE" then
            if isRunning and currentQueryItem then
                CollectLegacyQueryResults(currentQueryItem)
                ScheduleNextVerification(0.10)
            end
            return
        end

        if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
            local itemId = tonumber(arg1) or (currentQueryItem and currentQueryItem.itemId) or activeSearchItemId
            if itemId then
                CollectModernCommodityResults(itemId)
                if isRunning and currentQueryItem and currentQueryItem.itemId == itemId then
                    ScheduleNextVerification(0.10)
                end
            end
            return
        end

        if event == "ITEM_SEARCH_RESULTS_UPDATED" then
            local itemId = (type(arg1) == "table" and arg1.itemID) or tonumber(arg1) or (currentQueryItem and currentQueryItem.itemId) or activeSearchItemId
            local itemKey = (type(arg1) == "table") and arg1 or nil
            if itemId then
                CollectModernItemResults(itemId, itemKey)
                if isRunning and currentQueryItem and currentQueryItem.itemId == itemId then
                    ScheduleNextVerification(0.10)
                end
            end
            return
        end

        if event == "COMMODITY_PURCHASE_SUCCEEDED" and pendingCommodityPurchase then
            LL.AHVerifier.RecordConfirmedPurchase(pendingCommodityPurchase.itemId, pendingCommodityPurchase.name, pendingCommodityPurchase.quantity, "EVENT")
            pendingCommodityPurchase = nil
            return
        end

        if event == "CHAT_MSG_SYSTEM" and type(arg1) == "string" then
            local wonName = arg1:match("^You won an auction for (.+)$")
            if wonName then
                local cleanName = wonName:gsub("%.$", "")
                local activePlay = LevelingLad_DB and LevelingLad_DB.activePlay
                if activePlay and type(activePlay.shoppingList) == "table" then
                    for _, shop in ipairs(activePlay.shoppingList) do
                        if shop.name and shop.name:lower() == cleanName:lower() then
                            LL.AHVerifier.RecordConfirmedPurchase(shop.itemId, shop.name, 1, "CHAT")
                            break
                        end
                    end
                end
            end
        end
    end)

    LL.AHVerifier.frame = verifierFrame
end
