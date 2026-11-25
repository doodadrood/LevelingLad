-- Restores standalone PriceCheckerForever globals or marks embedded PCF active
local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

if LL._standalonePCFActive and type(LL._savedStandalonePCF) == "table" then
    _G.PCF = LL._savedStandalonePCF
    _G.GPC = LL._savedStandalonePCF
    if LL._savedStandalonePCFAPI ~= nil then
        _G.PCF_API = LL._savedStandalonePCFAPI
    end
    if type(LL._savedStandalonePCFDB) == "table" then
        _G.PCF_DB = LL._savedStandalonePCFDB
        _G.GPC_DB = LL._savedStandalonePCFDB
    end
    LL._embeddedPCFActive = false
elseif _G.PCF_API then
    LL._embeddedPCFActive = true
else
    LL._embeddedPCFActive = false
end

LL._savedStandalonePCF = nil
LL._savedStandalonePCFDB = nil
LL._savedStandalonePCFAPI = nil

local function IsAnyVerifierRunning()
    if _G.LL and _G.LL.AHVerifier and _G.LL.AHVerifier.IsRunning and _G.LL.AHVerifier.IsRunning() then
        return true
    end
    if _G.PF and _G.PF.AHVerifier and _G.PF.AHVerifier.IsRunning and _G.PF.AHVerifier.IsRunning() then
        return true
    end
    return false
end

local function GetActiveSellFrameItem()
    local ahFrame = _G.AuctionHouseFrame
    if not ahFrame then
        return nil, nil
    end

    local sellFrames = {
        ahFrame.CommoditiesSellFrame,
        ahFrame.ItemSellFrame,
    }

    for _, sellFrame in ipairs(sellFrames) do
        if sellFrame and (not sellFrame.IsShown or sellFrame:IsShown()) then
            local itemKey = sellFrame.GetItemKey and sellFrame:GetItemKey()
            local itemLoc = (sellFrame.GetItem and sellFrame:GetItem()) or sellFrame.itemLocation
            local itemId = (type(itemKey) == "table" and itemKey.itemID) or nil

            if not itemId and itemLoc then
                if _G.C_Item and _G.C_Item.GetItemID then
                    local okId, resolvedId = pcall(_G.C_Item.GetItemID, itemLoc)
                    if okId and resolvedId then
                        itemId = resolvedId
                    end
                end
                if not itemKey and _G.C_AuctionHouse and _G.C_AuctionHouse.GetItemKeyFromItem then
                    local okKey, resolvedKey = pcall(_G.C_AuctionHouse.GetItemKeyFromItem, itemLoc)
                    if okKey and type(resolvedKey) == "table" then
                        itemKey = resolvedKey
                        itemId = itemId or resolvedKey.itemID
                    end
                end
            end

            if itemId and itemId > 0 then
                return itemId, itemKey
            end
        end
    end

    return nil, nil
end

