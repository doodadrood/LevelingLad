local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.DetailWindow = {}

local detailFrame = nil
local currentPlay = nil
local shoppingRows = {}
local MAX_SHOPPING_ROWS = 20
local SCROLL_VIEWPORT_HEIGHT = 270
local SCROLL_STEP = 38
local CHECKMARK_ICON = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t "

local function SetBackdropSafe(frame, bgR, bgG, bgB, bgA)
    if not frame then return end
    if frame.CreateTexture and not frame._llBg then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        if bg.SetAllPoints then bg:SetAllPoints(frame) end
        if bg.SetColorTexture then
            bg:SetColorTexture(bgR or 0.05, bgG or 0.06, bgB or 0.08, bgA or 0.95)
        elseif bg.SetTexture then
            bg:SetTexture(bgR or 0.05, bgG or 0.06, bgB or 0.08, bgA or 0.95)
        end
        frame._llBg = bg
    end
end

local function SetRowBgColor(frame, r, g, b, a)
    if not frame or not frame._llBg then return end
    if frame._llBg.SetColorTexture then
        frame._llBg:SetColorTexture(r, g, b, a)
    elseif frame._llBg.SetTexture then
        frame._llBg:SetTexture(r, g, b, a)
    end
end

local function HandleItemLinkClick(itemId, itemName, itemLink, desiredQty)
    if _G.IsModifiedClick and _G.IsModifiedClick("CHATLINK") then
        if _G.ChatEdit_InsertLink and itemLink then
            if _G.ChatEdit_InsertLink(itemLink) then return end
        end
        if _G.BrowseName and _G.BrowseName.IsVisible and _G.BrowseName:IsVisible() then
            _G.BrowseName:SetText(itemName or "")
            return
        end
        if _G.AuctionHouseFrame and _G.AuctionHouseFrame.SearchBar and _G.AuctionHouseFrame.SearchBar.SearchBox then
            _G.AuctionHouseFrame.SearchBar.SearchBox:SetText(itemName or "")
            return
        end
    end

    if LL.AHVerifier and LL.AHVerifier.IsAuctionHouseOpen and LL.AHVerifier.IsAuctionHouseOpen() then
        LL.AHVerifier.SearchItemOnAH(itemId, itemName, itemLink, desiredQty)
    elseif _G.SetItemRef and itemLink then
        pcall(_G.SetItemRef, "item:" .. tostring(itemId), itemLink, "LeftButton")
    end
end

local function ShowItemTooltip(owner, itemId, itemLink, vendorHint)
    if not _G.GameTooltip then return end
    _G.GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    if itemLink and _G.GameTooltip.SetHyperlink then
        pcall(_G.GameTooltip.SetHyperlink, _G.GameTooltip, itemLink)
    elseif itemId and _G.GameTooltip.SetHyperlink then
        pcall(_G.GameTooltip.SetHyperlink, _G.GameTooltip, "item:" .. tostring(itemId))
    end
    _G.GameTooltip:AddLine(" ")
    if vendorHint then
        _G.GameTooltip:AddLine("|cff00ccffNPC Vendor Reagent:|r " .. vendorHint, 0.2, 0.9, 1)
    else
        _G.GameTooltip:AddLine("|cff00ff88Click:|r Search on Auction House", 0.8, 0.8, 0.8)
    end
    _G.GameTooltip:Show()
end

local function ApplyScrollOffset(offset)
    if not detailFrame or not detailFrame.scrollFrame then return end
    local sf = detailFrame.scrollFrame
    local maxScroll = sf._maxScroll or 0
    local clamped = math.max(0, math.min(maxScroll, offset or 0))
    sf._currentScroll = clamped
    if sf.SetVerticalScroll then
        pcall(sf.SetVerticalScroll, sf, clamped)
    end
    if detailFrame.scrollBar and detailFrame.scrollBar.SetValue then
        detailFrame._updatingScroll = true
        pcall(detailFrame.scrollBar.SetValue, detailFrame.scrollBar, clamped)
        detailFrame._updatingScroll = false
    end
end

