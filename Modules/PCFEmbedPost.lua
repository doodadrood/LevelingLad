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

-- Pause passive PCF sniffing while Leveling Lad's AHVerifier is running live order-book queries
if _G.PCF and type(_G.PCF.Scanner) == "table" then
    if type(_G.PCF.Scanner.SniffCommoditySearchResults) == "function" then
        local origSniffCommodity = _G.PCF.Scanner.SniffCommoditySearchResults
        _G.PCF.Scanner.SniffCommoditySearchResults = function(itemId)
            if _G.LL and _G.LL.AHVerifier and _G.LL.AHVerifier.IsRunning and _G.LL.AHVerifier.IsRunning() then
                return 0
            end
            return origSniffCommodity(itemId)
        end
    end

    if type(_G.PCF.Scanner.SniffItemSearchResults) == "function" then
        local origSniffItem = _G.PCF.Scanner.SniffItemSearchResults
        _G.PCF.Scanner.SniffItemSearchResults = function(itemKey)
            if _G.LL and _G.LL.AHVerifier and _G.LL.AHVerifier.IsRunning and _G.LL.AHVerifier.IsRunning() then
                return 0
            end
            return origSniffItem(itemKey)
        end
    end
end

-- Helper for resolving external AH price fallbacks (PCF -> TSM -> Auctionator)
function LL.ResolveExternalAHPrice(itemId, itemLink)
    if not itemId or itemId <= 0 then return nil end

    -- 1. PriceCheckerForever (standalone or embedded)
    if _G.PCF_DB and type(_G.PCF_DB.prices) == "table" then
        local entry = _G.PCF_DB.prices[itemId]
        if type(entry) == "table" and type(entry.minBuyout) == "number" and entry.minBuyout > 0 then
            return math.floor(entry.minBuyout)
        end
    end

    if _G.PCF and _G.PCF.ProviderRegistry and type(_G.PCF.ProviderRegistry.ResolveAHPrice) == "function" then
        local ok, price = pcall(_G.PCF.ProviderRegistry.ResolveAHPrice, itemLink, itemId)
        if ok and type(price) == "number" and price > 0 then
            return math.floor(price)
        end
    end

    -- 2. TradeSkillMaster (TSM) fallback
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

    -- 3. Auctionator fallback
    if _G.Auctionator and _G.Auctionator.API and _G.Auctionator.API.v1
        and type(_G.Auctionator.API.v1.GetAuctionPriceByItemID) == "function" then
        local ok, val = pcall(_G.Auctionator.API.v1.GetAuctionPriceByItemID, "LevelingLad", itemId)
        if ok and type(val) == "number" and val > 0 then
            return math.floor(val)
        end
    end

    return nil
end
