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
    version = 5,
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
        showSideWindow = false,              -- Closed by default at AH; open via top-left AH button, Minimap, or /ll
        priceSource = "AUTO",                -- "AUTO" (freshest of PCF/Auctionator), "PCF", or "AUCTIONATOR"
        minimap = { hide = false, minimapPos = 195 }, -- LibDBIcon-1.0 / OneForAll compatible minimap button state
        snoozeDurationSeconds = 86400,       -- Default manual snooze duration (24 hours)
        autoScanProfession = true,           -- Sync active TradeSkill window automatically on user-initiated actions
        onboardingDismissed = false,         -- Show welcome/AH-scan popup until dismissed
        staleDataThresholdSeconds = 86400,   -- Warn when cached AH data is older than 24 hours
    },
    charRecipes = {},        -- [charKey] = { [recipeKey] = recipeTable }
    charSkills = {},         -- [charKey] = { [skillLine] = { name, rank, maxRank, skillLine } }
    charProfScans = {},      -- [charKey] = { [skillLine] = { scannedAt, scannedRank, recipeCount, needsRescan } }
    trainerRecipes = {},     -- [skillLine] = { [nameLower] = { name, minSkill, trainerCost, outputItemId } }
    vendorBuyPrices = {},    -- [itemId] = copperPrice (dynamically updated from MERCHANT_SHOW)
    itemCache = {},          -- [itemId] = { name, link, quality, itemLevel, classID, subClassID, invType, texture, vendorSell }
    orderBookCache = {},     -- [itemId] = { timestamp = 0, listings = { { unitPrice, quantity }, ... }, unavailable = false }
    lastTopPlays = {},       -- Cached Top 5 immediate leveling plays
    lastRoadmap = nil,       -- Cached multi-step milestone roadmap
    activePlay = nil,        -- Currently tracked play in DetailWindow
    purchasedInMail = {},    -- [charKey] = { [itemId] = { count, spentCopper, updatedAt, lastBagCount } }
    snoozedPlays = {},       -- [snoozeKey] = { key, recipeId, outputItemId, itemName, itemLink, profession, skillLine, snoozedAt, expiresAt, reason }
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

-- Clears a stale activePlay when the user changes their target skill goal
-- (prevents old e.g. target=260 alerts from firing after setting a new goal like 265).
function LL.SyncActivePlayWithGoal(explicitNewGoal)
    local newGoal = tonumber(explicitNewGoal)
    if type(LevelingLad_DB) == "table" and type(LevelingLad_DB.activePlay) == "table" then
        local ap = LevelingLad_DB.activePlay
        if not newGoal then
            local rank, maxRank = 1, 300
            if LL.RecipeScanner and LL.RecipeScanner.GetProfessionSkill then
                local r, m = LL.RecipeScanner.GetProfessionSkill(ap.skillLine or ap.profession)
                rank = r or ap.liveSkill or ap.startSkill or 1
                maxRank = m or 300
            end
            newGoal = LL.GetTargetSkill(rank, maxRank)
        end
        local detailShown = LL.DetailWindow and LL.DetailWindow.frame
            and (not LL.DetailWindow.frame.IsShown or LL.DetailWindow.frame:IsShown())
        local trackedGoal = ap.goalTargetSkill or ap.requestedTargetSkill or ap.reachedSkill or ap.targetSkill
        if not detailShown or trackedGoal ~= newGoal then
            LevelingLad_DB.activePlay = nil
        end
    end
    if LL.DetailWindow and LL.DetailWindow.ClearStalePlay then
        LL.DetailWindow.ClearStalePlay(newGoal)
    end
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

function LL.GetPriceSourceMode()
    local raw = LevelingLad_DB and LevelingLad_DB.settings and LevelingLad_DB.settings.priceSource
    if type(raw) == "string" then
        local upper = raw:upper()
        if upper == "PCF" or upper == "AUCTIONATOR" or upper == "AUTO" then
            return upper
        end
    end
    return "AUTO"
