-- Comprehensive Mock WoW Lua Environment for Leveling Lad Headless LuaJIT Testing
local Mock = {
    currentTime = 1700000000.0,
    playerMoney = 500000, -- 50g default
    bagCounts = {},
    bankCounts = {},
    itemInfoDB = {},      -- [itemId] = { name, link, quality, itemLevel, minLevel, itemType, itemSubType, stackCount, equipLoc, texture, sellPrice, classID, subClassID }
    tradeSkills = {},
    tradeSkillLine = "Blacksmithing",
    tradeSkillRank = 1,
    tradeSkillMaxRank = 75,
    modernProfession = {
        professionID = 164,
        parentProfessionID = 164,
        professionName = "Blacksmithing",
        parentProfessionName = "Blacksmithing",
        skillLevel = 1,
        maxSkillLevel = 75,
    },
    modernRecipes = {},   -- [recipeId] = { recipeID, name, learned, outputItemID, quantityMin, quantityMax, reagents = { { itemID, qty } }, skillLine, difficulty }
    professions = {},     -- { { name, icon, skillLevel, maxSkillLevel, skillLine }, ... }
    skillLines = {},      -- { { name, isHeader, rank, maxRank }, ... }
    auctionListingsByQuery = {},
    commodityResults = {},
    itemSearchResults = {},
    currentAuctionResults = {},
    lastAuctionQuery = nil,
    lastBrowseQuery = nil,
    lastOpenedTradeSkill = nil,
    lastOpenedRecipeId = nil,
    lastCraftedModern = nil,
    timers = {},
    castSpells = {},
    selectedTradeSkill = nil,
    craftedTradeSkill = nil,
    placedBids = {},
    merchantItems = {},
    depositRate = 5,
    inCombat = false,
    frames = {},
    chatMessages = {},
    useModernTradeSkill = false,
}

_G.SlashCmdList = _G.SlashCmdList or {}

_G.GetTime = function() return Mock.currentTime end
_G.time = function() return math.floor(Mock.currentTime) end
_G.UnitName = function(unit) return unit == "player" and "SkillTester" or "Target" end
_G.GetRealmName = function() return "Forever" end
_G.GetMoney = function() return Mock.playerMoney end
_G.InCombatLockdown = function() return Mock.inCombat == true end

_G.GetItemCount = function(itemId, includeBank)
    local bags = Mock.bagCounts[itemId] or 0
    if includeBank then
        return bags + (Mock.bankCounts[itemId] or 0)
    end
    return bags
end

_G.GetItemInfo = function(target)
    local itemId = tonumber(target)
    if not itemId and type(target) == "string" then
        itemId = tonumber(target:match("item:(%d+)"))
    end
    local info = itemId and Mock.itemInfoDB[itemId]
    if not info then return nil end
    local link = info.link or string.format("|cffffffff|Hitem:%d:0:0:0:0:0:0:0|h[%s]|h|r", itemId, info.name or ("Item #" .. itemId))
    return info.name, link, info.quality or 1, info.itemLevel or 1, info.minLevel or 1,
        info.itemType or "Trade Goods", info.itemSubType or "Other",
        info.stackCount or 20, info.equipLoc or "", info.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
        info.sellPrice or 0, info.classID or 7, info.subClassID or 0
end

_G.GetItemIcon = function(itemId)
    local info = itemId and Mock.itemInfoDB[itemId]
    return (info and info.texture) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

_G.C_Item = {
    GetItemCount = function(itemId, includeBank)
        return _G.GetItemCount(itemId, includeBank)
    end,
    GetItemInfo = function(target)
        return _G.GetItemInfo(target)
    end,
    GetItemIconByID = function(itemId)
        return _G.GetItemIcon(itemId)
    end,
    RequestLoadItemDataByID = function() end,
}

_G.C_Timer = {
    After = function(delay, callback)
        table.insert(Mock.timers, { delay = delay, callback = callback })
    end,
}