-- Pause passive PCF sniffing while AHVerifier is running live order-book queries,
-- and ensure SniffItemSearchResults treats C_AuctionHouse.GetItemSearchResultInfo's
-- buyoutAmount as per-item buyout rather than dividing by collapsed row.quantity.
if _G.PCF and type(_G.PCF.Scanner) == "table" then
    if type(_G.PCF.Scanner.SniffCommoditySearchResults) == "function" and not _G.PCF.Scanner._llWrappedCommoditySniff then
        local origSniffCommodity = _G.PCF.Scanner.SniffCommoditySearchResults
        _G.PCF.Scanner.SniffCommoditySearchResults = function(itemId)
            if IsAnyVerifierRunning() then
                return 0
            end
            return origSniffCommodity(itemId)
        end
        _G.PCF.Scanner._llWrappedCommoditySniff = true
    end

    _G.PCF.Scanner.SniffItemSearchResults = function(itemKey)
        if IsAnyVerifierRunning() then
            return 0
        end
        if not (_G.PCF_DB and _G.PCF_DB.settings and _G.PCF_DB.settings.enabled ~= false and _G.PCF_DB.settings.passiveSniffing ~= false) then
            return 0
        end
        local scanBtn = _G.PCF.Scanner.scanButton
        if scanBtn and type(scanBtn.GetText) == "function" and scanBtn:GetText() == "Stop Scan" then
            return 0
        end
        if not _G.C_AuctionHouse or not _G.C_AuctionHouse.GetNumItemSearchResults or not _G.C_AuctionHouse.GetItemSearchResultInfo then
            return 0
        end

        if not itemKey then
            local activeId, activeKey = GetActiveSellFrameItem()
            itemKey = activeKey or activeId
        end

        local itemId = (type(itemKey) == "table" and itemKey.itemID) or tonumber(itemKey)
        if not itemId or itemId <= 0 then
            return 0
        end

        local queryKey = type(itemKey) == "table" and itemKey or { itemID = itemId, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }
        local okNum, numResults = pcall(_G.C_AuctionHouse.GetNumItemSearchResults, queryKey)
        if not okNum or not numResults or numResults <= 0 then
            return 0
        end

        local now = (_G.time and _G.time()) or 0
        local limit = math.min(numResults, 50)
        local minUnitBuyout = nil
        local minUnitBid = nil
        local totalQty = 0

        for i = 1, limit do
            local okInfo, result = pcall(_G.C_AuctionHouse.GetItemSearchResultInfo, queryKey, i)
            if okInfo and type(result) == "table" then
                local unitBuyout = (result.buyoutAmount and result.buyoutAmount > 0) and math.floor(result.buyoutAmount) or nil
                if unitBuyout and unitBuyout > 0 then
                    local unitBid = (result.minBid and result.minBid > 0 and math.floor(result.minBid))
                        or (result.bidAmount and result.bidAmount > 0 and math.floor(result.bidAmount))
                        or unitBuyout
                    local quantity = (result.quantity and result.quantity > 0) and math.floor(result.quantity) or 1
                    totalQty = totalQty + quantity
                    if not minUnitBuyout or unitBuyout < minUnitBuyout then
                        minUnitBuyout = unitBuyout
                    end
                    if not minUnitBid or unitBid < minUnitBid then
                        minUnitBid = unitBid
                    end
                end
            end
        end

        if not minUnitBuyout or minUnitBuyout <= 0 or totalQty <= 0 then
            return 0
        end

        _G.PCF_DB.prices = _G.PCF_DB.prices or {}
        local existing = _G.PCF_DB.prices[itemId]
        if existing then
            existing.minBuyout = minUnitBuyout
            existing.minBid = minUnitBid or minUnitBuyout
            existing.lastUpdated = now
            existing.count = totalQty
            existing.source = "PCF Sniff"
        else
            _G.PCF_DB.prices[itemId] = {
                minBuyout = minUnitBuyout,
                minBid = minUnitBid or minUnitBuyout,
                lastUpdated = now,
                count = totalQty,
                source = "PCF Sniff",
            }
        end

        if _G.LL and _G.LL.InvalidateAHStatusCache then
            _G.LL.InvalidateAHStatusCache()
        end
        if _G.PCF.MeshSync and _G.PCF.MeshSync.MarkDirty then
            _G.PCF.MeshSync.MarkDirty(itemId)
        end
        if _G.PCF.Tooltip and _G.PCF.Tooltip.RefreshVisibleTooltip then
            _G.PCF.Tooltip.RefreshVisibleTooltip()
        end

        return 1
    end
end

-- Preserve PCF v1.0.24+ recipe & item tooltip features while suppressing tooltip:Show()
-- inside modern TooltipDataProcessor post-calls / RefreshVisibleTooltip and skipping
-- RefreshVisibleTooltip during combat (preventing GameTooltip / ContainerFrame taint).
if _G.PCF and type(_G.PCF.Tooltip) == "table" and not _G.PCF.Tooltip._llTaintSafeWrapped then
    local origOnTooltipSetItem = _G.PCF.Tooltip.OnTooltipSetItem
    if type(origOnTooltipSetItem) == "function" then
        local function CallTooltipWithoutShow(tooltip, tooltipData)
            if not tooltip then return end
            local hadOwnShow = rawget(tooltip, "Show") ~= nil
            local savedShow = rawget(tooltip, "Show")
            rawset(tooltip, "Show", false)
            local ok, err = pcall(origOnTooltipSetItem, tooltip, tooltipData)
            if hadOwnShow then
                rawset(tooltip, "Show", savedShow)
            else
                rawset(tooltip, "Show", nil)
            end
            if not ok and _G.geterrorhandler then
                pcall(_G.geterrorhandler(), err)
            end
        end

        _G.PCF.Tooltip.OnTooltipSetItem = function(tooltip, tooltipData, allowShow)
            if not tooltip then return end
            local hasTooltipDataProcessor = (_G.TooltipDataProcessor
                and _G.TooltipDataProcessor.AddTooltipPostCall
                and _G.Enum
                and _G.Enum.TooltipDataType
                and _G.Enum.TooltipDataType.Item) ~= nil
            local shouldShow = (allowShow == true) or (allowShow == nil and not hasTooltipDataProcessor)
            if shouldShow then
                return origOnTooltipSetItem(tooltip, tooltipData)
            end
            CallTooltipWithoutShow(tooltip, tooltipData)
        end

        _G.PCF.Tooltip.RefreshVisibleTooltip = function()
            if _G.InCombatLockdown and _G.InCombatLockdown() then return end
            if _G.GameTooltip and (not _G.GameTooltip.IsShown or _G.GameTooltip:IsShown()) then
                _G.PCF.Tooltip.OnTooltipSetItem(_G.GameTooltip, nil, false)
            end
            if _G.ItemRefTooltip and (not _G.ItemRefTooltip.IsShown or _G.ItemRefTooltip:IsShown()) then
                _G.PCF.Tooltip.OnTooltipSetItem(_G.ItemRefTooltip, nil, false)
            end
        end
        _G.PCF.Tooltip._llTaintSafeWrapped = true
    end
