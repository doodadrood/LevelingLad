local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

function LL.IsSecret(val)
    if val == nil then return false end
    if _G.issecretvalue then
        local ok, isSec = pcall(_G.issecretvalue, val)
        if ok and isSec then
            return true
        end
    end
    if _G.canaccessvalue then
        local ok, canAccess = pcall(_G.canaccessvalue, val)
        if ok and not canAccess then
            return true
        end
    end
    return false
end

LevelingLad_DB = LevelingLad_DB or {}
_G.LevelingLad_DB = LevelingLad_DB

local MILESTONES = { 75, 150, 225, 300 }

local defaultConfig = {
    version = 1,
    settings = {
        enabled = true,
        budgetCopper = 0,                    -- 0 = unlimited (uses full character gold); >0 = hard gold cap in copper
        targetSkillRank = 0,                 -- 0 = auto next milestone (75/150/225/300); >0 = explicit target skill
        targetMode = "MILESTONE",            -- "PLUS5" | "PLUS10" | "MILESTONE" | "CUSTOM"
        customTargetSkill = 75,              -- Used when targetMode == "CUSTOM"
        selectedProfession = nil,            -- Active skillLine ID or profession name (nil = auto-detect)
        recoveryMode = "VENDOR",             -- "VENDOR" (default/safest) | "AH" (resale after AH cut) | "NONE"
        riskTolerance = "SAFE",              -- "SAFE" | "BALANCED" | "AGGRESSIVE"
        includeTrainerRecipes = true,        -- Look ahead to trainer-taught recipes up to +trainerSkillLookahead
        trainerSkillLookahead = 25,          -- Max skill points ahead for trainer recipe lookahead
        includeVendorArbitrage = true,       -- Always price unlimited NPC vendor reagents at vendor rates
        orderBookVerify = true,              -- Walk live AH order books before finalizing shopping lists
        buyoutOnly = true,                   -- Exclude bid-only listings without buyout price
        ahCutRate = 0.05,                    -- Standard 5% faction AH cut (auto-switches to 15% at Neutral AH)
        topCount = 5,                        -- Number of top plays to display in Side Window
        verifyCandidateCount = 10,           -- Number of top candidates to live-verify at AH
        maxCalculationSeconds = 90,          -- Max seconds for live AH verification loop
        showSideWindow = true,               -- Auto-show docked Side Window when opening AH
        onboardingDismissed = false,         -- Show welcome/AH-scan popup until dismissed
        staleDataThresholdSeconds = 86400,   -- Warn when cached AH data is older than 24 hours
    },
    charRecipes = {},        -- [charKey] = { [recipeKey] = recipeTable }
    charSkills = {},         -- [charKey] = { [skillLine] = { name, rank, maxRank, skillLine } }
    vendorBuyPrices = {},    -- [itemId] = copperPrice (dynamically updated from MERCHANT_SHOW)
    itemCache = {},          -- [itemId] = { name, link, quality, itemLevel, classID, subClassID, invType, texture, vendorSell }
    orderBookCache = {},     -- [itemId] = { timestamp = 0, listings = { { unitPrice, quantity }, ... }, unavailable = false }
    lastTopPlays = {},       -- Cached Top 5 immediate leveling plays
    lastRoadmap = nil,       -- Cached multi-step milestone roadmap
    activePlay = nil,        -- Currently tracked play in DetailWindow
    purchasedInMail = {},    -- [charKey] = { [itemId] = { count, spentCopper, updatedAt, lastBagCount } }
}

local function ApplyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            ApplyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

function LL.GetCharacterKey()
    local name = (_G.UnitName and _G.UnitName("player")) or "Player"
    local realm = (_G.GetRealmName and _G.GetRealmName()) or "Forever"
    return string.format("%s-%s", tostring(name), tostring(realm))
end