local function OnMouseWheel(_, delta)
    if not detailFrame or not detailFrame.scrollFrame then return end
    local cur = detailFrame.scrollFrame._currentScroll or 0
    ApplyScrollOffset(cur - ((delta or 0) * SCROLL_STEP))
end

local function BindWheel(frame)
    if not frame then return end
    if frame.EnableMouseWheel then pcall(frame.EnableMouseWheel, frame, true) end
    if frame.SetScript then pcall(frame.SetScript, frame, "OnMouseWheel", OnMouseWheel) end
end

local function CreateShoppingRow(parent, index, anchorBelow)
    local row = CreateFrame("Frame", "LL_DetailRow" .. index, parent)
    if row.SetSize then row:SetSize(434, 54) end
    if row.SetPoint then
        if index == 1 then
            row:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -6)
        else
            row:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -5)
        end
    end
    SetBackdropSafe(row, 0.11, 0.13, 0.16, 0.92)
    BindWheel(row)

    local iconTex = row.CreateTexture and row:CreateTexture(nil, "ARTWORK")
    if iconTex then
        if iconTex.SetSize then iconTex:SetSize(28, 28) end
        if iconTex.SetPoint then iconTex:SetPoint("LEFT", row, "LEFT", 8, 0) end
    end

    local itemBtn = CreateFrame("Button", "LL_DetailRowItemBtn" .. index, row)
    if itemBtn.SetSize then itemBtn:SetSize(296, 16) end
    if itemBtn.SetPoint then itemBtn:SetPoint("TOPLEFT", row, "TOPLEFT", 42, -5) end
    BindWheel(itemBtn)

    local itemText = itemBtn.CreateFontString and itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if itemText then
        if itemText.SetPoint then itemText:SetPoint("LEFT", itemBtn, "LEFT", 0, 0) end
        if itemText.SetWidth then itemText:SetWidth(296) end
        if itemText.SetJustifyH then itemText:SetJustifyH("LEFT") end
        if itemText.SetWordWrap then pcall(itemText.SetWordWrap, itemText, false) end
    end

    local statusText = row.CreateFontString and row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if statusText then
        if statusText.SetPoint then statusText:SetPoint("TOPLEFT", itemBtn, "BOTTOMLEFT", 0, -3) end
        if statusText.SetWidth then statusText:SetWidth(296) end
        if statusText.SetJustifyH then statusText:SetJustifyH("LEFT") end
        if statusText.SetWordWrap then pcall(statusText.SetWordWrap, statusText, false) end
    end

    local priceText = row.CreateFontString and row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if priceText then
        if priceText.SetPoint then priceText:SetPoint("TOPLEFT", statusText, "BOTTOMLEFT", 0, -2) end
        if priceText.SetWidth then priceText:SetWidth(296) end
        if priceText.SetJustifyH then priceText:SetJustifyH("LEFT") end
        if priceText.SetWordWrap then pcall(priceText.SetWordWrap, priceText, false) end
    end

    local searchBtn = CreateFrame("Button", "LL_DetailRowSearchBtn" .. index, row, "UIPanelButtonTemplate")
    if searchBtn.SetSize then searchBtn:SetSize(84, 24) end
    if searchBtn.SetPoint then searchBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0) end
    if searchBtn.SetText then searchBtn:SetText("Search AH") end
    BindWheel(searchBtn)

    itemBtn:SetScript("OnClick", function()
        if row._itemData then
            local rem = math.max(1, row._itemData.remainingToBuy or row._itemData.totalQuantity or 1)
            HandleItemLinkClick(row._itemData.itemId, row._itemData.name, row._itemData.link, rem)
        elseif row._roadmapStep then
            LL.DetailWindow.ShowPlay(row._roadmapStep)
        end
    end)

    itemBtn:SetScript("OnEnter", function(self)
        if row._itemData then
            ShowItemTooltip(self, row._itemData.itemId, row._itemData.link, row._itemData.source == "Vendor" and row._itemData.vendorHint or nil)
        end
    end)

    itemBtn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    searchBtn:SetScript("OnClick", function()
        if row._itemData and row._itemData.source ~= "Vendor" then
            local rem = math.max(1, (row._itemData.remainingToBuy and row._itemData.remainingToBuy > 0) and row._itemData.remainingToBuy or row._itemData.totalQuantity or 1)
            LL.AHVerifier.SearchItemOnAH(row._itemData.itemId, row._itemData.name, row._itemData.link, rem)
        elseif row._roadmapStep then
            LL.DetailWindow.ShowPlay(row._roadmapStep)
        end
    end)

    row.iconTex = iconTex
    row.itemBtn = itemBtn
    row.itemText = itemText
    row.statusText = statusText
    row.priceText = priceText
    row.searchBtn = searchBtn
    return row