end

local function GetPCFPriceInfo(itemId)
    if _G.PCF_DB and type(_G.PCF_DB.prices) == "table" then
        local entry = _G.PCF_DB.prices[itemId]
        if type(entry) == "table" and type(entry.minBuyout) == "number" and entry.minBuyout > 0 then
            local ts = tonumber(entry.lastUpdated) or 0
            if ts <= 0 then
                ts = math.max(tonumber(_G.PCF_DB.lastFullScan) or 0, tonumber(_G.PCF_DB.lastReplicateScan) or 0)
            end
            return math.floor(entry.minBuyout), ts
        end
    end
    return nil, 0
end

local function GetAuctionatorPriceInfo(itemId, itemLink)
    if LL.AuctionatorSource and LL.AuctionatorSource.GetItemData then
        local data = LL.AuctionatorSource.GetItemData(itemId, itemLink)
        if data and type(data.minBuyout) == "number" and data.minBuyout > 0 then
            return math.floor(data.minBuyout), tonumber(data.timestamp) or 0
        end
    end
    if _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
        and type(_G.Auctionator.API.v1.GetAuctionPriceByItemID) == "function" then
        local ok, val = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, "LevelingLad", itemId)
        if ok and type(val) == "number" and val > 0 then
            return math.floor(val), 0
        end
    end
    return nil, 0
end

local function GetTSMPrice(itemId)
    if _G.TSM_API and type(_G.TSM_API.GetCustomPriceValue) == "function" then
        local itemStr = "i:" .. tostring(itemId)
        local ok, val = pcall(_G.TSM_API.GetCustomPriceValue, "DBMinBuyout", itemStr)
        if not ok or type(val) ~= "number" or val <= 0 then
            ok, val = pcall(_G.TSM_API.GetCustomPriceValue, "DBMarket", itemStr)
        end
        if ok and type(val) == "number" and val > 0 then
            return math.floor(val)
        end
    end
    return nil
end

-- Resolves external AH price respecting LevelingLad_DB.settings.priceSource ("AUTO" | "PCF" | "AUCTIONATOR")
function LL.ResolveExternalAHPrice(itemId, itemLink)
    if not itemId or itemId <= 0 then return nil end

    local mode = (LL.GetPriceSourceMode and LL.GetPriceSourceMode()) or "AUTO"

    if mode == "AUCTIONATOR" then
        local atrPrice = GetAuctionatorPriceInfo(itemId, itemLink)
        return atrPrice
    end

    local pcfPrice, pcfTs = GetPCFPriceInfo(itemId)

    if mode == "PCF" then
        if pcfPrice then
            return pcfPrice
        end
        return GetTSMPrice(itemId)
    end

    -- AUTO mode: prefer whichever of PCF or Auctionator has the fresher scan timestamp
    local atrPrice, atrTs = GetAuctionatorPriceInfo(itemId, itemLink)
    if pcfPrice and atrPrice then
        if atrTs > 0 and atrTs > pcfTs then
            return atrPrice
        end
        return pcfPrice
    elseif pcfPrice then
        return pcfPrice
    elseif atrPrice then
        return atrPrice
    end

    if _G.PCF and _G.PCF.ProviderRegistry and type(_G.PCF.ProviderRegistry.ResolveAHPrice) == "function" then
        local ok, price = pcall(_G.PCF.ProviderRegistry.ResolveAHPrice, itemLink, itemId)
        if ok and type(price) == "number" and price > 0 then
            return math.floor(price)
        end
    end

    return GetTSMPrice(itemId)
end