-- Parses user gold input into copper.
-- Accepts: "", "0", "auto", "all", "reset", "off" -> 0 (use full player gold)
--          Plain gold numbers like "10" or "12.5" -> 100000 / 125000 copper
--          Currency strings like "10g", "10g 50s", "50s", "1g 25s 50c" -> exact copper
-- Returns copper (number >= 0) or nil if input cannot be parsed.
function LL.ParseGoldToCopper(input)
    if input == nil then return 0 end
    if type(input) == "number" then
        if input ~= input or input < 0 or input >= math.huge then return nil end
        return math.floor(input + 0.5)
    end
    if type(input) ~= "string" then return nil end
    local trimmed = input:lower():match("^%s*(.-)%s*$") or ""
    if trimmed == "" or trimmed == "0" or trimmed == "auto" or trimmed == "all" or trimmed == "reset" or trimmed == "off" or trimmed == "none" then
        return 0
    end

    local plainNum = tonumber(trimmed)
    if plainNum then
        if plainNum < 0 or plainNum >= math.huge then return nil end
        return math.floor((plainNum * 10000) + 0.5)
    end

    local remainder = trimmed:gsub("%s+", "")
    local total = 0
    local matchedAny = false
    local g = remainder:match("(%d+%.?%d*)g")
    if g then
        total = total + math.floor((tonumber(g) * 10000) + 0.5)
        remainder = remainder:gsub("%d+%.?%d*g", "", 1)
        matchedAny = true
    end
    local s = remainder:match("(%d+%.?%d*)s")
    if s then
        total = total + math.floor((tonumber(s) * 100) + 0.5)
        remainder = remainder:gsub("%d+%.?%d*s", "", 1)
        matchedAny = true
    end
    local c = remainder:match("(%d+)c")
    if c then
        total = total + math.floor(tonumber(c))
        remainder = remainder:gsub("%d+c", "", 1)
        matchedAny = true
    end

    if matchedAny and remainder == "" then
        return math.max(0, total)
    end
    return nil
end

-- Returns: effectiveBudgetCopper, isCapped, playerGoldCopper, configuredBudgetCopper
-- Never exceeds current character gold OR configured budgetCopper.
function LL.GetEffectiveBudget(budgetOverride)
    local playerGold = (LL.Formatter and LL.Formatter.GetPlayerGold and LL.Formatter.GetPlayerGold()) or 0
    if type(budgetOverride) == "number" then
        local ov = math.max(0, math.floor(budgetOverride))
        if ov > 0 then
            return ov, true, playerGold, ov
        end
        return playerGold, false, playerGold, 0
    end

    local configured = LevelingLad_DB and LevelingLad_DB.settings and tonumber(LevelingLad_DB.settings.budgetCopper) or 0
    configured = math.max(0, math.floor(configured))
    if configured > 0 then
        return math.min(playerGold, configured), true, playerGold, configured
    end
    return playerGold, false, playerGold, 0
end

-- Returns the next classic profession bracket milestone (75, 150, 225, 300) strictly above currentSkill.
function LL.GetNextMilestone(currentSkill, maxRank)
    currentSkill = math.max(0, math.floor(tonumber(currentSkill) or 1))
    for _, m in ipairs(MILESTONES) do
        if currentSkill < m then
            return m
        end
    end
    if type(maxRank) == "number" and maxRank > currentSkill then
        return math.floor(maxRank)
    end
    return 300
end

-- Resolves the effective target skill rank from settings or an explicit override.
function LL.GetTargetSkill(currentSkill, maxRank, targetOverride)
    currentSkill = math.max(1, math.floor(tonumber(currentSkill) or 1))
    local ceiling = math.max(300, math.floor(tonumber(maxRank) or 300))

    if type(targetOverride) == "number" and targetOverride > currentSkill then
        return math.min(ceiling, math.floor(targetOverride))
    end

    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    local mode = settings.targetMode or "MILESTONE"
    local explicit = tonumber(settings.targetSkillRank) or 0

    if mode == "PLUS5" then
        return math.min(ceiling, currentSkill + 5)
    elseif mode == "PLUS10" then
        return math.min(ceiling, currentSkill + 10)
    elseif mode == "CUSTOM" then
        local custom = tonumber(settings.customTargetSkill) or explicit
        if custom and custom > currentSkill then
            return math.min(ceiling, math.floor(custom))
        end
        return math.min(ceiling, currentSkill + 5)
    end

    if explicit > currentSkill then
        return math.min(ceiling, math.floor(explicit))
    end
    return math.min(ceiling, LL.GetNextMilestone(currentSkill, maxRank))
end

-- Returns 0.15 at a Neutral AH, otherwise the configured faction AH cut (default 0.05).
function LL.GetEffectiveAHCutRate()
    if _G.GetAuctionHouseDepositRate then
        local ok, depRate = pcall(_G.GetAuctionHouseDepositRate)
        if ok and type(depRate) == "number" and depRate > 5 then
            return 0.15
        end
    end
    local configured = LevelingLad_DB and LevelingLad_DB.settings and LevelingLad_DB.settings.ahCutRate
    if type(configured) == "number" and configured >= 0 and configured < 1 then
        return configured
    end
    return 0.05
