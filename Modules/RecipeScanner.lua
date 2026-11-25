local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.RecipeScanner = {}

local pendingOpenRecipe = nil
local skillupCallbacks = {}

local DIFFICULTY_NORMALIZE = {
    optimal = "ORANGE",
    orange  = "ORANGE",
    medium  = "YELLOW",
    yellow  = "YELLOW",
    easy    = "GREEN",
    green   = "GREEN",
    trivial = "GRAY",
    gray    = "GRAY",
    grey    = "GRAY",
}

local function MapDifficultyEnum(val)
    if type(val) ~= "number" then return nil end
    local enumTbl = _G.Enum and (
        _G.Enum.TradeskillRelativeDifficulty
        or _G.Enum.TradeSkillRelativeDifficulty
        or _G.Enum.ProfessionDifficulty
    )
    if type(enumTbl) == "table" then
        if enumTbl.Optimal ~= nil and val == enumTbl.Optimal then return "ORANGE" end
        if enumTbl.Medium  ~= nil and val == enumTbl.Medium  then return "YELLOW" end
        if enumTbl.Easy    ~= nil and val == enumTbl.Easy    then return "GREEN" end
        if enumTbl.Trivial ~= nil and val == enumTbl.Trivial then return "GRAY" end
    end
    -- Standard Blizzard Enum.TradeskillRelativeDifficulty numeric mapping:
    -- 0 = Optimal (Orange), 1 = Medium (Yellow), 2 = Easy (Green), 3 = Trivial (Gray)
    if val == 0 then return "ORANGE"
    elseif val == 1 then return "YELLOW"
    elseif val == 2 then return "GREEN"
    elseif val == 3 then return "GRAY"
    end
    return nil
end

-- Decodes Blizzard's recipe difficulty from modern C_TradeSkillUI (relativeDifficulty enum / numSkillUps)
-- or legacy TradeSkillFrame (difficulty string). Never fabricates ORANGE when difficulty is unknown.
function LL.RecipeScanner.NormalizeLiveDifficulty(rawDiff, relativeDiff, numSkillUps)
    if type(relativeDiff) == "number" then
        local mapped = MapDifficultyEnum(relativeDiff)
        if mapped then return mapped end
    elseif type(relativeDiff) == "string" and relativeDiff ~= "" then
        local mapped = DIFFICULTY_NORMALIZE[relativeDiff:lower()]
        if mapped then return mapped end
    end

    if type(rawDiff) == "string" and rawDiff ~= "" then
        local mapped = DIFFICULTY_NORMALIZE[rawDiff:lower()]
        if mapped then return mapped end
    elseif type(rawDiff) == "number" then
        local mapped = MapDifficultyEnum(rawDiff)
        if mapped then return mapped end
    end

    if type(numSkillUps) == "number" and numSkillUps <= 0 then
        return "GRAY"
    end

    return nil
end

local function BuildSkillUpPattern()
    local globalFmt = _G.ERR_SKILL_UP_SI
    if type(globalFmt) == "string" and globalFmt ~= "" then
        local esc = globalFmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
        esc = esc:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
        return "^" .. esc .. "$"
    end
    return "^Your skill in (.+) has increased to (%d+)%.?$"
end

function LL.RecipeScanner.RegisterSkillupCallback(cb)
    if type(cb) == "function" then
        table.insert(skillupCallbacks, cb)
    end
end

local function EnsureCharTables()
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.charRecipes = LevelingLad_DB.charRecipes or {}
    LevelingLad_DB.charSkills = LevelingLad_DB.charSkills or {}
    local charKey = LL.GetCharacterKey()
    if type(LevelingLad_DB.charRecipes[charKey]) ~= "table" then
        LevelingLad_DB.charRecipes[charKey] = {}
    end
    if type(LevelingLad_DB.charSkills[charKey]) ~= "table" then
        LevelingLad_DB.charSkills[charKey] = {}
    end
    return LevelingLad_DB.charRecipes[charKey], LevelingLad_DB.charSkills[charKey], charKey
end

local function RecordSkillRank(skillLineOrName, rank, maxRank, fromChatSkillUp)
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName)
    if not skillLine then return nil end
    local profName = LL.RecipeDatabase.GetProfessionName(skillLine)
    local _, charSkills = EnsureCharTables()
    local existing = charSkills[skillLine]
    local now = (_G.time and _G.time()) or 0
    local cleanRank = math.max(1, math.floor(tonumber(rank) or (existing and existing.rank) or 1))
    local cleanMax = math.max(cleanRank, math.floor(tonumber(maxRank) or (existing and existing.maxRank) or 75))
    local chatTs = fromChatSkillUp and now or nil

    if not fromChatSkillUp and existing and existing.chatSkillUpAt and (now - existing.chatSkillUpAt) <= 10 and (existing.rank or 0) > cleanRank then
        cleanRank = existing.rank
        cleanMax = math.max(cleanMax, existing.maxRank or cleanRank)
        chatTs = existing.chatSkillUpAt
    end

    charSkills[skillLine] = {
        skillLine = skillLine,
        name = profName,
        rank = cleanRank,
        maxRank = cleanMax,
        updatedAt = now,
        chatSkillUpAt = chatTs,
    }
    return charSkills[skillLine]
end

local function ReconcileThresholdsWithLiveDifficulty(recipe, liveDiff, currentRank)
    if not liveDiff or type(currentRank) ~= "number" or currentRank <= 0 then
        return
    end
    recipe.liveDifficulty = liveDiff
    recipe.scannedAtRank = currentRank

    if liveDiff == "GRAY" then
        -- Blizzard confirms this recipe is Trivial/Gray right now -> strictly enforce gray <= currentRank
        recipe.gray = math.min(recipe.gray or currentRank, currentRank)
        recipe.green = math.min(recipe.green or math.max(1, recipe.gray - 15), recipe.gray)
        recipe.yellow = math.min(recipe.yellow or math.max(1, recipe.green - 15), recipe.green)
        recipe.orange = math.min(recipe.orange or 1, recipe.yellow)
    elseif liveDiff == "GREEN" then
        -- Blizzard confirms Green right now -> green <= currentRank < gray
        recipe.green = math.min(recipe.green or currentRank, currentRank)
        if not recipe.gray or recipe.gray <= currentRank then
            recipe.gray = currentRank + 10
        end
        recipe.yellow = math.min(recipe.yellow or math.max(1, recipe.green - 15), recipe.green)
        recipe.orange = math.min(recipe.orange or 1, recipe.yellow)
    elseif liveDiff == "YELLOW" then
        -- Blizzard confirms Yellow right now -> yellow <= currentRank < green <= gray
        recipe.yellow = math.min(recipe.yellow or currentRank, currentRank)
        if not recipe.green or recipe.green <= currentRank then
            recipe.green = currentRank + 10
        end
        if not recipe.gray or recipe.gray <= recipe.green then
            recipe.gray = recipe.green + 10
        end
        recipe.orange = math.min(recipe.orange or 1, recipe.yellow)
    elseif liveDiff == "ORANGE" then
        -- Blizzard confirms Orange right now -> orange <= currentRank < yellow
        recipe.orange = math.min(recipe.orange or currentRank, currentRank)
        if not recipe.yellow or recipe.yellow <= currentRank then
            recipe.yellow = currentRank + 10
        end
        if not recipe.green or recipe.green < recipe.yellow then
            recipe.green = recipe.yellow + 10
        end
        if not recipe.gray or recipe.gray < recipe.green then
            recipe.gray = recipe.green + 10
        end
    end