function Mock.FlushTimers(maxSteps)
    local steps = 0
    local limit = maxSteps or 100
    while #Mock.timers > 0 and steps < limit do
        local t = table.remove(Mock.timers, 1)
        steps = steps + 1
        if t and t.callback then
            t.callback()
        end
    end
end

function Mock.FireEvent(event, ...)
    for _, frame in ipairs(Mock.frames) do
        if frame.events and frame.events[event] and frame.scripts and frame.scripts["OnEvent"] then
            frame.scripts["OnEvent"](frame, event, ...)
        end
    end
end

function Mock.SimulateSkillUp(professionName, newRank)
    local msg = string.format("Your skill in %s has increased to %d.", professionName, newRank)
    if Mock.tradeSkillLine == professionName then
        Mock.tradeSkillRank = newRank
    end
    if Mock.modernProfession and Mock.modernProfession.professionName == professionName then
        Mock.modernProfession.skillLevel = newRank
    end
    for _, sl in ipairs(Mock.skillLines) do
        if sl.name == professionName then
            sl.rank = newRank
        end
    end
    for _, p in ipairs(Mock.professions) do
        if p.name == professionName then
            p.skillLevel = newRank
        end
    end
    Mock.FireEvent("CHAT_MSG_SKILL", msg)
    return msg
end

_G.CreateFrame = function(frameType, name, parent, template)
    local frame = {
        frameType = frameType,
        name = name,
        parent = parent,
        template = template,
        events = {},
        scripts = {},
        lines = {},
        text = "",
        shown = true,
        minVal = 0,
        maxVal = 1,
        val = 0,
        hasFocus = false,
        enabled = true,
    }
    if name then _G[name] = frame end
    table.insert(Mock.frames, frame)

    function frame:GetName() return self.name end
    function frame:GetParent() return self.parent end
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:SetScript(scriptName, func) self.scripts[scriptName] = func end
    function frame:GetScript(scriptName) return self.scripts[scriptName] end
    function frame:HookScript(scriptName, func)
        local prev = self.scripts[scriptName]
        self.scripts[scriptName] = function(...) if prev then prev(...) end; func(...) end
    end
    function frame:Trigger(event, ...)
        if self.events[event] and self.scripts["OnEvent"] then
            self.scripts["OnEvent"](self, event, ...)
        end
    end
    function frame:Click(button)
        if self.enabled and self.scripts["OnClick"] then
            self.scripts["OnClick"](self, button or "LeftButton")
        end
    end
    function frame:Enable() self.enabled = true end
    function frame:Disable() self.enabled = false end
    function frame:IsEnabled() return self.enabled end
    function frame:SetOwner(owner) self.owner = owner end
    function frame:GetOwner() return self.owner end
    function frame:ClearLines() self.lines = {} end
    function frame:AddLine(text) table.insert(self.lines, text) end
    function frame:SetHyperlink(link) self.hyperlink = link end
    function frame:SetSize(w, h) self.width = w; self.height = h end
    function frame:SetWidth(w) self.width = w end
    function frame:SetHeight(h) self.height = h end
    function frame:SetPoint(...) end
    function frame:ClearAllPoints() end
    function frame:SetAllPoints(...) end
    function frame:SetFrameStrata(s) self.strata = s end
    function frame:GetFrameStrata() return self.strata end
    function frame:SetToplevel(v) self.toplevel = (v == true) end
    function frame:IsToplevel() return self.toplevel == true end
    function frame:Raise() self.raiseCount = (self.raiseCount or 0) + 1 end
    function frame:SetMovable(...) end
    function frame:EnableMouse(...) end
    function frame:RegisterForDrag(...) end
    function frame:StartMoving() end
    function frame:StopMovingOrSizing() end
    function frame:SetAutoFocus(...) end
    function frame:SetMaxLetters(...) end
    function frame:ClearFocus() self.hasFocus = false end
    function frame:SetFocus() self.hasFocus = true end
    function frame:HasFocus() return self.hasFocus end
    function frame:SetText(t) self.text = tostring(t or "") end
    function frame:GetText() return self.text end
    function frame:SetNumber(n) self.text = tostring(n or 0) end
    function frame:GetNumber() return tonumber(self.text) or 0 end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:IsVisible() return self.shown end
    function frame:SetMinMaxValues(minV, maxV) self.minVal = minV; self.maxVal = maxV end
    function frame:SetValue(v)
        self.val = v
        if self.scripts["OnValueChanged"] then
            self.scripts["OnValueChanged"](self, v)
        end
    end
    function frame:GetValue() return self.val end
    function frame:SetStatusBarTexture(...) end
    function frame:SetStatusBarColor(...) end
    function frame:SetScrollChild(child) self.scrollChild = child end
    function frame:SetVerticalScroll(offset) self.vScroll = offset end
    function frame:GetVerticalScroll() return self.vScroll or 0 end
    function frame:EnableMouseWheel(...) end
    function frame:SetClipsChildren(...) end
    function frame:SetOrientation(...) end
    function frame:SetValueStep(...) end
    function frame:SetThumbTexture(...) end
    function frame:CreateTexture(...)
        local tex = { texture = nil }
        function tex:SetSize(w, h) self.width = w; self.height = h end
        function tex:SetPoint(...) end
        function tex:SetAllPoints(...) end
        function tex:SetColorTexture(r, g, b, a) self.r = r; self.g = g; self.b = b; self.a = a end
        function tex:SetTexture(t) self.texture = t end
        function tex:Show() self.shown = true end
        function tex:Hide() self.shown = false end
        return tex
    end
    function frame:CreateFontString(...)
        local fs = { text = "", shown = true }
        function fs:SetPoint(...) end
        function fs:SetWidth(...) end
        function fs:SetJustifyH(...) end
        function fs:SetJustifyV(...) end
        function fs:SetWordWrap(...) end
        function fs:SetText(t) self.text = tostring(t or "") end
        function fs:GetText() return self.text end
        function fs:GetStringHeight() return 14 end
        function fs:Show() self.shown = true end
        function fs:Hide() self.shown = false end
        return fs
    end
    return frame