end

-- ============================================================================
-- Manual Play Snoozing (hides snoozed recipes from Top 5; Milestone Path keeps full catalog)
-- ============================================================================

function LL.GetSnoozeKey(playOrRecipe)
    if type(playOrRecipe) == "string" and playOrRecipe ~= "" then
        return playOrRecipe
    end
    if type(playOrRecipe) == "number" and playOrRecipe > 0 then
        return "RECIPE:" .. tostring(math.floor(playOrRecipe))
    end
    if type(playOrRecipe) ~= "table" then
        return nil
    end

    local rId = playOrRecipe.recipeId or (playOrRecipe.recipe and playOrRecipe.recipe.recipeId)
    if type(rId) == "number" and rId > 0 then
        return "RECIPE:" .. tostring(math.floor(rId))
    end

    local outId = playOrRecipe.outputItemId or (playOrRecipe.recipe and playOrRecipe.recipe.outputItemId)
    if type(outId) == "number" and outId > 0 then
        return "ITEM:" .. tostring(math.floor(outId))
    end

    local rName = playOrRecipe.recipeName or playOrRecipe.name or (playOrRecipe.recipe and playOrRecipe.recipe.name)
    local sLine = playOrRecipe.skillLine or (playOrRecipe.recipe and playOrRecipe.recipe.skillLine) or 0
    if type(rName) == "string" and rName ~= "" then
        return string.format("NAME:%s:%s", tostring(sLine), rName:lower())
    end
    return nil
end

function LL.PruneExpiredSnoozes(nowOverride)
    if not LevelingLad_DB or type(LevelingLad_DB.snoozedPlays) ~= "table" then
        return 0
    end
    local now = (type(nowOverride) == "number") and nowOverride or ((_G.time and _G.time()) or 0)
    local pruned = 0
    for key, entry in pairs(LevelingLad_DB.snoozedPlays) do
        if type(entry) ~= "table" then
            LevelingLad_DB.snoozedPlays[key] = nil
            pruned = pruned + 1
        elseif type(entry.expiresAt) == "number" and entry.expiresAt > 0 and now >= entry.expiresAt then
            LevelingLad_DB.snoozedPlays[key] = nil
            pruned = pruned + 1
        end
    end
    return pruned
end

function LL.IsPlaySnoozed(playOrRecipe, nowOverride)
    local snoozed = LevelingLad_DB and LevelingLad_DB.snoozedPlays
    if type(snoozed) ~= "table" or next(snoozed) == nil then
        return false, nil
    end
    local key = LL.GetSnoozeKey(playOrRecipe)
    local entry = key and snoozed[key] or nil
    if not entry and type(playOrRecipe) == "table" then
        local outId = playOrRecipe.outputItemId or (playOrRecipe.recipe and playOrRecipe.recipe.outputItemId)
        if type(outId) == "number" and outId > 0 then
            entry = snoozed["ITEM:" .. tostring(math.floor(outId))]
        end
    end
    if type(entry) ~= "table" then
        return false, nil
    end
    local now = (type(nowOverride) == "number") and nowOverride or ((_G.time and _G.time()) or 0)
    if type(entry.expiresAt) == "number" and entry.expiresAt > 0 and now >= entry.expiresAt then
        snoozed[entry.key or key] = nil
        return false, nil
    end
    return true, entry
end