end

local function MergeStaticThresholds(recipe)
    if type(recipe) ~= "table" then return recipe end
    local static = nil
    if recipe.recipeId then
        static = LL.RecipeDatabase.GetRecipeById(recipe.recipeId)
    end
    if not static and recipe.outputItemId then
        static = LL.RecipeDatabase.GetRecipeByOutputItem(recipe.outputItemId, recipe.skillLine or recipe.profession)
    end
    if not static and recipe.name then
        static = LL.RecipeDatabase.GetRecipeByName(recipe.name, recipe.skillLine or recipe.profession)
    end

    local currentRank = tonumber(recipe.scannedAtRank) or LL.RecipeScanner.GetProfessionSkill(recipe.skillLine or recipe.profession) or 1
    local minReq = math.max(1, math.floor(tonumber(recipe.minSkill) or 1))
    local anchorRank = math.max(minReq, currentRank)
    local normLive = LL.RecipeScanner.NormalizeLiveDifficulty(recipe.liveDifficulty, recipe.relativeDifficulty, recipe.numSkillUps)

    if static then
        recipe.recipeId = recipe.recipeId or static.recipeId
        recipe.skillLine = recipe.skillLine or static.skillLine
        recipe.profession = recipe.profession or static.profession
        recipe.minSkill = recipe.minSkill or static.minSkill
        recipe.orange = recipe.orange or static.orange
        recipe.yellow = recipe.yellow or static.yellow
        recipe.green = recipe.green or static.green
        recipe.gray = recipe.gray or static.gray
        recipe.source = recipe.source or static.source or "Trainer"
        recipe.isEnchant = (recipe.isEnchant == true) or (static.isEnchant == true)

        -- Only reconcile against live difficulty when player has reached the recipe's minSkill
        if normLive and currentRank >= (recipe.minSkill or 1) then
            ReconcileThresholdsWithLiveDifficulty(recipe, normLive, currentRank)
        end
    else
        -- Unknown recipe not in static catalog: NEVER fabricate ORANGE when live difficulty is nil/unknown!
        local diff = normLive or "GRAY"
        recipe.liveDifficulty = diff
        recipe.scannedAtRank = currentRank
        if recipe.learned == false and minReq > currentRank then
            -- Future trainer recipe (minSkill > currentRank): anchor thresholds at minReq, never at currentRank!
            recipe.orange = recipe.orange or minReq
            recipe.yellow = recipe.yellow or (minReq + 15)
            recipe.green = recipe.green or (minReq + 25)
            recipe.gray = recipe.gray or (minReq + 35)
            recipe.minSkill = minReq
        elseif diff == "GRAY" then
            recipe.orange = recipe.orange or 1
            recipe.yellow = recipe.yellow or math.max(1, anchorRank - 30)
            recipe.green = recipe.green or math.max(1, anchorRank - 15)
            recipe.gray = recipe.gray or anchorRank
        elseif diff == "GREEN" then
            recipe.orange = recipe.orange or 1
            recipe.yellow = recipe.yellow or math.max(1, anchorRank - 15)
            recipe.green = recipe.green or anchorRank
            recipe.gray = recipe.gray or (anchorRank + 10)
        elseif diff == "YELLOW" then
            recipe.orange = recipe.orange or 1
            recipe.yellow = recipe.yellow or anchorRank
            recipe.green = recipe.green or (anchorRank + 10)
            recipe.gray = recipe.gray or (anchorRank + 20)
        else
            recipe.orange = recipe.orange or anchorRank
            recipe.yellow = recipe.yellow or (anchorRank + 15)
            recipe.green = recipe.green or (anchorRank + 25)
            recipe.gray = recipe.gray or (anchorRank + 35)
        end
        recipe.minSkill = recipe.minSkill or recipe.orange or 1
        recipe.source = recipe.source or "Known"
    end
    return recipe
end

local function EnsureTrainerTable(skillLine)
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.trainerRecipes = LevelingLad_DB.trainerRecipes or {}
    if skillLine then
        if type(LevelingLad_DB.trainerRecipes[skillLine]) ~= "table" then
            LevelingLad_DB.trainerRecipes[skillLine] = {}
        end
        return LevelingLad_DB.trainerRecipes[skillLine]
    end
    return LevelingLad_DB.trainerRecipes
end

local function StripRecipePrefix(rawName)
    if type(rawName) ~= "string" then return "" end
    local clean = rawName:gsub("^%s*(.-)%s*$", "%1")
    clean = clean:gsub("^[Pp]lans:%s*", "")
        :gsub("^[Rr]ecipe:%s*", "")
        :gsub("^[Pp]attern:%s*", "")
        :gsub("^[Ss]chematic:%s*", "")
        :gsub("^[Ff]ormula:%s*", "")
        :gsub("^[Mm]anual:%s*", "")
    return clean
end

