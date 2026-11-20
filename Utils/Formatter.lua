local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.Formatter = {}

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"

local GOLD_SUFFIX = "|cffffd700g|r"
local SILVER_SUFFIX = "|cffc7c7cfs|r"
local COPPER_SUFFIX = "|cffeda55fc|r"

local QUALITY_HEX = {
    [0] = "cff9d9d9d", -- Poor
    [1] = "cffffffff", -- Common
    [2] = "cff1eff00", -- Uncommon
    [3] = "cff0070dd", -- Rare
    [4] = "cffa335ee", -- Epic
    [5] = "cffff8000", -- Legendary
}

local DIFFICULTY_META = {
    ORANGE  = { color = "|cffff8040", label = "Orange", rank = 1 },
    YELLOW  = { color = "|cffffff00", label = "Yellow", rank = 2 },
    GREEN   = { color = "|cff40bf40", label = "Green",  rank = 3 },
    GRAY    = { color = "|cff808080", label = "Gray",   rank = 4 },
    -- Legacy WoW API aliases
    optimal = { color = "|cffff8040", label = "Orange", rank = 1 },
    medium  = { color = "|cffffff00", label = "Yellow", rank = 2 },
    easy    = { color = "|cff40bf40", label = "Green",  rank = 3 },
    trivial = { color = "|cff808080", label = "Gray",   rank = 4 },
}

local function IsFiniteNumber(val)
    return type(val) == "number" and val == val and val > -math.huge and val < math.huge
end

-- Plain text money formatting without color escape sequences (e.g. "2g 45s", "12s 40c", "-5s")
function LL.Formatter.FormatMoneyPlain(copper, compact)
    if not IsFiniteNumber(copper) then
        return "0c"
    end
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = math.abs(copper)
    end
    copper = math.floor(copper + 0.5)
    if copper == 0 then
        return "0c"
    end

    local g = math.floor(copper / 10000) + 0
    local s = math.floor((copper % 10000) / 100) + 0
    local c = (copper % 100) + 0

    if compact then
        local parts = {}
        if g > 0 then
            table.insert(parts, string.format("%.0fg", g))
            if s > 0 then
                table.insert(parts, string.format("%ds", s))
            end
        elseif s > 0 then
            table.insert(parts, string.format("%ds", s))
            if c > 0 then
                table.insert(parts, string.format("%dc", c))
            end
        else
            table.insert(parts, string.format("%dc", c))
        end
        return sign .. table.concat(parts, "")
    end

    local parts = {}
    if g > 0 then table.insert(parts, string.format("%.0fg", g)) end
    if s > 0 then table.insert(parts, string.format("%ds", s)) end
    if c > 0 or #parts == 0 then table.insert(parts, string.format("%dc", c)) end
    return sign .. table.concat(parts, " ")
end

-- Colored WoW money formatting using |cffffd700g|r, |cffc7c7cfs|r, |cffeda55fc|r
function LL.Formatter.FormatMoney(copper, compact)
    if not IsFiniteNumber(copper) then
        return "0" .. COPPER_SUFFIX
    end
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = math.abs(copper)
    end
    copper = math.floor(copper + 0.5)
    if copper == 0 then
        return "0" .. COPPER_SUFFIX
    end

    local g = math.floor(copper / 10000) + 0
    local s = math.floor((copper % 10000) / 100) + 0
    local c = (copper % 100) + 0

    if compact then
        local parts = {}
        if g > 0 then
            table.insert(parts, string.format("%.0f%s", g, GOLD_SUFFIX))
            if s > 0 then
                table.insert(parts, string.format("%d%s", s, SILVER_SUFFIX))
            end
        elseif s > 0 then
            table.insert(parts, string.format("%d%s", s, SILVER_SUFFIX))
            if c > 0 then
                table.insert(parts, string.format("%d%s", c, COPPER_SUFFIX))
            end
        else
            table.insert(parts, string.format("%d%s", c, COPPER_SUFFIX))
        end
        return sign .. table.concat(parts, "")
    end

    local parts = {}
    if g > 0 then table.insert(parts, string.format("%.0f%s", g, GOLD_SUFFIX)) end
    if s > 0 then table.insert(parts, string.format("%d%s", s, SILVER_SUFFIX)) end
    if c > 0 or #parts == 0 then table.insert(parts, string.format("%d%s", c, COPPER_SUFFIX)) end
    return sign .. table.concat(parts, " ")
end

function LL.Formatter.FormatMoneyShort(copper)
    return LL.Formatter.FormatMoney(copper, true)
end

function LL.Formatter.FormatNetCost(copper, compact)
    if not IsFiniteNumber(copper) then
        return "0" .. COPPER_SUFFIX
    end
    if copper < 0 then
        return string.format("|cff00ff00+%s profit|r", LL.Formatter.FormatMoney(math.abs(copper), compact))
    end
    return LL.Formatter.FormatMoney(copper, compact)