-- Snoozes a leveling play/recipe for durationSeconds (nil -> default 24h; 0 -> permanent).
function LL.SnoozePlay(playOrRecipe, durationSeconds, reason)
    local key = LL.GetSnoozeKey(playOrRecipe)
    if not key then
        return nil
    end
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.snoozedPlays = LevelingLad_DB.snoozedPlays or {}

    local now = (_G.time and _G.time()) or 0
    local defaultDur = (LevelingLad_DB.settings and tonumber(LevelingLad_DB.settings.snoozeDurationSeconds)) or 86400
    local dur = (durationSeconds == nil) and defaultDur or math.max(0, math.floor(tonumber(durationSeconds) or 0))
    local expiresAt = (dur > 0) and (now + dur) or 0

    local rId = (type(playOrRecipe) == "table") and (playOrRecipe.recipeId or (playOrRecipe.recipe and playOrRecipe.recipe.recipeId)) or nil
    local outId = (type(playOrRecipe) == "table") and (playOrRecipe.outputItemId or (playOrRecipe.recipe and playOrRecipe.recipe.outputItemId)) or nil
    local itemName = (type(playOrRecipe) == "table") and (playOrRecipe.recipeName or playOrRecipe.name or (playOrRecipe.recipe and playOrRecipe.recipe.name)) or nil
    local itemLink = (type(playOrRecipe) == "table") and (playOrRecipe.outputLink or playOrRecipe.itemLink) or nil
    local profession = (type(playOrRecipe) == "table") and (playOrRecipe.profession or (playOrRecipe.recipe and playOrRecipe.recipe.profession)) or nil
    local skillLine = (type(playOrRecipe) == "table") and (playOrRecipe.skillLine or (playOrRecipe.recipe and playOrRecipe.recipe.skillLine)) or nil

    if not itemName and outId and LL.VendorDatabase and LL.VendorDatabase.GetItemMetadata then
        local meta = LL.VendorDatabase.GetItemMetadata(outId, itemLink, true)
        itemName = meta and meta.name
    end

    local entry = {
        key = key,
        recipeId = rId,
        outputItemId = outId,
        itemId = outId,
        itemName = itemName or key,
        itemLink = itemLink,
        profession = profession,
        skillLine = skillLine,
        snoozedAt = now,
        expiresAt = expiresAt,
        durationSeconds = dur,
        reason = reason or ((dur == 0) and "permanent" or "manual"),
    }
    LevelingLad_DB.snoozedPlays[key] = entry
    return entry
end

function LL.UnsnoozePlay(keyOrQuery)
    if not LevelingLad_DB or type(LevelingLad_DB.snoozedPlays) ~= "table" or keyOrQuery == nil then
        return false, nil
    end
    if type(keyOrQuery) == "number" then
        local n = math.floor(keyOrQuery)
        local k1 = "RECIPE:" .. tostring(n)
        local k2 = "ITEM:" .. tostring(n)
        if LevelingLad_DB.snoozedPlays[k1] then
            local removed = LevelingLad_DB.snoozedPlays[k1]
            LevelingLad_DB.snoozedPlays[k1] = nil
            return true, removed
        elseif LevelingLad_DB.snoozedPlays[k2] then
            local removed = LevelingLad_DB.snoozedPlays[k2]
            LevelingLad_DB.snoozedPlays[k2] = nil
            return true, removed
        end
        for k, entry in pairs(LevelingLad_DB.snoozedPlays) do
            if type(entry) == "table" and (entry.recipeId == n or entry.outputItemId == n) then
                LevelingLad_DB.snoozedPlays[k] = nil
                return true, entry
            end
        end
        return false, nil
    end
    if type(keyOrQuery) == "string" then
        if LevelingLad_DB.snoozedPlays[keyOrQuery] then
            local removed = LevelingLad_DB.snoozedPlays[keyOrQuery]
            LevelingLad_DB.snoozedPlays[keyOrQuery] = nil
            return true, removed
        end
        local asNum = tonumber(keyOrQuery)
        if asNum then
            local okNum, remNum = LL.UnsnoozePlay(asNum)
            if okNum then return true, remNum end
        end
        local needle = keyOrQuery:lower():match("^%s*(.-)%s*$") or ""
        if needle ~= "" then
            for k, entry in pairs(LevelingLad_DB.snoozedPlays) do
                local name = (type(entry) == "table" and type(entry.itemName) == "string" and entry.itemName:lower()) or ""
                if name ~= "" and name:find(needle, 1, true) then
                    LevelingLad_DB.snoozedPlays[k] = nil
                    return true, entry
                end
            end
        end
    end
    return false, nil