-- Scans an open WoW: Forever Profession Trainer window (TRAINER_SHOW / TRAINER_UPDATE).
-- Records ONLY genuinely trainer-taught recipes along with their exact server minSkill requirement!
function LL.RecipeScanner.ScanTrainerWindow()
    if not _G.GetNumTrainerServices or not _G.GetTrainerServiceInfo then
        return 0
    end
    local okNum, numServices = pcall(_G.GetNumTrainerServices)
    if not okNum or type(numServices) ~= "number" or numServices <= 0 then
        return 0
    end

    local recorded = 0
    local now = (_G.time and _G.time()) or 0

    for i = 1, numServices do
        local okInfo, sName, _, sType = pcall(_G.GetTrainerServiceInfo, i)
        if okInfo and type(sName) == "string" and sName ~= "" and sType ~= "header" then
            local skillName, reqRank = nil, nil
            if _G.GetTrainerServiceSkillReq then
                local okReq, sn, rk = pcall(_G.GetTrainerServiceSkillReq, i)
                if okReq then
                    skillName = sn
                    reqRank = tonumber(rk)
                end
            end

            local skillLine = skillName and LL.RecipeDatabase.ResolveSkillLineId(skillName) or nil
            if skillLine then
                local trainerTbl = EnsureTrainerTable(skillLine)
                local cleanName = StripRecipePrefix(sName)
                local key = cleanName:lower()
                if sType == "used" then
                    -- Already learned by player; remove from pending trainer list
                    trainerTbl[key] = nil
                elseif sType == "available" or sType == "unavailable" then
                    local cost = 0
                    if _G.GetTrainerServiceCost then
                        local okC, moneyCost = pcall(_G.GetTrainerServiceCost, i)
                        if okC and type(moneyCost) == "number" then
                            cost = math.max(0, math.floor(moneyCost))
                        end
                    end
                    local outId = nil
                    if _G.GetTrainerServiceItemLink then
                        local okL, link = pcall(_G.GetTrainerServiceItemLink, i)
                        if okL and type(link) == "string" then
                            outId = tonumber(link:match("item:(%d+)"))
                        end
                    end
                    local minSkill = math.max(1, math.floor(reqRank or 1))
                    trainerTbl[key] = {
                        name = cleanName,
                        skillLine = skillLine,
                        minSkill = minSkill,
                        trainerCost = cost,
                        outputItemId = outId,
                        serviceType = sType,
                        updatedAt = now,
                    }
                    recorded = recorded + 1
                end
            end
        end
    end

    if recorded > 0 then
        LL.RecipeScanner.ScanModernTradeSkillUI()
    end

    return recorded
end

local function SaveScannedRecipe(charRecipes, recipe)
    if type(recipe) ~= "table" or not recipe.name then return false end
    local normReagents = LL.RecipeDatabase.NormalizeReagents(recipe.reagents)
    if #normReagents == 0 then return false end

    local reagentMap = {}
    for _, r in ipairs(normReagents) do
        reagentMap[r.itemId] = r.count
    end
    recipe.reagents = reagentMap
    recipe.reagentList = normReagents
    if recipe.learned == nil then
        recipe.learned = true
    end
    recipe.needsTrainer = (recipe.learned == false)
    MergeStaticThresholds(recipe)

    local key = tostring(recipe.skillLine or 0) .. ":" .. tostring(recipe.recipeId or recipe.outputItemId or recipe.name)
    recipe.key = key
    recipe.lastScanned = (_G.time and _G.time()) or 0
    charRecipes[key] = recipe
    return true
end

function LL.RecipeScanner.GetCharacterProfessions()
    local skills = LL.RecipeDatabase.GetCharacterSkillRanks()
    local _, charSkills = EnsureCharTables()
    local now = (_G.time and _G.time()) or 0
    for skillLine, info in pairs(skills) do
        local prev = charSkills[skillLine]
        if prev and prev.chatSkillUpAt and (now - prev.chatSkillUpAt) <= 10 and (prev.rank or 0) > (info.rank or 0) then
            info.rank = prev.rank
            info.maxRank = math.max(info.maxRank or 75, prev.maxRank or prev.rank)
            info.chatSkillUpAt = prev.chatSkillUpAt
        end
        charSkills[skillLine] = info
    end
    local list = {}
    for _, info in pairs(skills) do
        table.insert(list, info)
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list, skills
end

function LL.RecipeScanner.GetProfessionSkill(skillLineOrName)
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName)
    local _, skills = LL.RecipeScanner.GetCharacterProfessions()
    if skillLine and skills[skillLine] then
        local rank = skills[skillLine].rank
        local maxRank = skills[skillLine].maxRank
        -- Guard against CHAT_MSG_SKILL arriving slightly ahead of GetProfessionInfo/SKILL_LINES_CHANGED
        local _, charSkills = EnsureCharTables()
        local cached = charSkills[skillLine]
        local now = (_G.time and _G.time()) or 0
        if cached and cached.chatSkillUpAt and (now - cached.chatSkillUpAt) <= 10 and (cached.rank or 0) > (rank or 0) then
            rank = cached.rank
            maxRank = math.max(maxRank or 75, cached.maxRank or rank)
        end
        return rank, maxRank, skills[skillLine].name, skillLine
    end
    return nil, nil, LL.RecipeDatabase.GetProfessionName(skillLineOrName), skillLine
end

function LL.RecipeScanner.GetActiveProfession()
    local settings = LevelingLad_DB and LevelingLad_DB.settings
    local list, skills = LL.RecipeScanner.GetCharacterProfessions()

    if settings and settings.selectedProfession then
        local selectedId = LL.RecipeDatabase.ResolveSkillLineId(settings.selectedProfession)
        if selectedId then
            if skills[selectedId] then
                return skills[selectedId]
            end
            return {
                skillLine = selectedId,
                name = LL.RecipeDatabase.GetProfessionName(selectedId),
                rank = 1,
                maxRank = 75,
            }
        end
    end

    if #list > 0 then
        return list[1]
    end

    return {
        skillLine = 164,
        name = "Blacksmithing",
        rank = 1,
        maxRank = 75,
    }
end