end

local function EnsureDetailFrame()
    if detailFrame then return detailFrame end

    detailFrame = CreateFrame("Frame", "LL_DetailWindow", _G.UIParent)
    if detailFrame.SetSize then detailFrame:SetSize(486, 520) end
    if detailFrame.SetPoint then detailFrame:SetPoint("CENTER", _G.UIParent, "CENTER", 200, 0) end
    if detailFrame.SetFrameStrata then detailFrame:SetFrameStrata("MEDIUM") end
    if detailFrame.SetToplevel then detailFrame:SetToplevel(true) end
    if detailFrame.SetMovable then detailFrame:SetMovable(true) end
    if detailFrame.EnableMouse then detailFrame:EnableMouse(true) end
    if detailFrame.RegisterForDrag then detailFrame:RegisterForDrag("LeftButton") end
    detailFrame:SetScript("OnDragStart", function(self)
        if self.StartMoving then self:StartMoving() end
    end)
    detailFrame:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    end)
    BindWheel(detailFrame)
    SetBackdropSafe(detailFrame, 0.05, 0.06, 0.09, 0.96)

    -- Header
    local headerText = detailFrame.CreateFontString and detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if headerText then
        if headerText.SetPoint then headerText:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 14, -12) end
        if headerText.SetText then headerText:SetText("|cff00ccffLeveling Lad|r — Shopping & Crafting Tracker") end
    end

    local closeBtn = CreateFrame("Button", "LL_DetailCloseBtn", detailFrame, "UIPanelCloseButton")
    if closeBtn.SetPoint then closeBtn:SetPoint("TOPRIGHT", detailFrame, "TOPRIGHT", -4, -4) end
    closeBtn:SetScript("OnClick", function()
        detailFrame:Hide()
    end)

    -- Recipe Title & Skill Range
    local titleText = detailFrame.CreateFontString and detailFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    if titleText then
        if titleText.SetPoint then titleText:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 14, -38) end
        if titleText.SetWidth then titleText:SetWidth(454) end
        if titleText.SetJustifyH then titleText:SetJustifyH("LEFT") end
    end

    -- Cost & Recovery Summary
    local metricsText = detailFrame.CreateFontString and detailFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if metricsText then
        if metricsText.SetPoint then metricsText:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 14, -62) end
        if metricsText.SetWidth then metricsText:SetWidth(454) end
        if metricsText.SetJustifyH then metricsText:SetJustifyH("LEFT") end
    end

    -- Smart Alert Banner (Goal Reached / Trainer Handoff / Price Spike)
    local alertBanner = CreateFrame("Frame", "LL_DetailAlertBanner", detailFrame)
    if alertBanner.SetSize then alertBanner:SetSize(458, 28) end
    if alertBanner.SetPoint then alertBanner:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 14, -96) end
    SetBackdropSafe(alertBanner, 0.08, 0.25, 0.14, 0.95)
    local alertText = alertBanner.CreateFontString and alertBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if alertText then
        if alertText.SetPoint then alertText:SetPoint("LEFT", alertBanner, "LEFT", 8, 0) end
        if alertText.SetWidth then alertText:SetWidth(442) end
        if alertText.SetJustifyH then alertText:SetJustifyH("LEFT") end
    end
    alertBanner.text = alertText
    alertBanner:Hide()

    -- Live Skill Progress Bar
    local progressBar = CreateFrame("StatusBar", "LL_DetailSkillProgressBar", detailFrame)
    if progressBar.SetSize then progressBar:SetSize(458, 18) end
    if progressBar.SetPoint then progressBar:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 14, -130) end
    if progressBar.SetStatusBarTexture then progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar") end
    if progressBar.SetStatusBarColor then progressBar:SetStatusBarColor(0.15, 0.72, 0.95, 0.95) end
    SetBackdropSafe(progressBar, 0.12, 0.14, 0.18, 0.95)

    local progressText = progressBar.CreateFontString and progressBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if progressText then
        if progressText.SetPoint then progressText:SetPoint("CENTER", progressBar, "CENTER", 0, 0) end
    end
    progressBar.text = progressText

    -- Scrollable Shopping List Area
    local scrollFrame = CreateFrame("ScrollFrame", "LL_DetailScrollFrame", detailFrame)
    if scrollFrame.SetSize then scrollFrame:SetSize(446, SCROLL_VIEWPORT_HEIGHT) end
    if scrollFrame.SetPoint then scrollFrame:SetPoint("TOPLEFT", detailFrame, "TOPLEFT", 14, -158) end
    if scrollFrame.SetClipsChildren then pcall(scrollFrame.SetClipsChildren, scrollFrame, true) end
    scrollFrame._currentScroll = 0
    scrollFrame._maxScroll = 0
    BindWheel(scrollFrame)

    local scrollChild = CreateFrame("Frame", "LL_DetailScrollChild", scrollFrame)
    if scrollChild.SetSize then scrollChild:SetSize(440, SCROLL_VIEWPORT_HEIGHT) end
    if scrollFrame.SetScrollChild then pcall(scrollFrame.SetScrollChild, scrollFrame, scrollChild) end
    BindWheel(scrollChild)

    local scrollBar = CreateFrame("Slider", "LL_DetailScrollBar", detailFrame)
    if scrollBar.SetSize then scrollBar:SetSize(10, SCROLL_VIEWPORT_HEIGHT) end
    if scrollBar.SetPoint then scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, 0) end
    if scrollBar.SetOrientation then pcall(scrollBar.SetOrientation, scrollBar, "VERTICAL") end
    if scrollBar.SetMinMaxValues then scrollBar:SetMinMaxValues(0, 0) end
    if scrollBar.SetValueStep then pcall(scrollBar.SetValueStep, scrollBar, 10) end
    if scrollBar.SetValue then scrollBar:SetValue(0) end
    SetBackdropSafe(scrollBar, 0.14, 0.16, 0.20, 0.90)
    scrollBar:SetScript("OnValueChanged", function(_, value)
        if not detailFrame._updatingScroll then
            ApplyScrollOffset(value)
        end
    end)

    local listHeader = scrollChild.CreateFontString and scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if listHeader then
        if listHeader.SetPoint then listHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, -2) end
        if listHeader.SetText then listHeader:SetText("|cff00ccffReagent Shopping List:|r (Need / Bags / Mail / To Buy)") end
    end

    local anchor = listHeader
    for i = 1, MAX_SHOPPING_ROWS do
        local r = CreateShoppingRow(scrollChild, i, anchor)
        r:Hide()
        shoppingRows[i] = r
        anchor = r
    end

    -- Footer Controls: Open Recipe, Craft All, Refresh
    local openRecipeBtn = CreateFrame("Button", "LL_DetailOpenRecipeBtn", detailFrame, "UIPanelButtonTemplate")
    if openRecipeBtn.SetSize then openRecipeBtn:SetSize(140, 26) end
    if openRecipeBtn.SetPoint then openRecipeBtn:SetPoint("BOTTOMLEFT", detailFrame, "BOTTOMLEFT", 14, 14) end
    if openRecipeBtn.SetText then openRecipeBtn:SetText("Open Recipe") end
    openRecipeBtn:SetScript("OnClick", function()
        local play = currentPlay
        if play and play.isRoadmap and play.steps and play.steps[1] then
            play = play.steps[1]
        end
        if play and play.recipe then
            LL.RecipeScanner.OpenRecipe(play.recipe)
        end
    end)

    local craftAllBtn = CreateFrame("Button", "LL_DetailCraftAllBtn", detailFrame, "UIPanelButtonTemplate")
    if craftAllBtn.SetSize then craftAllBtn:SetSize(160, 26) end
    if craftAllBtn.SetPoint then craftAllBtn:SetPoint("LEFT", openRecipeBtn, "RIGHT", 8, 0) end
    if craftAllBtn.SetText then craftAllBtn:SetText("Craft All") end
    craftAllBtn:SetScript("OnClick", function()
        local play = currentPlay
        if play and play.isRoadmap and play.steps and play.steps[1] then
            play = play.steps[1]
        end
        if not play or not play.recipe then return end
        local liveSkill = LL.RecipeScanner.GetProfessionSkill(play.skillLine or play.profession) or play.liveSkill or play.startSkill
        if play.targetSkill and liveSkill >= play.targetSkill then
            print(string.format("|cff00ff88[Leveling Lad]|r Goal reached (Skill %d / %d)! Stop crafting to save remaining mats.", liveSkill, play.targetSkill))
            LL.DetailWindow.RefreshIfShown()
            return
        end
        local remainingCrafts = LL.LevelingEngine.CalculateExpectedCrafts(play.recipe, liveSkill, play.targetSkill)
        local qty = math.max(1, math.min(remainingCrafts > 0 and remainingCrafts or play.expectedCrafts or 1, play.craftableNow > 0 and play.craftableNow or remainingCrafts or 1))
        LL.RecipeScanner.CraftRecipe(play.recipe, qty)
    end)

    local refreshBtn = CreateFrame("Button", "LL_DetailRefreshBtn", detailFrame, "UIPanelButtonTemplate")
    if refreshBtn.SetSize then refreshBtn:SetSize(134, 26) end
    if refreshBtn.SetPoint then refreshBtn:SetPoint("BOTTOMRIGHT", detailFrame, "BOTTOMRIGHT", -14, 14) end
    if refreshBtn.SetText then refreshBtn:SetText("Refresh Mats") end
    refreshBtn:SetScript("OnClick", function()
        LL.DetailWindow.RefreshIfShown()
    end)

    detailFrame.titleText = titleText
    detailFrame.metricsText = metricsText
    detailFrame.alertBanner = alertBanner
    detailFrame.progressBar = progressBar
    detailFrame.scrollFrame = scrollFrame
    detailFrame.scrollChild = scrollChild
    detailFrame.scrollBar = scrollBar
    detailFrame.listHeader = listHeader
    detailFrame.openRecipeBtn = openRecipeBtn
    detailFrame.craftAllBtn = craftAllBtn
    detailFrame.refreshBtn = refreshBtn

    detailFrame:Hide()
    LL.DetailWindow.frame = detailFrame
    return detailFrame