end

_G.UIParent = _G.CreateFrame("Frame", "UIParent")
_G.GameTooltip = _G.CreateFrame("GameTooltip", "GameTooltip")
_G.AuctionFrame = _G.CreateFrame("Frame", "AuctionFrame", _G.UIParent)
_G.BrowseName = _G.CreateFrame("EditBox", "BrowseName", _G.AuctionFrame)
_G.TradeSkillFrame = _G.CreateFrame("Frame", "TradeSkillFrame", _G.UIParent)
_G.TradeSkillFrame:Hide()
_G.ProfessionsFrame = _G.CreateFrame("Frame", "ProfessionsFrame", _G.UIParent)
_G.ProfessionsFrame:Hide()

-- Character Professions API
_G.GetProfessions = function()
    if #Mock.professions == 0 then return nil end
    local idxs = {}
    for i = 1, 6 do
        idxs[i] = Mock.professions[i] and i or nil
    end
    return idxs[1], idxs[2], idxs[3], idxs[4], idxs[5], idxs[6]
end

_G.GetProfessionInfo = function(index)
    local p = Mock.professions[index]
    if not p then return nil end
    return p.name, p.icon or "", p.skillLevel or 1, p.maxSkillLevel or 75, 0, 0, p.skillLine or 164, 0
end

-- Legacy Skill Lines API
_G.GetNumSkillLines = function()
    return #Mock.skillLines
end
_G.GetSkillLineInfo = function(index)
    local s = Mock.skillLines[index]
    if not s then return nil end
    return s.name, s.isHeader or false, true, s.rank or 1, 0, 0, s.maxRank or 300
end

-- Legacy TradeSkill Mock API
_G.GetTradeSkillLine = function()
    return Mock.tradeSkillLine, Mock.tradeSkillRank, Mock.tradeSkillMaxRank
end
_G.GetNumTradeSkills = function()
    return #Mock.tradeSkills