function LL.RecipeScanner.ScanLegacyTradeSkill()
    if not _G.GetNumTradeSkills or not _G.GetTradeSkillInfo then
        return 0
    end
    if _G.IsTradeSkillLinked then
        local okL, linked = pcall(_G.IsTradeSkillLinked)
        if okL and linked then return 0 end
    end
    if _G.IsTradeSkillGuild then
        local okG, guild = pcall(_G.IsTradeSkillGuild)
        if okG and guild then return 0 end
    end

    local okNum, numSkills = pcall(_G.GetNumTradeSkills)
    if not okNum or type(numSkills) ~= "number" or numSkills <= 0 then
        return 0
    end

    local lineName, rank, maxRank = "Blacksmithing", 1, 75
    if _G.GetTradeSkillLine then
        local okL, ln, rk, mrk = pcall(_G.GetTradeSkillLine)
        if okL and type(ln) == "string" and ln ~= "" and ln ~= "UNKNOWN" then
            lineName = ln
            rank = tonumber(rk) or 1
            maxRank = tonumber(mrk) or 75
        end
    end

    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(lineName)
    if skillLine then
        RecordSkillRank(skillLine, rank, maxRank)
    end
    local profName = LL.RecipeDatabase.GetProfessionName(skillLine) or lineName
    local charRecipes = EnsureCharTables()
    local scanned = 0

    for i = 1, numSkills do
        local okInfo, skillName, skillType = pcall(_G.GetTradeSkillInfo, i)
        if okInfo and skillName and skillType ~= "header" and skillType ~= "subheader" then
            local itemLink = _G.GetTradeSkillItemLink and _G.GetTradeSkillItemLink(i)
            local outputItemId = itemLink and tonumber(itemLink:match("item:(%d+)"))
            if outputItemId and outputItemId > 0 then
                LL.VendorDatabase.GetItemMetadata(outputItemId, itemLink)
            end

            local minMade, maxMade = 1, 1
            if _G.GetTradeSkillNumMade then
                local okM, mn, mx = pcall(_G.GetTradeSkillNumMade, i)
                if okM and mn and mn > 0 then
                    minMade = mn
                    maxMade = (mx and mx >= mn) and mx or mn
                end
            end

            local numReagents = (_G.GetTradeSkillNumReagents and _G.GetTradeSkillNumReagents(i)) or 0
            local reagents = {}
            for r = 1, numReagents do
                local rName, _, rCount = _G.GetTradeSkillReagentInfo(i, r)
                local rLink = _G.GetTradeSkillReagentItemLink and _G.GetTradeSkillReagentItemLink(i, r)
                local rItemId = rLink and tonumber(rLink:match("item:(%d+)"))
                if rItemId and rItemId > 0 and rCount and rCount > 0 then
                    LL.VendorDatabase.GetItemMetadata(rItemId, rLink)
                    table.insert(reagents, { itemId = rItemId, name = rName, count = rCount })
                end
            end

            if #reagents > 0 then
                local saved = SaveScannedRecipe(charRecipes, {
                    name = skillName,
                    profession = profName,
                    skillLine = skillLine,
                    tradeSkillIndex = i,
                    liveDifficulty = skillType,
                    scannedAtRank = rank,
                    outputItemId = outputItemId,
                    outputLink = itemLink,
                    outputQty = (minMade + maxMade) / 2,
                    reagents = reagents,
                })
                if saved then
                    scanned = scanned + 1
                end
            end
        end
    end

    return scanned
end