end

function LL.DetailWindow.ShowPlay(play)
    if type(play) ~= "table" then return end
    currentPlay = play
    if LevelingLad_DB then
        LevelingLad_DB.activePlay = play
    end
    local frame = EnsureDetailFrame()
    frame:Show()
    if frame.Raise then frame:Raise() end
    ApplyScrollOffset(0)
    LL.DetailWindow.RefreshIfShown()
end

function LL.DetailWindow.ShowRoadmap(roadmap)
    if type(roadmap) ~= "table" then return end
    LL.DetailWindow.ShowPlay(roadmap)
end

function LL.DetailWindow.ClearStalePlay(newGoal)
    if not currentPlay then return end
    local trackedGoal = currentPlay.goalTargetSkill or currentPlay.requestedTargetSkill or currentPlay.reachedSkill or currentPlay.targetSkill
    if not newGoal or trackedGoal ~= newGoal then
        currentPlay = nil
        if detailFrame and detailFrame.Hide then
            detailFrame:Hide()
        end
    end
end

function LL.DetailWindow.OnSkillUp(profName, newSkill, skillLine, goalReached)
    if not currentPlay then return end
    if currentPlay.skillLine == skillLine or currentPlay.profession == profName then
        currentPlay.liveSkill = newSkill
        if goalReached then
            currentPlay.goalReached = true
        end
        LL.DetailWindow.RefreshIfShown()
    end