end
_G.GetTradeSkillInfo = function(index)
    local ts = Mock.tradeSkills[index]
    if not ts then return nil end
    return ts.name, ts.skillType or "optimal", 1, true
end
_G.GetTradeSkillItemLink = function(index)
    local ts = Mock.tradeSkills[index]
    if not ts then return nil end
    if not ts.outputItemId then return nil end
    return ts.outputLink or string.format("|cffffffff|Hitem:%d:0:0:0|h[%s]|h|r", ts.outputItemId, ts.name)
end
_G.GetTradeSkillNumMade = function(index)
    local ts = Mock.tradeSkills[index]
    if not ts then return 1, 1 end
    return ts.minMade or 1, ts.maxMade or ts.minMade or 1
end
_G.GetTradeSkillNumReagents = function(index)
    local ts = Mock.tradeSkills[index]
    return (ts and ts.reagents and #ts.reagents) or 0
end
_G.GetTradeSkillReagentInfo = function(index, rIndex)
    local ts = Mock.tradeSkills[index]
    local r = ts and ts.reagents and ts.reagents[rIndex]
    if not r then return nil end
    return r.name, nil, r.count, Mock.bagCounts[r.itemId] or 0
end
_G.GetTradeSkillReagentItemLink = function(index, rIndex)
    local ts = Mock.tradeSkills[index]
    local r = ts and ts.reagents and ts.reagents[rIndex]
    if not r then return nil end
    return r.link or string.format("|cffffffff|Hitem:%d:0:0:0|h[%s]|h|r", r.itemId, r.name or "Reagent")
end
_G.SelectTradeSkill = function(index)
    Mock.selectedTradeSkill = index
end
_G.DoTradeSkill = function(index, qty)
    Mock.craftedTradeSkill = { index = index, quantity = qty }
end
_G.CastSpellByName = function(spellName)
    table.insert(Mock.castSpells, spellName)
end

-- Modern C_TradeSkillUI Mock API
_G.C_TradeSkillUI = {
    IsTradeSkillReady = function() return true end,
    IsTradeSkillLinked = function() return false end,
    IsTradeSkillGuild = function() return false end,
    IsNPCCrafting = function() return false end,
    GetBaseProfessionInfo = function()
        return Mock.modernProfession
    end,
    GetChildProfessionInfo = function()
        return Mock.modernProfession
    end,
    GetAllRecipeIDs = function()
        local ids = {}
        for id in pairs(Mock.modernRecipes) do
            table.insert(ids, id)
        end
        table.sort(ids)
        return ids
    end,
    GetRecipeInfo = function(recipeID)
        local r = Mock.modernRecipes[recipeID]
        if not r then return nil end
        return {
            recipeID = recipeID,
            name = r.name,
            learned = (r.learned ~= false),
            itemID = r.outputItemID,
            difficulty = r.difficulty or "optimal",
            relativeDifficulty = r.relativeDifficulty or 1,
        }
    end,
    GetRecipeSchematic = function(recipeID)
        local r = Mock.modernRecipes[recipeID]
        if not r then return nil end
        local slots = {}
        for _, reg in ipairs(r.reagents or {}) do
            table.insert(slots, {
                quantityRequired = reg.qty or reg.count or 1,
                reagents = { { itemID = reg.itemID or reg.itemId } },
            })
        end
        return {
            recipeID = recipeID,
            name = r.name,
            outputItemID = r.outputItemID,
            quantityMin = r.quantityMin or 1,
            quantityMax = r.quantityMax or r.quantityMin or 1,
            reagentSlotSchematics = slots,
        }
    end,
    GetProfessionInfoByRecipeID = function(recipeID)
        local r = Mock.modernRecipes[recipeID]
        if r and r.skillLine then
            return {
                professionID = r.skillLine,
                parentProfessionID = r.skillLine,
                professionName = r.professionName or Mock.modernProfession.professionName,
                parentProfessionName = r.professionName or Mock.modernProfession.professionName,
                skillLevel = Mock.modernProfession.skillLevel,
                maxSkillLevel = Mock.modernProfession.maxSkillLevel,
            }
        end
        return Mock.modernProfession
    end,
    OpenTradeSkill = function(skillLineID)
        Mock.lastOpenedTradeSkill = skillLineID
        _G.ProfessionsFrame:Show()
        return true
    end,
    OpenRecipe = function(recipeID)
        Mock.lastOpenedRecipeId = recipeID
        _G.ProfessionsFrame:Show()
        return true
    end,
    CraftRecipe = function(recipeID, quantity)
        Mock.lastCraftedModern = { recipeID = recipeID, quantity = quantity or 1 }
        return true
    end,
}

-- Legacy Auction House Mock API
_G.CanSendAuctionQuery = function() return true end
_G.QueryAuctionItems = function(name)
    Mock.lastAuctionQuery = name
    Mock.currentAuctionResults = Mock.auctionListingsByQuery[name] or {}
    Mock.FireEvent("AUCTION_ITEM_LIST_UPDATE")
end
_G.GetNumAuctionItems = function()
    return #Mock.currentAuctionResults, #Mock.currentAuctionResults
end
_G.GetAuctionItemInfo = function(_, index)
    local row = Mock.currentAuctionResults[index]
    if not row then return nil end
    return row.name, nil, row.count or 1, 1, nil, 1, nil, row.minBid or row.buyoutPrice, 0, row.buyoutPrice, 0, nil, 0, "Seller", nil, 0, row.itemId
end
_G.SetSelectedAuctionItem = function(_, index)
    Mock.selectedAuctionIndex = index
end
_G.PlaceAuctionBid = function(listType, index, amount)
    table.insert(Mock.placedBids, { listType = listType, index = index, amount = amount })
end
_G.GetAuctionHouseDepositRate = function()
    return Mock.depositRate
end

-- Merchant Mock API
_G.GetMerchantNumItems = function()
    return #Mock.merchantItems
end
_G.GetMerchantItemInfo = function(index)
    local m = Mock.merchantItems[index]
    if not m then return nil end
    return m.name, nil, m.price, m.quantity or 1, m.numAvailable or -1
end
_G.GetMerchantItemLink = function(index)
    local m = Mock.merchantItems[index]
    if not m then return nil end
    return m.link or string.format("|cffffffff|Hitem:%d:0:0:0|h[%s]|h|r", m.itemId, m.name or "Item")
end

function Mock.Reset()
    Mock.currentTime = 1700000000.0
    Mock.playerMoney = 500000
    Mock.bagCounts = {}
    Mock.bankCounts = {}
    Mock.itemInfoDB = {}
    Mock.tradeSkills = {}
    Mock.tradeSkillLine = "Blacksmithing"
    Mock.tradeSkillRank = 1
    Mock.tradeSkillMaxRank = 75
    Mock.modernProfession = {
        professionID = 164,
        parentProfessionID = 164,
        professionName = "Blacksmithing",
        parentProfessionName = "Blacksmithing",
        skillLevel = 1,
        maxSkillLevel = 75,
    }
    Mock.modernRecipes = {}
    Mock.professions = {}
    Mock.skillLines = {}
    Mock.auctionListingsByQuery = {}
    Mock.commodityResults = {}
    Mock.itemSearchResults = {}
    Mock.currentAuctionResults = {}
    Mock.lastAuctionQuery = nil
    Mock.lastBrowseQuery = nil
    Mock.lastOpenedTradeSkill = nil
    Mock.lastOpenedRecipeId = nil
    Mock.lastCraftedModern = nil
    Mock.timers = {}
    Mock.castSpells = {}
    Mock.selectedTradeSkill = nil
    Mock.craftedTradeSkill = nil
    Mock.placedBids = {}
    Mock.merchantItems = {}
    Mock.depositRate = 5
    Mock.inCombat = false
    _G.AuctionFrame:Show()
    _G.TradeSkillFrame:Hide()
    _G.ProfessionsFrame:Hide()
end

return Mock
