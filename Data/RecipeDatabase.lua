local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.RecipeDatabase = {}

local SKILL_LINE_ID_TO_PROFESSION = {
    [129] = "First Aid",
    [164] = "Blacksmithing",
    [165] = "Leatherworking",
    [171] = "Alchemy",
    [185] = "Cooking",
    [186] = "Mining",
    [197] = "Tailoring",
    [202] = "Engineering",
    [333] = "Enchanting",
}

local PROFESSION_TO_SKILL_LINE_ID = {
    ["First Aid"]      = 129,
    ["Blacksmithing"]  = 164,
    ["Leatherworking"] = 165,
    ["Alchemy"]        = 171,
    ["Cooking"]        = 185,
    ["Mining"]         = 186,
    ["Smelting"]       = 186,
    ["Tailoring"]      = 197,
    ["Engineering"]    = 202,
    ["Enchanting"]     = 333,
}

LL.RecipeDatabase.SKILL_LINE_ID_TO_PROFESSION = SKILL_LINE_ID_TO_PROFESSION
LL.RecipeDatabase.PROFESSION_TO_SKILL_LINE_ID = PROFESSION_TO_SKILL_LINE_ID

-- Strictly WoW: Forever recipe catalog indexed by [skillLine][recipeId].
-- Intentionally contains ZERO WoW Classic Era recipes (WoW: Forever reworks 940+ recipes,
-- skill brackets, reagents, and profession assignments).
-- Recipes are populated live from the WoW: Forever client via C_TradeSkillUI / TRAINER_SHOW,
-- or via verified WoW: Forever datasets (e.g. ForeverDB.net API exports).
local RECIPES = {
    [129] = {}, -- First Aid
    [164] = {}, -- Blacksmithing
    [165] = {}, -- Leatherworking
    [171] = {}, -- Alchemy
    [185] = {}, -- Cooking
    [186] = {}, -- Mining
    [197] = {}, -- Tailoring
    [202] = {}, -- Engineering
    [333] = {}, -- Enchanting
}

local RECIPE_BY_ID = {}

local function RebuildIndex()
    RECIPE_BY_ID = {}
    for skillLineId, profRecipes in pairs(RECIPES) do
        local profName = SKILL_LINE_ID_TO_PROFESSION[skillLineId] or "Crafting"
        for rId, rec in pairs(profRecipes) do
            rec.recipeId = rId
            rec.skillLine = skillLineId
            rec.profession = profName
            rec.minSkill = rec.minSkill or rec.orange or 1
            rec.outputQty = rec.outputQty or 1
            RECIPE_BY_ID[rId] = rec
        end
    end
end

RebuildIndex()

LL.RecipeDatabase.RECIPES = RECIPES

function LL.RecipeDatabase.RegisterForeverRecipe(rec)
    if type(rec) ~= "table" or not rec.recipeId then return false end
    local skillLine = LL.RecipeDatabase.ResolveSkillLineId(rec.skillLine or rec.profession)
    if not skillLine then return false end
    RECIPES[skillLine] = RECIPES[skillLine] or {}
    rec.skillLine = skillLine
    rec.profession = SKILL_LINE_ID_TO_PROFESSION[skillLine] or rec.profession or "Crafting"
    rec.minSkill = rec.minSkill or rec.orange or 1
    rec.outputQty = rec.outputQty or 1
    RECIPES[skillLine][rec.recipeId] = rec
    RECIPE_BY_ID[rec.recipeId] = rec
    return true
end

function LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName)
    if type(skillLineOrName) == "number" and SKILL_LINE_ID_TO_PROFESSION[skillLineOrName] then
        return skillLineOrName
    end
    if type(skillLineOrName) == "string" then
        local trimmed = skillLineOrName:match("^%s*(.-)%s*$") or ""
        if PROFESSION_TO_SKILL_LINE_ID[trimmed] then
            return PROFESSION_TO_SKILL_LINE_ID[trimmed]
        end
        local lower = trimmed:lower()
        for name, id in pairs(PROFESSION_TO_SKILL_LINE_ID) do
            if name:lower() == lower or lower:sub(-(#name + 1)) == (" " .. name:lower()) then
                return id
            end
        end
    end
    return nil
end

function LL.RecipeDatabase.GetProfessionName(skillLineOrName)
    local id = LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName)
    if id then
        return SKILL_LINE_ID_TO_PROFESSION[id]
    end
    if type(skillLineOrName) == "string" and skillLineOrName ~= "" then
        return skillLineOrName
    end
    return nil
end

function LL.RecipeDatabase.GetSupportedProfessions()
    local list = {}
    local order = { 164, 197, 165, 171, 202, 185, 333, 129, 186 }
    for _, id in ipairs(order) do
        table.insert(list, { skillLine = id, name = SKILL_LINE_ID_TO_PROFESSION[id] })
    end
    return list
end

-- Normalizes reagent representations into a deterministic sorted array:
--   Accepts either { [itemId] = qty } OR { { itemId = id, count = qty, name = ... }, ... }
function LL.RecipeDatabase.NormalizeReagents(reagents)
    local normalized = {}
    if type(reagents) ~= "table" then
        return normalized
    end

    if #reagents > 0 and type(reagents[1]) == "table" and reagents[1].itemId then
        for _, entry in ipairs(reagents) do
            local id = tonumber(entry.itemId)
            local qty = tonumber(entry.count or entry.qty) or 0
            if id and id > 0 and qty > 0 then
                local meta = LL.VendorDatabase and LL.VendorDatabase.GetItemMetadata and LL.VendorDatabase.GetItemMetadata(id, nil, true)
                table.insert(normalized, {
                    itemId = id,
                    count = qty,
                    name = entry.name or (meta and meta.name) or string.format("Item #%d", id),
                })
            end
        end
    else
        local ids = {}
        for itemId, qty in pairs(reagents) do
            if type(itemId) == "number" and itemId > 0 and type(qty) == "number" and qty > 0 then
                table.insert(ids, itemId)
            end
        end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local meta = LL.VendorDatabase and LL.VendorDatabase.GetItemMetadata and LL.VendorDatabase.GetItemMetadata(id, nil, true)
            table.insert(normalized, {
                itemId = id,
                count = reagents[id],
                name = (meta and meta.name) or string.format("Item #%d", id),
            })
        end
    end
    return normalized
end

function LL.RecipeDatabase.GetRecipesForProfession(skillLineOrName)
    local id = LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName)
    if not id or not RECIPES[id] then
        return {}
    end
    local list = {}
    for _, rec in pairs(RECIPES[id]) do
        table.insert(list, rec)
    end
    table.sort(list, function(a, b)
        if (a.minSkill or 1) ~= (b.minSkill or 1) then
            return (a.minSkill or 1) < (b.minSkill or 1)
        end
        return (a.recipeId or 0) < (b.recipeId or 0)
    end)
    return list
end

function LL.RecipeDatabase.GetRecipeById(recipeId)
    return recipeId and RECIPE_BY_ID[recipeId] or nil
end

function LL.RecipeDatabase.GetRecipeByName(recipeName, skillLineOrName)
    if type(recipeName) ~= "string" or recipeName == "" then return nil end
    local targetLower = recipeName:lower()
    local id = skillLineOrName and LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName) or nil
    if id and RECIPES[id] then
        for _, rec in pairs(RECIPES[id]) do
            if rec.name and rec.name:lower() == targetLower then
                return rec
            end
        end
    else
        for _, profRecipes in pairs(RECIPES) do
            for _, rec in pairs(profRecipes) do
                if rec.name and rec.name:lower() == targetLower then
                    return rec
                end
            end
        end
    end
    return nil
end

function LL.RecipeDatabase.GetRecipeByOutputItem(outputItemId, skillLineOrName)
    if not outputItemId or outputItemId <= 0 then return nil end
    local id = skillLineOrName and LL.RecipeDatabase.ResolveSkillLineId(skillLineOrName) or nil
    if id and RECIPES[id] then
        for _, rec in pairs(RECIPES[id]) do
            if rec.outputItemId == outputItemId then
                return rec
            end
        end
    else
        for _, profRecipes in pairs(RECIPES) do
            for _, rec in pairs(profRecipes) do
                if rec.outputItemId == outputItemId then
                    return rec
                end
            end
        end
    end
    return nil
end

