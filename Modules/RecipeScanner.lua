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

local function RecordSkillRank(skillLineOrName, rank, maxRank)
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName)
    if not skillLine then return nil end
    local profName = LL.RecipeDatabase.GetProfessionName(skillLine)
    local _, charSkills = EnsureCharTables()
    local existing = charSkills[skillLine]
    local cleanRank = math.max(1, math.floor(tonumber(rank) or (existing and existing.rank) or 1))
    local cleanMax = math.max(cleanRank, math.floor(tonumber(maxRank) or (existing and existing.maxRank) or 75))
    charSkills[skillLine] = {
        skillLine = skillLine,
        name = profName,
        rank = cleanRank,
        maxRank = cleanMax,
        updatedAt = (_G.time and _G.time()) or 0,
    }
    return charSkills[skillLine]
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
    else
        local currentRank = LL.RecipeScanner.GetProfessionSkill(recipe.skillLine or recipe.profession) or 1
        local diff = DIFFICULTY_NORMALIZE[(recipe.liveDifficulty or ""):lower()] or "ORANGE"
        if diff == "GRAY" then
            recipe.orange = recipe.orange or 1
            recipe.yellow = recipe.yellow or math.max(1, currentRank - 30)
            recipe.green = recipe.green or math.max(1, currentRank - 15)
            recipe.gray = recipe.gray or currentRank
        elseif diff == "GREEN" then
            recipe.orange = recipe.orange or 1
            recipe.yellow = recipe.yellow or math.max(1, currentRank - 15)
            recipe.green = recipe.green or currentRank
            recipe.gray = recipe.gray or (currentRank + 15)
        elseif diff == "YELLOW" then
            recipe.orange = recipe.orange or 1
            recipe.yellow = recipe.yellow or currentRank
            recipe.green = recipe.green or (currentRank + 15)
            recipe.gray = recipe.gray or (currentRank + 30)
        else
            recipe.orange = recipe.orange or currentRank
            recipe.yellow = recipe.yellow or (currentRank + 20)
            recipe.green = recipe.green or (currentRank + 35)
            recipe.gray = recipe.gray or (currentRank + 50)
        end
        recipe.minSkill = recipe.minSkill or recipe.orange or 1
        recipe.source = recipe.source or "Known"
    end
    return recipe
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
    recipe.learned = true
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

    local windowSkillLine, windowProfName = nil, nil
    if _G.C_TradeSkillUI.GetBaseProfessionInfo then
        local okP, pInfo = pcall(_G.C_TradeSkillUI.GetBaseProfessionInfo)
        if okP and type(pInfo) == "table" then
            local pid = (type(pInfo.parentProfessionID) == "number" and pInfo.parentProfessionID > 0) and pInfo.parentProfessionID or pInfo.professionID
            local pname = pInfo.parentProfessionName or pInfo.professionName
            windowSkillLine = LL.RecipeDatabase.ResolveSkillLineId(pid or pname)
            windowProfName = LL.RecipeDatabase.GetProfessionName(windowSkillLine or pname)
            if windowSkillLine and (pInfo.skillLevel or 0) > 0 then
                RecordSkillRank(windowSkillLine, pInfo.skillLevel, pInfo.maxSkillLevel)
            end
        end
    end

    local charRecipes = EnsureCharTables()
    local scanned = 0

    for _, recipeID in ipairs(recipeIDs) do
        local okInfo, info = pcall(_G.C_TradeSkillUI.GetRecipeInfo, recipeID)
        if okInfo and type(info) == "table" and info.learned then
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
                local rSkillLine = windowSkillLine
                local rProfName = windowProfName
                if _G.C_TradeSkillUI.GetProfessionInfoByRecipeID then
                    local okPR, prInfo = pcall(_G.C_TradeSkillUI.GetProfessionInfoByRecipeID, recipeID)
                    if okPR and type(prInfo) == "table" then
                        local pid = (type(prInfo.parentProfessionID) == "number" and prInfo.parentProfessionID > 0) and prInfo.parentProfessionID or prInfo.professionID
                        local resolved = LL.RecipeDatabase.ResolveSkillLineId(pid or prInfo.parentProfessionName or prInfo.professionName)
                        if resolved then
                            rSkillLine = resolved
                            rProfName = LL.RecipeDatabase.GetProfessionName(resolved)
                        end
                    end
                end

                local minMade = (schematic and schematic.quantityMin) or 1
                local maxMade = (schematic and schematic.quantityMax) or minMade
                local saved = SaveScannedRecipe(charRecipes, {
                    recipeId = recipeID,
                    name = info.name or string.format("Recipe #%d", recipeID),
                    profession = rProfName or "Crafting",
                    skillLine = rSkillLine,
                    liveDifficulty = info.difficulty,
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

    -- 1. Character's scanned known recipes
    local charRecipes = EnsureCharTables()
    for _, rec in pairs(charRecipes) do
        if type(rec) == "table" and rec.skillLine == skillLine then
            local idKey = rec.recipeId
            local nameKey = rec.name and rec.name:lower()
            if (not idKey or not seenById[idKey]) and (not nameKey or not seenByName[nameKey]) then
                if idKey then seenById[idKey] = true end
                if nameKey then seenByName[nameKey] = true end
                rec.learned = true
                rec.needsTrainer = false
                table.insert(list, rec)
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
    if skillLine then
        local _, charSkills = EnsureCharTables()
        local existing = charSkills[skillLine]
        local maxRank = existing and existing.maxRank or LL.GetNextMilestone(newSkill - 1)
        local rec = RecordSkillRank(skillLine, newSkill, math.max(maxRank, newSkill))
        if rec then
            rec.chatSkillUpAt = (_G.time and _G.time()) or 0
        end
    end

    local goalReached = false
    local activePlay = LevelingLad_DB and LevelingLad_DB.activePlay
    if activePlay and activePlay.targetSkill and (activePlay.skillLine == skillLine or activePlay.profession == profName) then
        activePlay.liveSkill = newSkill
        if newSkill >= activePlay.targetSkill then
            goalReached = true
            activePlay.goalReached = true
            print(string.format(
                "|cff00ff88[Leveling Lad]|r Goal reached! %s hit skill %d (target: %d). Stop crafting to save remaining materials!",
                profName, newSkill, activePlay.targetSkill
            ))
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

function LL.RecipeScanner.Init()
    if LL.RecipeScanner._initialized then return end
    LL.RecipeScanner._initialized = true

    local frame = CreateFrame("Frame")
    if frame and frame.RegisterEvent then
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_SHOW")
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_UPDATE")
        pcall(frame.RegisterEvent, frame, "TRADE_SKILL_DATA_SOURCE_CHANGED")
        pcall(frame.RegisterEvent, frame, "SKILL_LINES_CHANGED")
        pcall(frame.RegisterEvent, frame, "CHAT_MSG_SKILL")
        pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")

        frame:SetScript("OnEvent", function(_, event, arg1)
            if event == "CHAT_MSG_SKILL" then
                LL.RecipeScanner.HandleSkillMessage(arg1)
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