end

function LL.Formatter.FormatTooltipMoney(copper)
    if not IsFiniteNumber(copper) then
        return "0" .. COPPER_SUFFIX
    end
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = math.abs(copper)
    end
    copper = math.floor(copper + 0.5)
    if copper == 0 then
        return "0" .. COPPER_ICON
    end
    if _G.GetCoinTextureString then
        local ok, formatted = pcall(_G.GetCoinTextureString, copper)
        if ok and type(formatted) == "string" and formatted ~= "" then
            return sign .. formatted
        end
    end
    local g = math.floor(copper / 10000) + 0
    local s = math.floor((copper % 10000) / 100) + 0
    local c = (copper % 100) + 0
    local parts = {}
    if g > 0 then table.insert(parts, string.format("%.0f%s", g, GOLD_ICON)) end
    if s > 0 then table.insert(parts, string.format("%d%s", s, SILVER_ICON)) end
    if c > 0 or #parts == 0 then table.insert(parts, string.format("%d%s", c, COPPER_ICON)) end
    return sign .. table.concat(parts, " ")
end

function LL.Formatter.GetDifficultyColor(difficulty)
    local meta = difficulty and DIFFICULTY_META[difficulty]
    if meta then
        return meta.color
    end
    return "|cffffffff"
end

function LL.Formatter.GetDifficultyLabel(difficulty)
    local meta = difficulty and DIFFICULTY_META[difficulty]
    if meta then
        return meta.label
    end
    return tostring(difficulty or "Unknown")
end

function LL.Formatter.FormatDifficultyBadge(startDiff, endDiff)
    local sMeta = (startDiff and DIFFICULTY_META[startDiff]) or DIFFICULTY_META.ORANGE
    if not endDiff or endDiff == startDiff then
        return string.format("%s[%s]|r", sMeta.color, sMeta.label)
    end
    local eMeta = DIFFICULTY_META[endDiff] or sMeta
    return string.format("%s[%s|r -> %s%s]|r", sMeta.color, sMeta.label, eMeta.color, eMeta.label)
end

function LL.Formatter.FormatSkillRange(startSkill, endSkill)
    return string.format("%d -> %d", math.floor(tonumber(startSkill) or 0), math.floor(tonumber(endSkill) or 0))
end

function LL.Formatter.GetPlayerGold()
    if _G.GetMoney then
        local ok, money = pcall(_G.GetMoney)
        if ok and type(money) == "number" and money >= 0 then
            return math.floor(money)
        end
    end
    return 0
end

function LL.Formatter.GetInventoryCount(itemId, includeBank)
    if not itemId or itemId <= 0 then return 0 end
    if _G.C_Item and _G.C_Item.GetItemCount then
        local ok, count = pcall(_G.C_Item.GetItemCount, itemId, includeBank == true, false, false)
        if ok and type(count) == "number" then
            return math.floor(count)
        end
    end
    if _G.GetItemCount then
        local ok, count = pcall(_G.GetItemCount, itemId, includeBank == true)
        if ok and type(count) == "number" then
            return math.floor(count)
        end
    end
    return 0
end

function LL.Formatter.GetItemIcon(itemId)
    if not itemId or itemId <= 0 then
        return "Interface\\Icons\\INV_Misc_QuestionMark"
    end
    if _G.C_Item and _G.C_Item.GetItemIconByID then
        local ok, icon = pcall(_G.C_Item.GetItemIconByID, itemId)
        if ok and icon then return icon end
    end
    if _G.GetItemIcon then
        local ok, icon = pcall(_G.GetItemIcon, itemId)
        if ok and icon then return icon end
    end
    local meta = LL.VendorDatabase and LL.VendorDatabase.GetItemMetadata and LL.VendorDatabase.GetItemMetadata(itemId, nil, true)
    if meta and meta.texture then
        return meta.texture
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function LL.Formatter.BuildItemLink(itemId, itemName, quality, existingLink)
    if type(existingLink) == "string" and existingLink:find("|Hitem:") then
        return existingLink
    end
    if not itemId or itemId <= 0 then
        return string.format("|cffffd100[%s]|r", tostring(itemName or "Unknown Recipe"))
    end
    local info = LL.VendorDatabase and LL.VendorDatabase.GetItemMetadata and LL.VendorDatabase.GetItemMetadata(itemId, nil, true)
    if info and type(info.link) == "string" and info.link:find("|Hitem:") then
        return info.link
    end
    local resolvedName = itemName or (info and info.name) or string.format("Item #%d", itemId)
    local resolvedQuality = quality or (info and info.quality) or 1
    local hex = QUALITY_HEX[resolvedQuality] or QUALITY_HEX[1]
    return string.format("|%s|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r", hex, itemId, resolvedName)
end