-- Queries the character's current learned crafting professions & skill ranks in WoW: Forever.
-- Returns: skillsByLineId = { [skillLine] = { skillLine, name, rank, maxRank } }, hasAuthData (boolean)
function LL.RecipeDatabase.GetCharacterSkillRanks()
    local skills = {}
    local hasAuthData = false

    local function RecordSkill(skillLine, name, rank, maxRank)
        local resolvedId = LL.RecipeDatabase.ResolveSkillLineId(skillLine or name)
        if not resolvedId then return end
        local canonicalName = SKILL_LINE_ID_TO_PROFESSION[resolvedId]
        if not canonicalName then return end
        local existing = skills[resolvedId]
        local cleanRank = math.max(1, math.floor(tonumber(rank) or 1))
        local cleanMax = math.max(cleanRank, math.floor(tonumber(maxRank) or 75))
        if not existing or cleanRank > existing.rank then
            skills[resolvedId] = {
                skillLine = resolvedId,
                name = canonicalName,
                rank = cleanRank,
                maxRank = cleanMax,
            }
        end
    end

    -- 1. Modern GetProfessions / GetProfessionInfo
    if _G.GetProfessions and _G.GetProfessionInfo then
        local ok, p1, p2, arch, fish, cook, firstAid = pcall(_G.GetProfessions)
        if ok then
            local slots = { p1, p2, arch, fish, cook, firstAid }
            for i = 1, 6 do
                local idx = slots[i]
                if type(idx) == "number" then
                    local okI, pName, _, rank, maxRank, _, _, skillLine = pcall(_G.GetProfessionInfo, idx)
                    if okI and pName then
                        hasAuthData = true
                        RecordSkill(skillLine, pName, rank, maxRank)
                    end
                end
            end
        end
    end

    -- 2. Legacy GetNumSkillLines / GetSkillLineInfo fallback
    if _G.GetNumSkillLines and _G.GetSkillLineInfo then
        local okNum, num = pcall(_G.GetNumSkillLines)
        if okNum and type(num) == "number" and num > 0 then
            for i = 1, num do
                local okInfo, sName, isHeader, _, rank, _, _, maxRank = pcall(_G.GetSkillLineInfo, i)
                if okInfo and not isHeader and type(sName) == "string" then
                    local resolvedId = LL.RecipeDatabase.ResolveSkillLineId(sName)
                    if resolvedId then
                        hasAuthData = true
                        RecordSkill(resolvedId, sName, rank, maxRank)
                    end
                end
            end
        end
    end

    -- 3. Currently open C_TradeSkillUI window (Child & Base profession info)
    if _G.C_TradeSkillUI then
        local function ReadProfInfo(fn)
            if type(fn) ~= "function" then return end
            local okP, info = pcall(fn)
            if okP and type(info) == "table" and (info.skillLevel or 0) > 0 then
                local pid = (type(info.parentProfessionID) == "number" and info.parentProfessionID > 0) and info.parentProfessionID or info.professionID
                local pname = info.parentProfessionName or info.professionName
                RecordSkill(pid, pname, info.skillLevel, info.maxSkillLevel)
            end
        end
        ReadProfInfo(_G.C_TradeSkillUI.GetBaseProfessionInfo)
        ReadProfInfo(_G.C_TradeSkillUI.GetChildProfessionInfo)
    end
    if _G.GetTradeSkillLine then
        local okL, lineName, rank, maxRank = pcall(_G.GetTradeSkillLine)
        if okL and type(lineName) == "string" and lineName ~= "" and lineName ~= "UNKNOWN" and type(rank) == "number" and rank > 0 then
            RecordSkill(nil, lineName, rank, maxRank)
        end
    end

    -- 4. Merge persisted LevelingLad_DB.charSkills for this character
    local charKey = LL.GetCharacterKey and LL.GetCharacterKey()
    local saved = charKey and LevelingLad_DB and LevelingLad_DB.charSkills and LevelingLad_DB.charSkills[charKey]
    if type(saved) == "table" then
        for skillLine, info in pairs(saved) do
            if type(info) == "table" and not skills[skillLine] then
                RecordSkill(skillLine, info.name, info.rank, info.maxRank)
            end
        end
    end

    return skills, hasAuthData
end