end

function LL.ClearAllSnoozedPlays()
    if not LevelingLad_DB or type(LevelingLad_DB.snoozedPlays) ~= "table" then
        return 0
    end
    local count = 0
    for k in pairs(LevelingLad_DB.snoozedPlays) do
        LevelingLad_DB.snoozedPlays[k] = nil
        count = count + 1
    end
    return count
end

function LL.GetActiveSnoozedPlays(nowOverride)
    local now = (type(nowOverride) == "number") and nowOverride or ((_G.time and _G.time()) or 0)
    LL.PruneExpiredSnoozes(now)
    local list = {}
    if not LevelingLad_DB or type(LevelingLad_DB.snoozedPlays) ~= "table" then
        return list
    end
    for key, entry in pairs(LevelingLad_DB.snoozedPlays) do
        if type(entry) == "table" then
            local isPerm = (not entry.expiresAt or entry.expiresAt <= 0)
            local remSec = isPerm and nil or math.max(0, entry.expiresAt - now)
            local remText = isPerm and "Permanent" or LL.FormatAgeShort(remSec)
            table.insert(list, {
                key = key,
                recipeId = entry.recipeId,
                outputItemId = entry.outputItemId,
                itemId = entry.outputItemId,
                itemName = entry.itemName or key,
                itemLink = entry.itemLink,
                profession = entry.profession,
                skillLine = entry.skillLine,
                snoozedAt = entry.snoozedAt or 0,
                expiresAt = entry.expiresAt or 0,
                reason = entry.reason or (isPerm and "permanent" or "manual"),
                isPermanent = isPerm,
                remainingSeconds = remSec,
                remainingText = remText,
            })
        end
    end
    table.sort(list, function(a, b)
        if a.snoozedAt ~= b.snoozedAt then
            return a.snoozedAt > b.snoozedAt
        end
        return tostring(a.itemName) < tostring(b.itemName)
    end)
    return list
end

-- ============================================================================
-- Memoized Auction House Data Status (PCF + OrderBook + Auctionator)
-- ============================================================================

local ahStatusCache = nil

function LL.InvalidateAHStatusCache()
    ahStatusCache = nil
end