function LL.RecipeScanner.ScanModernTradeSkillUI()
    if not _G.C_TradeSkillUI or not _G.C_TradeSkillUI.GetAllRecipeIDs or not _G.C_TradeSkillUI.GetRecipeInfo then
        return 0
    end
    if _G.C_TradeSkillUI.IsTradeSkillLinked then
        local okL, linked = pcall(_G.C_TradeSkillUI.IsTradeSkillLinked)
        if okL and linked then return 0 end
    end
    if _G.C_TradeSkillUI.IsTradeSkillGuild then
        local okG, guild = pcall(_G.C_TradeSkillUI.IsTradeSkillGuild)
        if okG and guild then return 0 end
    end
    if _G.C_TradeSkillUI.IsNPCCrafting then
        local okN, npc = pcall(_G.C_TradeSkillUI.IsNPCCrafting)
        if okN and npc then return 0 end
    end
    if _G.C_TradeSkillUI.IsTradeSkillReady then
        local okR, ready = pcall(_G.C_TradeSkillUI.IsTradeSkillReady)
        if okR and not ready then return 0 end
    end

    local okIds, recipeIDs = pcall(_G.C_TradeSkillUI.GetAllRecipeIDs)
    if not okIds or type(recipeIDs) ~= "table" or #recipeIDs == 0 then
        return 0
    end

    local windowSkillLine, windowProfName, windowSkillRank, windowMaxRank = nil, nil, nil, nil
    if _G.C_TradeSkillUI.GetBaseProfessionInfo then
        local okP, pInfo = pcall(_G.C_TradeSkillUI.GetBaseProfessionInfo)
        if okP and type(pInfo) == "table" then
            local pid = (type(pInfo.parentProfessionID) == "number" and pInfo.parentProfessionID > 0) and pInfo.parentProfessionID or pInfo.professionID
            local pname = pInfo.parentProfessionName or pInfo.professionName
            windowSkillLine = LL.RecipeDatabase.ResolveSkillLineId(pid or pname)
            windowProfName = LL.RecipeDatabase.GetProfessionName(windowSkillLine or pname)
            if (pInfo.skillLevel or 0) > 0 then
                windowSkillRank = pInfo.skillLevel
                windowMaxRank = pInfo.maxSkillLevel
            end
        end
    end
    if _G.C_TradeSkillUI.GetChildProfessionInfo then
        local okC, cInfo = pcall(_G.C_TradeSkillUI.GetChildProfessionInfo)
        if okC and type(cInfo) == "table" then
            if not windowSkillLine then
                local pid = (type(cInfo.parentProfessionID) == "number" and cInfo.parentProfessionID > 0) and cInfo.parentProfessionID or cInfo.professionID
                local pname = cInfo.parentProfessionName or cInfo.professionName
                windowSkillLine = LL.RecipeDatabase.ResolveSkillLineId(pid or pname)
                windowProfName = LL.RecipeDatabase.GetProfessionName(windowSkillLine or pname)
            end
            if (cInfo.skillLevel or 0) > 0 then
                windowSkillRank = cInfo.skillLevel
                windowMaxRank = cInfo.maxSkillLevel or windowMaxRank
            end
        end
    end
    if windowSkillLine and (windowSkillRank or 0) > 0 then
        RecordSkillRank(windowSkillLine, windowSkillRank, windowMaxRank)
    end

    local charRecipes = EnsureCharTables()
    local scanned = 0

    -- Purge any unlearned charRecipes in this profession that are no longer verified via a Trainer scan
    if windowSkillLine then
        local winTrainerTbl = EnsureTrainerTable(windowSkillLine)
        for key, existing in pairs(charRecipes) do
            if type(existing) == "table" and existing.skillLine == windowSkillLine and existing.learned == false then
                local cleanKey = StripRecipePrefix(existing.name or ""):lower()
                if not winTrainerTbl[cleanKey] then
                    charRecipes[key] = nil
                end
            end
        end
    end

    for _, recipeID in ipairs(recipeIDs) do
        local okInfo, info = pcall(_G.C_TradeSkillUI.GetRecipeInfo, recipeID)
        if okInfo and type(info) == "table" and not info.disabled
            and not info.isRecraft and not info.isDummyRecipe
            and not info.isGatheringRecipe and not info.isSalvageRecipe then
            local isLearned = (info.learned == true)
            local normDiff = LL.RecipeScanner.NormalizeLiveDifficulty(info.difficulty, info.relativeDifficulty, info.numSkillUps)

            local rSkillLine = windowSkillLine
            local rProfName = windowProfName
            local rRank = windowSkillRank
            if _G.C_TradeSkillUI.GetProfessionInfoByRecipeID then
                local okPR, prInfo = pcall(_G.C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID)
                if okPR and type(prInfo) == "table" then
                    local pid = (type(prInfo.parentProfessionID) == "number" and prInfo.parentProfessionID > 0) and prInfo.parentProfessionID or prInfo.professionID
                    local resolved = LL.RecipeDatabase.ResolveSkillLineId(pid or prInfo.parentProfessionName or prInfo.professionName)
                    if resolved then
                        rSkillLine = resolved
                        rProfName = LL.RecipeDatabase.GetProfessionName(resolved)
                    end
                    if (prInfo.skillLevel or 0) > 0 then
                        rRank = prInfo.skillLevel
                    end
                end
            end

            local cleanKey = StripRecipePrefix(info.name or ""):lower()
            local trainerTbl = rSkillLine and EnsureTrainerTable(rSkillLine) or nil
            local trainerEntry = (not isLearned and trainerTbl) and trainerTbl[cleanKey] or nil
            if isLearned and trainerTbl and cleanKey ~= "" then
                trainerTbl[cleanKey] = nil
            end

            -- STRICT WoW: Forever rule:
            -- 1. Always store learned recipes (including GRAY so we know they're trivial).
            -- 2. NEVER accept arbitrary unlearned C_TradeSkillUI recipes (which include phase-locked,
            --    raid/world drops, rep recipes, and 300-skill recipes with no minSkill).
            --    ONLY include unlearned recipes explicitly verified at a WoW: Forever Profession Trainer!
            if isLearned or (trainerEntry and normDiff and normDiff ~= "GRAY") then
                local schematic = _G.C_TradeSkillUI.GetRecipeSchematic and _G.C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
                local outputItemId = (schematic and schematic.outputItemID) or info.itemID
                local reagents = {}
                if schematic and type(schematic.reagentSlotSchematics) == "table" then
                    for _, slot in ipairs(schematic.reagentSlotSchematics) do
                        local rItemId = slot.reagents and slot.reagents[1] and slot.reagents[1].itemID
                        local rCount = slot.quantityRequired or 1
                        if rItemId and rItemId > 0 and rCount > 0 then
                            local meta = LL.VendorDatabase.GetItemMetadata(rItemId)
                            table.insert(reagents, {
                                itemId = rItemId,
                                name = (meta and meta.name) or string.format("Item #%d", rItemId),
                                count = rCount,
                            })
                        end
                    end
                end

                if #reagents > 0 then
                    local minMade = (schematic and schematic.quantityMin) or 1
                    local maxMade = (schematic and schematic.quantityMax) or minMade
                    local trainerMinSkill = trainerEntry and trainerEntry.minSkill or nil
                    local sourceLabel = isLearned and "Known" or string.format("Trainer (%d)", trainerMinSkill or 1)

                    local saved = SaveScannedRecipe(charRecipes, {
                        recipeId = recipeID,
                        name = info.name or string.format("Recipe #%d", recipeID),
                        profession = rProfName or "Crafting",
                        skillLine = rSkillLine,
                        learned = isLearned,
                        needsTrainer = not isLearned,
                        verifiedTrainer = (trainerEntry ~= nil),
                        minSkill = trainerMinSkill,
                        trainerCost = trainerEntry and trainerEntry.trainerCost or nil,
                        source = sourceLabel,
                        liveDifficulty = normDiff,
                        relativeDifficulty = info.relativeDifficulty,
                        numSkillUps = info.numSkillUps,
                        scannedAtRank = rRank or LL.RecipeScanner.GetProfessionSkill(rSkillLine or rProfName) or 1,
                        outputItemId = (outputItemId and outputItemId > 0) and outputItemId or nil,
                        outputQty = (minMade + maxMade) / 2,
                        reagents = reagents,
                    })
                    if saved then
                        scanned = scanned + 1
                    end
                end
            end
        end
    end

    return scanned
end

function LL.RecipeScanner.ScanCurrentProfessionWindow()
    local count = LL.RecipeScanner.ScanModernTradeSkillUI()
    if count == 0 then
        count = LL.RecipeScanner.ScanLegacyTradeSkill()
    end
    return count
end

-- Returns known + trainer-available recipes for a profession.
-- Each entry has .learned (true/false) and .needsTrainer (true when unlearned Trainer/Vendor recipe).
function LL.RecipeScanner.GetRecipesForProfession(skillLineOrName, includeTrainer)
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName)
    if not skillLine then return {} end

    local settings = (LevelingLad_DB and LevelingLad_DB.settings) or {}
    if includeTrainer == nil then
        includeTrainer = (settings.includeTrainerRecipes ~= false)
    end

    local list = {}
    local seenById = {}
    local seenByName = {}

    -- 1. Character's scanned live WoW: Forever recipes (learned + trainer-verified unlearned)
    local charRecipes = EnsureCharTables()
    local trainerTbl = EnsureTrainerTable(skillLine)
    local liveRank = LL.RecipeScanner.GetProfessionSkill(skillLine)
    for _, rec in pairs(charRecipes) do
        if type(rec) == "table" and rec.skillLine == skillLine then
            local isLearned = (rec.learned ~= false)
            local cleanKey = StripRecipePrefix(rec.name or ""):lower()
            local trainerEntry = (not isLearned) and trainerTbl[cleanKey] or nil
            local isVerifiedTrainer = (not isLearned) and (rec.verifiedTrainer == true or trainerEntry ~= nil)
            if trainerEntry and trainerEntry.minSkill then
                rec.minSkill = trainerEntry.minSkill
                rec.source = string.format("Trainer (%d)", trainerEntry.minSkill)
            end

            if isLearned or (includeTrainer and isVerifiedTrainer) then
                -- Refresh live difficulty on-demand from C_TradeSkillUI when player meets minSkill
                local minReq = tonumber(rec.minSkill) or 1
                if type(rec.recipeId) == "number" and rec.recipeId > 0
                    and liveRank and liveRank >= minReq
                    and _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetRecipeInfo then
                    local okI, rInfo = pcall(_G.C_TradeSkillUI.GetRecipeInfo, rec.recipeId)
                    if okI and type(rInfo) == "table" then
                        local freshDiff = LL.RecipeScanner.NormalizeLiveDifficulty(rInfo.difficulty, rInfo.relativeDifficulty, rInfo.numSkillUps)
                        if freshDiff then
                            ReconcileThresholdsWithLiveDifficulty(rec, freshDiff, liveRank)
                        end
                    end
                end

                local idKey = rec.recipeId
                local nameKey = rec.name and rec.name:lower()
                if (not idKey or not seenById[idKey]) and (not nameKey or not seenByName[nameKey]) then
                    if idKey then seenById[idKey] = true end
                    if nameKey then seenByName[nameKey] = true end
                    rec.learned = isLearned
                    rec.needsTrainer = not isLearned
                    table.insert(list, rec)
                end
            end
        end
    end

    -- 2. Static catalog recipes (marked needsTrainer if not scanned as learned, or known if no scan yet)
    local hasScannedAny = (#list > 0)
    local catalog = LL.RecipeDatabase.GetRecipesForProfession(skillLine)
    for _, base in ipairs(catalog) do
        local idKey = base.recipeId
        local nameKey = base.name and base.name:lower()
        if (not idKey or not seenById[idKey]) and (not nameKey or not seenByName[nameKey]) then
            local isTrainerSource = (base.source == "Trainer" or base.source == "Vendor" or base.source == nil)
            if includeTrainer or (not hasScannedAny and isTrainerSource) then
                if idKey then seenById[idKey] = true end
                if nameKey then seenByName[nameKey] = true end
                local copy = {}
                for k, v in pairs(base) do copy[k] = v end
                copy.learned = (not hasScannedAny)
                copy.needsTrainer = hasScannedAny and isTrainerSource
                table.insert(list, copy)
            end
        end
    end

    table.sort(list, function(a, b)
        if (a.minSkill or 1) ~= (b.minSkill or 1) then
            return (a.minSkill or 1) < (b.minSkill or 1)
        end
        return (a.recipeId or 0) < (b.recipeId or 0)
    end)

    return list
end

local function FindModernRecipeId(recipe)
    if not recipe or not _G.C_TradeSkillUI then return nil end
    if type(recipe.recipeId) == "number" and recipe.recipeId > 0 then
        return recipe.recipeId
    end
    if not _G.C_TradeSkillUI.GetAllRecipeIDs or not _G.C_TradeSkillUI.GetRecipeInfo then
        return nil
    end
    local okIds, ids = pcall(_G.C_TradeSkillUI.GetAllRecipeIDs)
    if not okIds or type(ids) ~= "table" then return nil end
    for _, rId in ipairs(ids) do
        local okI, info = pcall(_G.C_TradeSkillUI.GetRecipeInfo, rId)
        if okI and type(info) == "table" then
            if (recipe.name and info.name == recipe.name) or (recipe.outputItemId and info.itemID == recipe.outputItemId) then
                return rId
            end
        end
    end
    return nil
end

local function SelectLegacyRecipe(recipe)
    if not recipe or not _G.GetNumTradeSkills or not _G.GetTradeSkillInfo or not _G.SelectTradeSkill then
        return false
    end
    local num = _G.GetNumTradeSkills() or 0
    for i = 1, num do
        local name, skillType = _G.GetTradeSkillInfo(i)
        local link = _G.GetTradeSkillItemLink and _G.GetTradeSkillItemLink(i)
        local outId = link and tonumber(link:match("item:(%d+)"))
        if skillType ~= "header" and skillType ~= "subheader" and ((recipe.outputItemId and outId == recipe.outputItemId) or (recipe.name and name == recipe.name)) then
            pcall(_G.SelectTradeSkill, i)
            if _G.TradeSkillFrame_SetSelection then
                pcall(_G.TradeSkillFrame_SetSelection, i)
            end
            return true
        end
    end
    return false
end

-- Taint-free profession/recipe navigation: uses C_TradeSkillUI.OpenTradeSkill / OpenRecipe
-- without ever mutating Blizzard's ProfessionsFrame tables directly.
function LL.RecipeScanner.OpenRecipe(recipe)
    if not recipe then return false end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        print("|cffff9900[Leveling Lad]|r Cannot open profession windows during combat.")
        return false
    end

    local skillLineID = recipe.skillLine or LL.RecipeDatabase.ResolveSkillLineId(recipe.profession)

    -- 1. Modern C_TradeSkillUI path
    if _G.C_TradeSkillUI and (_G.C_TradeSkillUI.OpenTradeSkill or _G.C_TradeSkillUI.OpenRecipe) then
        local opened = false
        if skillLineID and _G.C_TradeSkillUI.OpenTradeSkill then
            pendingOpenRecipe = {
                recipeId = recipe.recipeId,
                outputItemId = recipe.outputItemId,
                name = recipe.name,
                skillLine = skillLineID,
                expiresAt = ((_G.GetTime and _G.GetTime()) or 0) + 3.0,
            }
            local okOpen, res = pcall(_G.C_TradeSkillUI.OpenTradeSkill, skillLineID)
            if okOpen and res ~= false then
                opened = true
            end
        end

        local targetId = FindModernRecipeId(recipe)
        if targetId and _G.C_TradeSkillUI.OpenRecipe then
            local okRec, recRes = pcall(_G.C_TradeSkillUI.OpenRecipe, targetId)
            if okRec and recRes ~= false then
                pendingOpenRecipe = nil
                opened = true
            end
        end

        if opened then
            return true
        end
    end

    -- 2. Legacy TradeSkillFrame fallback
    local profName = recipe.profession or LL.RecipeDatabase.GetProfessionName(skillLineID)
    if profName == "Mining" then profName = "Smelting" end
    if profName and _G.CastSpellByName then
        pendingOpenRecipe = {
            recipeId = recipe.recipeId,
            outputItemId = recipe.outputItemId,
            name = recipe.name,
            expiresAt = ((_G.GetTime and _G.GetTime()) or 0) + 3.0,
        }
        pcall(_G.CastSpellByName, profName)
    end

    if SelectLegacyRecipe(recipe) then
        pendingOpenRecipe = nil
        return true
    end

    return profName ~= nil
end

function LL.RecipeScanner.CraftRecipe(recipe, quantity)
    if not recipe then return false, "NO_RECIPE" end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        print("|cffff9900[Leveling Lad]|r Cannot craft recipes during combat.")
        return false, "COMBAT"
    end

    quantity = math.max(1, math.floor(tonumber(quantity) or 1))

    -- Smart Guard: halt if active leveling play already hit target skill!
    local activePlay = LevelingLad_DB and LevelingLad_DB.activePlay
    if activePlay and activePlay.targetSkill and activePlay.recipe and activePlay.recipe.recipeId == recipe.recipeId then
        local apiSkill = LL.RecipeScanner.GetProfessionSkill(activePlay.skillLine or recipe.skillLine) or 0
        local effectiveSkill = math.max(apiSkill, tonumber(activePlay.liveSkill) or 0)
        if activePlay.goalReached == true or effectiveSkill >= activePlay.targetSkill then
            print(string.format(
                "|cff00ff88[Leveling Lad]|r Goal already reached (Skill %d / %d)! Halted crafting to save remaining materials.",
                effectiveSkill, activePlay.targetSkill
            ))
            return false, "TARGET_REACHED"
        end
    end

    -- 1. Modern C_TradeSkillUI path
    if _G.C_TradeSkillUI and _G.C_TradeSkillUI.CraftRecipe then
        local targetId = FindModernRecipeId(recipe)
        local frameShown = (_G.ProfessionsFrame and _G.ProfessionsFrame.IsShown and _G.ProfessionsFrame:IsShown())
            or (_G.TradeSkillFrame and _G.TradeSkillFrame.IsShown and _G.TradeSkillFrame:IsShown())
        if targetId and (frameShown or not _G.ProfessionsFrame) then
            local ok = pcall(_G.C_TradeSkillUI.CraftRecipe, targetId, quantity)
            if ok then
                print(string.format("|cff00ccff[Leveling Lad]|r Crafting %dx [%s]...", quantity, recipe.name or ("Recipe #" .. tostring(targetId))))
                return true, "CRAFTING"
            end
        elseif targetId then
            LL.RecipeScanner.OpenRecipe(recipe)
            print(string.format("|cff00ccff[Leveling Lad]|r Opened [%s] — click 'Craft All' again to begin crafting %dx.", recipe.name or "Recipe", quantity))
            return false, "OPENING_PROFESSION"
        end
    end

    -- 2. Legacy DoTradeSkill fallback
    if _G.GetNumTradeSkills and _G.GetTradeSkillInfo and _G.DoTradeSkill then
        local num = _G.GetNumTradeSkills() or 0
        for i = 1, num do
            local name, skillType = _G.GetTradeSkillInfo(i)
            local link = _G.GetTradeSkillItemLink and _G.GetTradeSkillItemLink(i)
            local outId = link and tonumber(link:match("item:(%d+)"))
            if skillType ~= "header" and skillType ~= "subheader" and ((recipe.outputItemId and outId == recipe.outputItemId) or (recipe.name and name == recipe.name)) then
                pcall(_G.DoTradeSkill, i, quantity)
                print(string.format("|cff00ccff[Leveling Lad]|r Crafting %dx [%s]...", quantity, recipe.name or name or "Recipe"))
                return true, "CRAFTING"
            end
        end
    end

    LL.RecipeScanner.OpenRecipe(recipe)
    return false, "OPENING_PROFESSION"
end

-- Parses CHAT_MSG_SKILL messages, updates cached rank, and triggers smart target-reached alerts
function LL.RecipeScanner.HandleSkillMessage(message)
    if type(message) ~= "string" or message == "" then return nil, nil end
    local pattern = BuildSkillUpPattern()
    local profName, newSkillStr = message:match(pattern)
    if not profName or not newSkillStr then
        profName, newSkillStr = message:match("skill in (.-) has increased to (%d+)")
    end
    local newSkill = tonumber(newSkillStr)
    if not profName or not newSkill then
        return nil, nil
    end

    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(profName)
    local prevSkill = nil
    if skillLine then
        local _, charSkills = EnsureCharTables()
        local existing = charSkills[skillLine]
        prevSkill = existing and tonumber(existing.rank) or nil
        local maxRank = existing and existing.maxRank or LL.GetNextMilestone(newSkill - 1)
        RecordSkillRank(skillLine, newSkill, math.max(maxRank, newSkill), true)
    end

    local goalReached = false
    local activePlay = LevelingLad_DB and LevelingLad_DB.activePlay
    if activePlay and activePlay.targetSkill and (activePlay.skillLine == skillLine or activePlay.profession == profName) then
        local settings = LevelingLad_DB and LevelingLad_DB.settings
        local customGoal = settings and settings.targetMode == "CUSTOM" and tonumber(settings.customTargetSkill) or nil
        local trackedGoal = activePlay.goalTargetSkill or activePlay.requestedTargetSkill or activePlay.reachedSkill or activePlay.targetSkill
        if customGoal and customGoal ~= trackedGoal then
            -- Stale activePlay from an older goal setting; clear silently
            LevelingLad_DB.activePlay = nil
        else
            local priorSkill = tonumber(activePlay.liveSkill) or prevSkill or tonumber(activePlay.startSkill) or 0
            activePlay.liveSkill = newSkill
            if not activePlay.goalReached and newSkill >= activePlay.targetSkill then
                activePlay.goalReached = true
                if priorSkill < activePlay.targetSkill then
                    goalReached = true
                    print(string.format(
                        "|cff00ff88[Leveling Lad]|r Goal reached! %s hit skill %d (target: %d). Stop crafting to save remaining materials!",
                        profName, newSkill, activePlay.targetSkill
                    ))
                end
            end
        end
    end

    -- Refresh cached Top 5 plays for the new skill level so SideWindow skill ranges update live
    if skillLine and LevelingLad_DB and LL.LevelingEngine and LL.LevelingEngine.FindTopPlays then
        local activeProf = LL.RecipeScanner.GetActiveProfession()
        local verifierBusy = LL.AHVerifier and LL.AHVerifier.IsRunning and LL.AHVerifier.IsRunning()
        if activeProf and activeProf.skillLine == skillLine and not verifierBusy then
            local dataStatus = LL.GetAHDataStatus and LL.GetAHDataStatus() or "FRESH"
            if dataStatus ~= "NO_DATA" then
                LevelingLad_DB.lastTopPlays = LL.LevelingEngine.FindTopPlays(skillLine, newSkill)
            end
        end
    end

    for _, cb in ipairs(skillupCallbacks) do
        pcall(cb, profName, newSkill, skillLine, goalReached)
    end

    if LL.DetailWindow and LL.DetailWindow.OnSkillUp then
        LL.DetailWindow.OnSkillUp(profName, newSkill, skillLine, goalReached)
    end
    if LL.SideWindow and LL.SideWindow.Refresh then
        LL.SideWindow.Refresh()
    end

    return profName, newSkill, goalReached
end

-- Diagnostic helper (/ll debug): prints raw WoW: Forever C_TradeSkillUI difficulty enums & sample recipes
function LL.RecipeScanner.DebugDump()
    local active = LL.RecipeScanner.GetActiveProfession()
    print(string.format("|cff00ccff[Leveling Lad Debug]|r Active: %s (id=%s) Skill: %d/%d",
        tostring(active.name), tostring(active.skillLine), tonumber(active.rank) or 0, tonumber(active.maxRank) or 0))

    local enumTbl = _G.Enum and (
        _G.Enum.TradeskillRelativeDifficulty
        or _G.Enum.TradeSkillRelativeDifficulty
        or _G.Enum.ProfessionDifficulty
    )
    if type(enumTbl) == "table" then
        local parts = {}
        for k, v in pairs(enumTbl) do
            table.insert(parts, string.format("%s=%s", tostring(k), tostring(v)))
        end
        table.sort(parts)
        print("  Enum.TradeskillRelativeDifficulty: " .. table.concat(parts, ", "))
    else
        print("  Enum.TradeskillRelativeDifficulty: <nil>")
    end

    if _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetAllRecipeIDs and _G.C_TradeSkillUI.GetRecipeInfo then
        local okIds, ids = pcall(_G.C_TradeSkillUI.GetAllRecipeIDs)
        if okIds and type(ids) == "table" and #ids > 0 then
            local counts = { ORANGE = 0, YELLOW = 0, GREEN = 0, GRAY = 0, NIL = 0 }
            local samples = {}
            for _, rId in ipairs(ids) do
                local okI, info = pcall(_G.C_TradeSkillUI.GetRecipeInfo, rId)
                if okI and type(info) == "table" then
                    local norm = LL.RecipeScanner.NormalizeLiveDifficulty(info.difficulty, info.relativeDifficulty, info.numSkillUps)
                    counts[norm or "NIL"] = (counts[norm or "NIL"] or 0) + 1
                    if #samples < 6 or (norm and norm ~= "GRAY" and #samples < 10) then
                        table.insert(samples, string.format(
                            "  [%d] %s | learned=%s | diff=%s | relDiff=%s | skillUps=%s => %s",
                            rId, tostring(info.name), tostring(info.learned),
                            tostring(info.difficulty), tostring(info.relativeDifficulty),
                            tostring(info.numSkillUps), tostring(norm or "NIL")
                        ))
                    end
                end
            end
            print(string.format("  C_TradeSkillUI Recipes (%d total): O=%d Y=%d G=%d Gr=%d Nil=%d",
                #ids, counts.ORANGE, counts.YELLOW, counts.GREEN, counts.GRAY, counts.NIL))
            for _, line in ipairs(samples) do
                print(line)
            end
            return counts
        else
            print("  C_TradeSkillUI.GetAllRecipeIDs(): empty (open your Profession window first!)")
        end
    else
        print("  C_TradeSkillUI not available.")
    end
    return nil
end

function LL.RecipeScanner.Init()
    if LL.RecipeScanner._initialized then return end
    LL.RecipeScanner._initialized = true

    local frame = CreateFrame("Frame")
    if frame and frame.RegisterEvent then
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_SHOW")
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_UPDATE")
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_DATA_SOURCE_CHANGED")
        pcall(frame.RegisterEvent, frame, "TRAINER_SHOW")
        pcall(frame.RegisterEvent, frame, "TRAINER_UPDATE")
        pcall(frame.RegisterEvent, frame, "SKILL_LINES_CHANGED")
        pcall(frame.RegisterEvent, frame, "CHAT_MSG_SKILL")
        pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")

        frame:SetScript("OnEvent", function(_, event, arg1)
            if event == "CHAT_MSG_SKILL" then
                LL.RecipeScanner.HandleSkillMessage(arg1)
                return
            end

            if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
                LL.RecipeScanner.ScanTrainerWindow()
                if LL.SideWindow and LL.SideWindow.frame
                    and (not LL.SideWindow.frame.IsShown or LL.SideWindow.frame:IsShown())
                    and LL.SideWindow.Refresh then
                    LL.SideWindow.Refresh()
                end
                return
            end

            if event == "SKILL_LINES_CHANGED" or event == "PLAYER_ENTERING_WORLD" then
                LL.RecipeScanner.GetCharacterProfessions()
                if LL.SideWindow and LL.SideWindow.frame
                    and (not LL.SideWindow.frame.IsShown or LL.SideWindow.frame:IsShown())
                    and LL.SideWindow.Refresh then
                    LL.SideWindow.Refresh()
                end
                return
            end

            LL.RecipeScanner.ScanCurrentProfessionWindow()

            if pendingOpenRecipe then
                local now = (_G.GetTime and _G.GetTime()) or 0
                if pendingOpenRecipe.expiresAt and now > pendingOpenRecipe.expiresAt then
                    pendingOpenRecipe = nil
                elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
                    local targetId = FindModernRecipeId(pendingOpenRecipe)
                    if targetId and _G.C_TradeSkillUI and _G.C_TradeSkillUI.OpenRecipe then
                        pcall(_G.C_TradeSkillUI.OpenRecipe, targetId)
                        pendingOpenRecipe = nil
                    elseif SelectLegacyRecipe(pendingOpenRecipe) then
                        pendingOpenRecipe = nil
                    end
                end
            end
        end)
    end
    LL.RecipeScanner.frame = frame
end