end

function LL.FormatAgeShort(ageSeconds)
    if type(ageSeconds) ~= "number" or ageSeconds < 0 or ageSeconds >= math.huge then
        return "never"
    end
    local secs = math.floor(ageSeconds)
    if secs >= 86400 then
        local d = math.floor(secs / 86400)
        local h = math.floor((secs % 86400) / 3600)
        return string.format("%dd %dh", d, h)
    elseif secs >= 3600 then
        local h = math.floor(secs / 3600)
        local m = math.floor((secs % 3600) / 60)
        return string.format("%dh %dm", h, m)
    elseif secs >= 60 then
        return string.format("%dm", math.floor(secs / 60))
    end
    return "0m"
end

-- Evaluates whether Auction House price data is available and fresh.
-- Returns: status ("NO_DATA" | "STALE" | "FRESH"), detailsTable
function LL.GetAHDataStatus()
    local now = (_G.time and _G.time()) or 0
    local threshold = (LevelingLad_DB and LevelingLad_DB.settings and tonumber(LevelingLad_DB.settings.staleDataThresholdSeconds)) or 86400

    local pcfItems = 0
    local newestEntryTs = 0
    local hasUntimestampedEntry = false

    if _G.PCF_DB and type(_G.PCF_DB.prices) == "table" then
        for itemId, entry in pairs(_G.PCF_DB.prices) do
            if type(itemId) == "number" and itemId > 0 and type(entry) == "table" and entry.minBuyout and entry.minBuyout > 0 then
                pcfItems = pcfItems + 1
                local ts = tonumber(entry.lastUpdated) or 0
                if ts > newestEntryTs then
                    newestEntryTs = ts
                elseif ts <= 0 then
                    hasUntimestampedEntry = true
                end
            end
        end
    end

    local obItems = 0
    local newestOBTs = 0
    if LevelingLad_DB and type(LevelingLad_DB.orderBookCache) == "table" then
        for itemId, ob in pairs(LevelingLad_DB.orderBookCache) do
            if type(itemId) == "number" and itemId > 0 and type(ob) == "table" and not ob.unavailable and type(ob.listings) == "table" and #ob.listings > 0 then
                obItems = obItems + 1
                local ts = tonumber(ob.timestamp) or 0
                if ts > newestOBTs then
                    newestOBTs = ts
                end
            end
        end
    end

    local lastScanTs = 0
    if _G.PCF_DB then
        local fullTs = tonumber(_G.PCF_DB.lastFullScan) or 0
        local repTs = tonumber(_G.PCF_DB.lastReplicateScan) or 0
        lastScanTs = math.max(fullTs, repTs)
    end

    local totalItems = math.max(pcfItems, obItems)
    local bestTs = math.max((pcfItems > 0 and ((lastScanTs > 0) and lastScanTs or newestEntryTs)) or 0, newestOBTs)

    if totalItems <= 0 then
        return "NO_DATA", {
            status = "NO_DATA",
            itemCount = 0,
            pcfItems = 0,
            orderBookItems = 0,
            lastScanTimestamp = 0,
            ageSeconds = nil,
            ageText = "never",
        }
    end

    if bestTs <= 0 and hasUntimestampedEntry then
        return "FRESH", {
            status = "FRESH",
            itemCount = totalItems,
            pcfItems = pcfItems,
            orderBookItems = obItems,
            lastScanTimestamp = now,
            ageSeconds = 0,
            ageText = "0m",
        }
    end

    local ageSeconds = math.max(0, now - bestTs)
    local ageText = LL.FormatAgeShort(ageSeconds)
    local status = (ageSeconds > threshold) and "STALE" or "FRESH"

    return status, {
        status = status,
        itemCount = totalItems,
        pcfItems = pcfItems,
        orderBookItems = obItems,
        lastScanTimestamp = bestTs,
        ageSeconds = ageSeconds,
        ageText = ageText,
    }
end

function LL.LoadConfig(customDB)
    if type(customDB) == "table" then
        LevelingLad_DB = customDB
    else
        LevelingLad_DB = (type(_G.LevelingLad_DB) == "table" and _G.LevelingLad_DB) or {}
    end
    _G.LevelingLad_DB = LevelingLad_DB

    ApplyDefaults(LevelingLad_DB, defaultConfig)
    return LevelingLad_DB
end