-- Evaluates whether Auction House price data is available and fresh.
-- Respects LevelingLad_DB.settings.priceSource ("AUTO" | "PCF" | "AUCTIONATOR") and memoizes counts.
-- Returns: status ("NO_DATA" | "STALE" | "FRESH"), detailsTable
function LL.GetAHDataStatus()
    local now = (_G.time and _G.time()) or 0
    local threshold = (LevelingLad_DB and LevelingLad_DB.settings and tonumber(LevelingLad_DB.settings.staleDataThresholdSeconds)) or 86400
    local mode = LL.GetPriceSourceMode()

    local pcfPrices = (mode ~= "AUCTIONATOR" and _G.PCF_DB and type(_G.PCF_DB.prices) == "table") and _G.PCF_DB.prices or nil
    local pcfEmpty = (not pcfPrices) or (next(pcfPrices) == nil)
    local lastScanTs = 0
    if mode ~= "AUCTIONATOR" and _G.PCF_DB then
        local fullTs = tonumber(_G.PCF_DB.lastFullScan) or 0
        local repTs = tonumber(_G.PCF_DB.lastReplicateScan) or 0
        lastScanTs = math.max(fullTs, repTs)
    end

    local obCache = (LevelingLad_DB and type(LevelingLad_DB.orderBookCache) == "table") and LevelingLad_DB.orderBookCache or nil
    local obEmpty = (not obCache) or (next(obCache) == nil)
    local obRev = (LL.AHVerifier and LL.AHVerifier.GetOrderBookRevision and LL.AHVerifier.GetOrderBookRevision()) or 0

    local atrPriceTable = (mode ~= "PCF" and LL.AuctionatorSource and LL.AuctionatorSource.GetRealmPriceTable and LL.AuctionatorSource.GetRealmPriceTable()) or nil
    local atrEmpty = (not atrPriceTable) or (next(atrPriceTable) == nil)
    local atrScanTs = (mode ~= "PCF" and LL.AuctionatorSource and LL.AuctionatorSource.GetLastScanTimestamp and LL.AuctionatorSource.GetLastScanTimestamp()) or 0
    local atrRev = (LL.AuctionatorSource and LL.AuctionatorSource.GetCacheRevision and LL.AuctionatorSource.GetCacheRevision()) or 0

    if ahStatusCache
        and math.abs(now - ahStatusCache.computedAt) < 2
        and ahStatusCache.mode == mode
        and ahStatusCache.threshold == threshold
        and ahStatusCache.pcfPrices == pcfPrices
        and ahStatusCache.pcfEmpty == pcfEmpty
        and ahStatusCache.lastScanTs == lastScanTs
        and ahStatusCache.obCache == obCache
        and ahStatusCache.obEmpty == obEmpty
        and ahStatusCache.obRev == obRev
        and ahStatusCache.atrPriceTable == atrPriceTable
        and ahStatusCache.atrEmpty == atrEmpty
        and ahStatusCache.atrScanTs == atrScanTs
        and ahStatusCache.atrRev == atrRev then
        return ahStatusCache.status, ahStatusCache.info
    end

    local function CacheAndReturn(status, info)
        ahStatusCache = {
            status = status,
            info = info,
            computedAt = now,
            mode = mode,
            threshold = threshold,
            pcfPrices = pcfPrices,
            pcfEmpty = pcfEmpty,
            lastScanTs = lastScanTs,
            obCache = obCache,
            obEmpty = obEmpty,
            obRev = obRev,
            atrPriceTable = atrPriceTable,
            atrEmpty = atrEmpty,
            atrScanTs = atrScanTs,
            atrRev = atrRev,
        }
        return status, info
    end

    local pcfItems = 0
    local newestEntryTs = 0
    local hasUntimestampedPCF = false

    if pcfPrices and not pcfEmpty then
        for itemId, entry in pairs(pcfPrices) do
            if type(itemId) == "number" and itemId > 0 and type(entry) == "table" and entry.minBuyout and entry.minBuyout > 0 then
                pcfItems = pcfItems + 1
                local ts = tonumber(entry.lastUpdated) or 0
                if ts > newestEntryTs then
                    newestEntryTs = ts
                elseif ts <= 0 then
                    hasUntimestampedPCF = true
                end
            end
        end
    end

    local obItems = 0
    local newestOBTs = 0
    if obCache and not obEmpty then
        for itemId, ob in pairs(obCache) do
            if type(itemId) == "number" and itemId > 0 and type(ob) == "table" and not ob.unavailable and type(ob.listings) == "table" and #ob.listings > 0 then
                obItems = obItems + 1
                local ts = tonumber(ob.timestamp) or 0
                if ts > newestOBTs then
                    newestOBTs = ts
                end
            end
        end
    end

    local auctionatorItems = 0
    local auctionatorTs = 0
    local hasUntimestampedAtr = false
    if mode ~= "PCF" and LL.AuctionatorSource and LL.AuctionatorSource.GetStatus then
        local atrStatus = LL.AuctionatorSource.GetStatus()
        if atrStatus then
            auctionatorItems = atrStatus.itemCount or 0
            auctionatorTs = atrStatus.lastScanTimestamp or 0
            hasUntimestampedAtr = (atrStatus.hasUntimestamped == true)
        end
    end

    local effectivePCFTs = (pcfItems > 0) and ((lastScanTs > 0) and lastScanTs or newestEntryTs) or 0
    local effectiveAtrTs = (auctionatorItems > 0) and auctionatorTs or 0

    local totalItems = math.max(pcfItems, obItems, auctionatorItems)
    local bestTs = math.max(effectivePCFTs, newestOBTs, effectiveAtrTs)
    local hasUntimestampedEntry = hasUntimestampedPCF or hasUntimestampedAtr

    local activeSource = "None"
    if totalItems > 0 then
        if mode == "AUCTIONATOR" then
            activeSource = (auctionatorItems > 0) and "Auctionator" or ((obItems > 0) and "Live AH" or "None")
        elseif mode == "PCF" then
            activeSource = (pcfItems > 0) and "PCF" or ((obItems > 0) and "Live AH" or "None")
        else
            if auctionatorItems > 0 and effectiveAtrTs >= effectivePCFTs and (effectiveAtrTs > 0 or pcfItems == 0) then
                activeSource = "Auctionator"
            elseif pcfItems > 0 then
                activeSource = "PCF"
            elseif auctionatorItems > 0 then
                activeSource = "Auctionator"
            elseif obItems > 0 then
                activeSource = "Live AH"
            end
        end
    end

    if totalItems <= 0 then
        return CacheAndReturn("NO_DATA", {
            status = "NO_DATA",
            itemCount = 0,
            pcfItems = 0,
            orderBookItems = 0,
            auctionatorItems = 0,
            activeSource = "None",
            priceSourceMode = mode,
            lastScanTimestamp = 0,
            ageSeconds = nil,
            ageText = "never",
        })
    end

    if bestTs <= 0 and hasUntimestampedEntry then
        return CacheAndReturn("FRESH", {
            status = "FRESH",
            itemCount = totalItems,
            pcfItems = pcfItems,
            orderBookItems = obItems,
            auctionatorItems = auctionatorItems,
            activeSource = activeSource,
            priceSourceMode = mode,
            lastScanTimestamp = now,
            ageSeconds = 0,
            ageText = "0m",
        })
    end

    local ageSeconds = math.max(0, now - bestTs)
    local ageText = LL.FormatAgeShort(ageSeconds)
    local status = (ageSeconds > threshold) and "STALE" or "FRESH"

    return CacheAndReturn(status, {
        status = status,
        itemCount = totalItems,
        pcfItems = pcfItems,
        orderBookItems = obItems,
        auctionatorItems = auctionatorItems,
        activeSource = activeSource,
        priceSourceMode = mode,
        lastScanTimestamp = bestTs,
        ageSeconds = ageSeconds,
        ageText = ageText,
    })