end

function LL.DetailWindow.RefreshIfShown()
    if not detailFrame or (detailFrame.IsShown and not detailFrame:IsShown()) then
        return
    end
    local play = currentPlay or (LevelingLad_DB and LevelingLad_DB.activePlay)
    if not play then return end

    LL.LevelingEngine.ComputeLiveInventoryState(play)

    local apiSkill = LL.RecipeScanner.GetProfessionSkill(play.skillLine or play.profession)
    local liveSkill = math.max(tonumber(apiSkill) or 0, tonumber(play.liveSkill) or tonumber(play.startSkill) or 1)
    play.liveSkill = liveSkill

    if play.isRoadmap then
        if detailFrame.titleText then
            detailFrame.titleText:SetText(string.format(
                "|cff00ccff%s Roadmap:|r Skill %d -> %d (%d steps)",
                play.profession or "Profession",
                play.startSkill or 1,
                play.reachedSkill or 1,
                #(play.steps or {})
            ))
        end
        if detailFrame.metricsText then
            detailFrame.metricsText:SetText(string.format(
                "Gross Mats: %s  |  Recovery: %s  |  Net Cost: %s  |  Avg: %s/pt",
                LL.Formatter.FormatMoney(play.totalGrossCost),
                LL.Formatter.FormatMoney(play.totalRecovery),
                LL.Formatter.FormatNetCost(play.totalNetCost),
                LL.Formatter.FormatNetCost(math.floor((play.avgCPSP or 0) + 0.5), true)
            ))
        end
    else
        local badge = LL.Formatter.FormatDifficultyBadge(play.startDifficulty, play.endDifficulty)
        local verTag = play.verified and "|cff00ff00[Verified]|r" or "|cffffcc00[Cached]|r"
        if detailFrame.titleText then
            detailFrame.titleText:SetText(string.format(
                "%s  %dx (%d->%d)  %s %s",
                play.outputLink or play.recipeName or "Recipe",
                play.expectedCrafts or 0,
                play.startSkill or 1,
                play.targetSkill or 1,
                badge,
                verTag
            ))
        end
        if detailFrame.metricsText then
            detailFrame.metricsText:SetText(string.format(
                "Gross: %s  |  Recovery (%s): %s  |  Net: %s  |  CPSP: %s/pt",
                LL.Formatter.FormatMoney(play.grossMatCost),
                play.recoveryMode or "VENDOR",
                LL.Formatter.FormatMoney(play.totalRecovery),
                LL.Formatter.FormatNetCost(play.netCost),
                LL.Formatter.FormatNetCost(play.cpspRounded or play.cpsp, true)
            ))
        end
    end

    -- Alert Banner (Smart Abort / Trainer Handoff / Circuit Breaker / Budget Exhausted)
    local targetSkill = play.isRoadmap and play.reachedSkill or play.targetSkill or liveSkill
    local startSkill = play.startSkill or 1
    local goalReached = (liveSkill >= targetSkill and targetSkill > startSkill) or (play.goalReached == true)

    if detailFrame.alertBanner then
        if goalReached then
            SetRowBgColor(detailFrame.alertBanner, 0.08, 0.34, 0.16, 0.96)
            detailFrame.alertBanner.text:SetText(string.format("|cff00ff88Goal reached (Skill %d)! Stop crafting to save remaining mats.|r", liveSkill))
            detailFrame.alertBanner:Show()
        elseif play.circuitBreakerNotice then
            SetRowBgColor(detailFrame.alertBanner, 0.36, 0.14, 0.10, 0.96)
            detailFrame.alertBanner.text:SetText("|cffff6644AH Spike Alert:|r " .. play.circuitBreakerNotice)
            detailFrame.alertBanner:Show()
        elseif play.handoff then
            SetRowBgColor(detailFrame.alertBanner, 0.28, 0.20, 0.07, 0.96)
            detailFrame.alertBanner.text:SetText(string.format(
                "|cffffcc00Stop at Skill %d!|r Visit %s for |cff00ccff[%s]|r (cheaper than continuing).",
                play.handoff.atSkill,
                play.handoff.source or "Trainer",
                play.handoff.nextRecipeName or "Next Recipe"
            ))
            detailFrame.alertBanner:Show()
        elseif play.budgetExhausted or play.budgetCapped then
            SetRowBgColor(detailFrame.alertBanner, 0.30, 0.18, 0.08, 0.96)
            detailFrame.alertBanner.text:SetText("|cffffaa00Budget Cap Active:|r Capped craft count to stay strictly within your gold budget.")
            detailFrame.alertBanner:Show()
        else
            detailFrame.alertBanner:Hide()
        end
    end

    -- Progress Bar
    if detailFrame.progressBar then
        local totalDelta = math.max(1, targetSkill - startSkill)
        local gained = math.max(0, math.min(totalDelta, liveSkill - startSkill))
        detailFrame.progressBar:SetMinMaxValues(0, totalDelta)
        detailFrame.progressBar:SetValue(gained)
        if detailFrame.progressBar.text then
            detailFrame.progressBar.text:SetText(string.format(
                "Skill Progress: %d / %d  (+%d / +%d pts)",
                liveSkill, targetSkill, gained, totalDelta
            ))
        end
    end

    -- Build display rows (Roadmap steps followed by shopping list, or direct shopping list)
    local entries = {}
    if play.isRoadmap and type(play.steps) == "table" then
        for _, step in ipairs(play.steps) do
            table.insert(entries, { kind = "STEP", step = step })
        end
    end
    for _, item in ipairs(play.shoppingList or {}) do
        table.insert(entries, { kind = "SHOP", item = item })
    end

    local visibleRows = 0
    for i = 1, MAX_SHOPPING_ROWS do
        local row = shoppingRows[i]
        local entry = entries[i]
        if entry and entry.kind == "SHOP" then
            visibleRows = visibleRows + 1
            local item = entry.item
            row._itemData = item
            row._roadmapStep = nil
            row:Show()

            if row.iconTex and row.iconTex.SetTexture then
                row.iconTex:SetTexture(item.icon or LL.Formatter.GetItemIcon(item.itemId))
            end

            local need = item.totalQuantity or 0
            local bags = item.haveInBags or 0
            local mail = item.inMail or 0
            local toBuy = item.remainingToBuy or math.max(0, need - bags - mail)
            local isReady = (toBuy <= 0)

            if isReady then
                SetRowBgColor(row, 0.07, 0.22, 0.13, 0.92)
            elseif mail > 0 then
                SetRowBgColor(row, 0.09, 0.16, 0.22, 0.92)
            else
                SetRowBgColor(row, 0.11, 0.13, 0.16, 0.92)
            end

            local prefix = isReady and CHECKMARK_ICON or ""
            local srcTag = (item.source == "Vendor") and "|cff00ccff[Vendor]|r" or "|cffffaa00[AH]|r"
            if row.itemText then
                row.itemText:SetText(string.format("%s%s %s", prefix, srcTag, item.link or item.name))
            end

            local statusColor = isReady and "|cff00ff88" or "|cffffcc00"
            if row.statusText then
                row.statusText:SetText(string.format(
                    "%sNeed: %d | Bags: %d | Mail: %d | Buy: %d|r",
                    statusColor, need, bags, mail, toBuy
                ))
            end

            if row.priceText then
                if item.source == "Vendor" then
                    row.priceText:SetText(string.format(
                        "|cff88ddffNPC: %s ea (Total: %s) — %s|r",
                        LL.Formatter.FormatMoney(item.avgUnitPrice, true),
                        LL.Formatter.FormatMoney(item.totalCost, true),
                        item.vendorHint or "Trade Vendor"
                    ))
                elseif item.minUnitPrice ~= item.maxUnitPrice then
                    row.priceText:SetText(string.format(
                        "|cffccccccAH Tiers: %s–%s ea (Avg %s | Total: %s)|r",
                        LL.Formatter.FormatMoney(item.minUnitPrice, true),
                        LL.Formatter.FormatMoney(item.maxUnitPrice, true),
                        LL.Formatter.FormatMoney(item.avgUnitPrice, true),
                        LL.Formatter.FormatMoney(item.totalCost, true)
                    ))
                else
                    row.priceText:SetText(string.format(
                        "|cffccccccAH: %s ea (Total: %s)|r",
                        LL.Formatter.FormatMoney(item.avgUnitPrice, true),
                        LL.Formatter.FormatMoney(item.totalCost, true)
                    ))
                end
            end

            if row.searchBtn then
                if item.source == "Vendor" then
                    row.searchBtn:Hide()
                else
                    row.searchBtn:Show()
                    row.searchBtn:SetText("Search AH")
                end
            end
        elseif entry and entry.kind == "STEP" then
            visibleRows = visibleRows + 1
            local step = entry.step
            row._itemData = nil
            row._roadmapStep = step
            row:Show()
            SetRowBgColor(row, 0.09, 0.14, 0.22, 0.94)

            if row.iconTex and row.iconTex.SetTexture then
                row.iconTex:SetTexture(step.icon or LL.Formatter.GetItemIcon(step.outputItemId))
            end
            local badge = LL.Formatter.FormatDifficultyBadge(step.startDifficulty, step.endDifficulty)
            if row.itemText then
                row.itemText:SetText(string.format("|cff00ccffStep %d:|r %s %s", step.stepNumber or 1, step.outputLink or step.recipeName, badge))
            end
            if row.statusText then
                row.statusText:SetText(string.format(
                    "Skill %d -> %d  |  Craft %dx  |  Net: %s (%s/pt)",
                    step.startSkill, step.targetSkill, step.expectedCrafts,
                    LL.Formatter.FormatNetCost(step.netCost, true),
                    LL.Formatter.FormatNetCost(step.cpspRounded, true)
                ))
            end
            if row.priceText then
                local srcNote = step.needsTrainer and "|cff00ccffVisit Trainer to learn|r" or "|cffaaaaaaReady to craft|r"
                row.priceText:SetText(srcNote)
            end
            if row.searchBtn then
                row.searchBtn:Show()
                row.searchBtn:SetText("Inspect")
            end
        else
            row._itemData = nil
            row._roadmapStep = nil
            row:Hide()
        end
    end

    local contentHeight = math.max(SCROLL_VIEWPORT_HEIGHT, 28 + (visibleRows * 59))
    if detailFrame.scrollChild and detailFrame.scrollChild.SetHeight then
        detailFrame.scrollChild:SetHeight(contentHeight)
    end
    local maxScroll = math.max(0, contentHeight - SCROLL_VIEWPORT_HEIGHT)
    detailFrame.scrollFrame._maxScroll = maxScroll
    if detailFrame.scrollBar then
        detailFrame.scrollBar:SetMinMaxValues(0, maxScroll)
        if maxScroll > 0 then detailFrame.scrollBar:Show() else detailFrame.scrollBar:Hide() end
    end

    if detailFrame.craftAllBtn then
        if goalReached then
            detailFrame.craftAllBtn:SetText("Goal Reached!")
        else
            local targetPlay = (play.isRoadmap and play.steps and play.steps[1]) or play
            local remCrafts = (targetPlay.recipe and LL.LevelingEngine.CalculateExpectedCrafts(targetPlay.recipe, liveSkill, targetPlay.targetSkill)) or targetPlay.expectedCrafts or 1
            detailFrame.craftAllBtn:SetText(string.format("Craft All (%dx)", math.max(1, remCrafts)))
        end
    end
end

function LL.DetailWindow.Init()
    if LL.DetailWindow._initialized then return end
    LL.DetailWindow._initialized = true

    local evFrame = CreateFrame("Frame")
    if evFrame and evFrame.RegisterEvent then
        pcall(evFrame.RegisterEvent, evFrame, "BAG_UPDATE")
        pcall(evFrame.RegisterEvent, evFrame, "BAG_UPDATE_DELAYED")
        pcall(evFrame.RegisterEvent, evFrame, "MAIL_INBOX_UPDATE")
        evFrame:SetScript("OnEvent", function()
            LL.DetailWindow.RefreshIfShown()
        end)
    end
    LL.DetailWindow.eventFrame = evFrame
end