end

function LL.LoadConfig(customDB)
    LL.InvalidateAHStatusCache()
    if LL.RecipeScanner and LL.RecipeScanner.InvalidateCache then
        LL.RecipeScanner.InvalidateCache()
    end
    if LL.AHVerifier and LL.AHVerifier.InvalidateEvaluatedPool then
        LL.AHVerifier.InvalidateEvaluatedPool()
    end

    if type(customDB) == "table" then
        LevelingLad_DB = customDB
    else
        LevelingLad_DB = (type(_G.LevelingLad_DB) == "table" and _G.LevelingLad_DB) or {}
    end
    _G.LevelingLad_DB = LevelingLad_DB

    local prevVersion = tonumber(LevelingLad_DB.version) or 0
    ApplyDefaults(LevelingLad_DB, defaultConfig)

    -- v4 migration: purge unlearned C_TradeSkillUI recipes (e.g. phase-locked / drop / 300-skill recipes
    -- like Elemental Sharpening Stone & Ebon Shiv that lacked minSkill) and clear stale activePlay targets.
    if prevVersion > 0 and prevVersion < 4 then
        LevelingLad_DB.charRecipes = {}
        LevelingLad_DB.lastTopPlays = {}
        LevelingLad_DB.lastRoadmap = nil
        LevelingLad_DB.activePlay = nil
        LevelingLad_DB.version = 4
    end

    -- v5 migration: switch existing installs to closed-by-default at the Auction House
    -- (can be re-enabled anytime in Options or /ll autoopen).
    if prevVersion > 0 and prevVersion < 5 then
        if LevelingLad_DB.settings then
            LevelingLad_DB.settings.showSideWindow = false
        end
        LevelingLad_DB.version = 5
    end

    return LevelingLad_DB
end
