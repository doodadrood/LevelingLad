local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.SideWindow = {}

local sideFrame = nil
local eventFrame = CreateFrame("Frame")
local playButtons = {}
local TOP_ROWS = 5

local RECOVERY_CYCLE = { "VENDOR", "AH", "NONE" }
local RECOVERY_LABELS = {
    VENDOR = "Recovery: Vendor",
    AH     = "Recovery: AH",
    NONE   = "Recovery: None",
}

local function SetBackdropSafe(frame, bgR, bgG, bgB, bgA)
    if not frame then return end
    if frame.CreateTexture and not frame._llBg then
        local bg = frame:CreateTexture(nil, "BACKGROUND")
        if bg.SetAllPoints then bg:SetAllPoints(frame) end
        if bg.SetColorTexture then
            bg:SetColorTexture(bgR or 0.05, bgG or 0.06, bgB or 0.09, bgA or 0.95)
        elseif bg.SetTexture then
            bg:SetTexture(bgR or 0.05, bgG or 0.06, bgB or 0.09, bgA or 0.95)
        end
        frame._llBg = bg
    end
end

local function SetBtnBgColor(frame, r, g, b, a)
    if not frame or not frame._llBg then return end
    if frame._llBg.SetColorTexture then
        frame._llBg:SetColorTexture(r, g, b, a)
    elseif frame._llBg.SetTexture then
        frame._llBg:SetTexture(r, g, b, a)
    end
end

local function AnchorToAuctionHouse()
    if not sideFrame or not sideFrame.SetPoint then return end
    local ahParent = _G.AuctionHouseFrame or _G.AuctionFrame
    if ahParent and (not ahParent.IsShown or ahParent:IsShown()) then
        if sideFrame.ClearAllPoints then sideFrame:ClearAllPoints() end
        sideFrame:SetPoint("TOPLEFT", ahParent, "TOPRIGHT", 6, 0)
    end
end

local function CreatePlayRowButton(parent, index, yOffset)
    local btn = CreateFrame("Button", "LL_SidePlayBtn" .. index, parent)
    if btn.SetSize then btn:SetSize(346, 52) end
    if btn.SetPoint then btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset) end
    SetBackdropSafe(btn, 0.11, 0.13, 0.17, 0.92)

    local mainText = btn.CreateFontString and btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if mainText then
        if mainText.SetPoint then mainText:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -6) end
        if mainText.SetWidth then mainText:SetWidth(330) end
        if mainText.SetJustifyH then mainText:SetJustifyH("LEFT") end
        if mainText.SetWordWrap then pcall(mainText.SetWordWrap, mainText, false) end
    end

    local subText = btn.CreateFontString and btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if subText then
        if subText.SetPoint then subText:SetPoint("TOPLEFT", mainText, "BOTTOMLEFT", 0, -4) end
        if subText.SetWidth then subText:SetWidth(330) end
        if subText.SetJustifyH then subText:SetJustifyH("LEFT") end
        if subText.SetWordWrap then pcall(subText.SetWordWrap, subText, false) end
    end

    local extraText = btn.CreateFontString and btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if extraText then
        if extraText.SetPoint then extraText:SetPoint("TOPLEFT", subText, "BOTTOMLEFT", 0, -2) end
        if extraText.SetWidth then extraText:SetWidth(330) end
        if extraText.SetJustifyH then extraText:SetJustifyH("LEFT") end
        if extraText.SetWordWrap then pcall(extraText.SetWordWrap, extraText, false) end
    end

    btn:SetScript("OnClick", function()
        if btn._play then
            LL.DetailWindow.ShowPlay(btn._play)
        elseif btn._needsAHScan then
            LL.SideWindow.TriggerAHScan()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        if btn._play then
            local p = btn._play
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:AddLine(p.summaryLine or p.recipeName, 0, 0.85, 1)
            _G.GameTooltip:AddLine(string.format("Craft %dx -> Skill %d to %d (+%d pts)", p.expectedCrafts, p.startSkill, p.targetSkill, p.pointsGained), 1, 1, 1)
            _G.GameTooltip:AddLine(string.format("Gross Mats: %s | Recovery: %s | Net: %s",
                LL.Formatter.FormatMoney(p.grossMatCost),
                LL.Formatter.FormatMoney(p.totalRecovery),
                LL.Formatter.FormatNetCost(p.netCost)
            ), 0.9, 0.9, 0.9)
            if p.handoff then
                _G.GameTooltip:AddLine(string.format("|cffffcc00Stops at %d -> Trainer [%s]|r", p.handoff.atSkill, p.handoff.nextRecipeName), 1, 0.85, 0.2)
            end
            _G.GameTooltip:AddLine(" ")
            _G.GameTooltip:AddLine("|cff00ff88Click to open Shopping List & Craft Launcher|r", 0.2, 1, 0.6)
            _G.GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    btn.mainText = mainText
    btn.subText = subText
    btn.extraText = extraText
    return btn
end

local function CycleProfession()
    local learned = LL.RecipeScanner.GetCharacterProfessions()
    local list = (#learned > 0) and learned or LL.RecipeDatabase.GetSupportedProfessions()
    if #list == 0 then return end

    local active = LL.RecipeScanner.GetActiveProfession()
    local nextIdx = 1
    for i, entry in ipairs(list) do
        if entry.skillLine == active.skillLine then
            nextIdx = (i % #list) + 1
            break
        end
    end

    LevelingLad_DB.settings.selectedProfession = list[nextIdx].skillLine
    LL.SideWindow.RunSearch()
end

local function CycleRecoveryMode()
    local cur = (LevelingLad_DB.settings.recoveryMode or "VENDOR"):upper()
    local nextMode = "VENDOR"
    for i, m in ipairs(RECOVERY_CYCLE) do
        if m == cur then
            nextMode = RECOVERY_CYCLE[(i % #RECOVERY_CYCLE) + 1]
            break
        end
    end
    LevelingLad_DB.settings.recoveryMode = nextMode
    LL.SideWindow.RunSearch()
end

local function EnsureSideWindow()
    if sideFrame then return sideFrame end

    sideFrame = CreateFrame("Frame", "LL_SideWindow", _G.UIParent)
    if sideFrame.SetSize then sideFrame:SetSize(370, 520) end
    if sideFrame.SetPoint then sideFrame:SetPoint("CENTER", _G.UIParent, "CENTER", -220, 0) end
    if sideFrame.SetFrameStrata then sideFrame:SetFrameStrata("MEDIUM") end
    if sideFrame.SetToplevel then sideFrame:SetToplevel(true) end
    if sideFrame.SetMovable then sideFrame:SetMovable(true) end
    if sideFrame.EnableMouse then sideFrame:EnableMouse(true) end
    if sideFrame.RegisterForDrag then sideFrame:RegisterForDrag("LeftButton") end
    sideFrame:SetScript("OnDragStart", function(self)
        if self.StartMoving then self:StartMoving() end
    end)
    sideFrame:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    end)
    SetBackdropSafe(sideFrame, 0.05, 0.06, 0.09, 0.95)

    -- Title Bar
    local title = sideFrame.CreateFontString and sideFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if title then
        if title.SetPoint then title:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -12) end
        if title.SetText then title:SetText("|cff00ccffLeveling Lad|r |cff88ccff(LL)|r — Cheapest Leveling") end
    end

    local closeBtn = CreateFrame("Button", "LL_SideCloseBtn", sideFrame, "UIPanelCloseButton")
    if closeBtn.SetPoint then closeBtn:SetPoint("TOPRIGHT", sideFrame, "TOPRIGHT", -4, -4) end
    closeBtn:SetScript("OnClick", function()
        sideFrame:Hide()
    end)

    -- Row 1: Profession Selector + Current Skill Rank Indicator
    local profBtn = CreateFrame("Button", "LL_SideProfBtn", sideFrame, "UIPanelButtonTemplate")
    if profBtn.SetSize then profBtn:SetSize(210, 24) end
    if profBtn.SetPoint then profBtn:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -38) end
    profBtn:SetScript("OnClick", CycleProfession)

    local recoveryBtn = CreateFrame("Button", "LL_SideRecoveryBtn", sideFrame, "UIPanelButtonTemplate")
    if recoveryBtn.SetSize then recoveryBtn:SetSize(130, 24) end
    if recoveryBtn.SetPoint then recoveryBtn:SetPoint("LEFT", profBtn, "RIGHT", 6, 0) end
    recoveryBtn:SetScript("OnClick", CycleRecoveryMode)

    -- Row 2: Target Goal Selector (+5 pts | Next Tier | Custom)
    local targetPlus5Btn = CreateFrame("Button", "LL_SideTargetPlus5Btn", sideFrame)
    if targetPlus5Btn.SetSize then targetPlus5Btn:SetSize(84, 22) end
    if targetPlus5Btn.SetPoint then targetPlus5Btn:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -68) end
    SetBackdropSafe(targetPlus5Btn, 0.14, 0.16, 0.20, 0.92)
    targetPlus5Btn:SetScript("OnClick", function()
        LevelingLad_DB.settings.targetMode = "PLUS5"
        LevelingLad_DB.settings.targetSkillRank = 0
        LL.SideWindow.RunSearch()
    end)

    local targetMilestoneBtn = CreateFrame("Button", "LL_SideTargetMilestoneBtn", sideFrame)
    if targetMilestoneBtn.SetSize then targetMilestoneBtn:SetSize(128, 22) end
    if targetMilestoneBtn.SetPoint then targetMilestoneBtn:SetPoint("LEFT", targetPlus5Btn, "RIGHT", 6, 0) end
    SetBackdropSafe(targetMilestoneBtn, 0.10, 0.30, 0.42, 0.95)
    targetMilestoneBtn:SetScript("OnClick", function()
        LevelingLad_DB.settings.targetMode = "MILESTONE"
        LevelingLad_DB.settings.targetSkillRank = 0
        LL.SideWindow.RunSearch()
    end)

    local targetCustomInput = CreateFrame("EditBox", "LL_SideCustomTargetInput", sideFrame, "InputBoxTemplate")
    if targetCustomInput.SetSize then targetCustomInput:SetSize(52, 22) end
    if targetCustomInput.SetPoint then targetCustomInput:SetPoint("LEFT", targetMilestoneBtn, "RIGHT", 10, 0) end
    if targetCustomInput.SetAutoFocus then targetCustomInput:SetAutoFocus(false) end
    targetCustomInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val > 1 and val <= 300 then
            LevelingLad_DB.settings.targetMode = "CUSTOM"
            LevelingLad_DB.settings.customTargetSkill = math.floor(val)
            LevelingLad_DB.settings.targetSkillRank = math.floor(val)
            LL.SideWindow.RunSearch()
        end
        if self.ClearFocus then self:ClearFocus() end
    end)

    local targetApplyBtn = CreateFrame("Button", "LL_SideCustomTargetApply", sideFrame, "UIPanelButtonTemplate")
    if targetApplyBtn.SetSize then targetApplyBtn:SetSize(64, 22) end
    if targetApplyBtn.SetPoint then targetApplyBtn:SetPoint("LEFT", targetCustomInput, "RIGHT", 4, 0) end
    if targetApplyBtn.SetText then targetApplyBtn:SetText("Set Goal") end
    targetApplyBtn:SetScript("OnClick", function()
        local val = tonumber(targetCustomInput:GetText())
        if val and val > 1 and val <= 300 then
            LevelingLad_DB.settings.targetMode = "CUSTOM"
            LevelingLad_DB.settings.customTargetSkill = math.floor(val)
            LevelingLad_DB.settings.targetSkillRank = math.floor(val)
            LL.SideWindow.RunSearch()
        end
    end)

    -- Row 3: Budget Input + Apply
    local budgetLabel = sideFrame.CreateFontString and sideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if budgetLabel then
        if budgetLabel.SetPoint then budgetLabel:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -98) end
        if budgetLabel.SetText then budgetLabel:SetText("Budget:") end
    end

    local budgetInput = CreateFrame("EditBox", "LL_SideBudgetInput", sideFrame, "InputBoxTemplate")
    if budgetInput.SetSize then budgetInput:SetSize(96, 22) end
    if budgetInput.SetPoint then budgetInput:SetPoint("LEFT", budgetLabel, "RIGHT", 10, 0) end
    if budgetInput.SetAutoFocus then budgetInput:SetAutoFocus(false) end
    budgetInput:SetScript("OnEnterPressed", function(self)
        LL.SideWindow.SetBudget(self:GetText())
        if self.ClearFocus then self:ClearFocus() end
    end)

    local budgetApplyBtn = CreateFrame("Button", "LL_SideBudgetApplyBtn", sideFrame, "UIPanelButtonTemplate")
    if budgetApplyBtn.SetSize then budgetApplyBtn:SetSize(74, 22) end
    if budgetApplyBtn.SetPoint then budgetApplyBtn:SetPoint("LEFT", budgetInput, "RIGHT", 6, 0) end
    if budgetApplyBtn.SetText then budgetApplyBtn:SetText("Apply") end
    budgetApplyBtn:SetScript("OnClick", function()
        LL.SideWindow.SetBudget(budgetInput:GetText())
    end)

    local budgetInfoText = sideFrame.CreateFontString and sideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if budgetInfoText then
        if budgetInfoText.SetPoint then budgetInfoText:SetPoint("LEFT", budgetApplyBtn, "RIGHT", 8, 0) end
    end

    -- Row 4: Find Cheapest Plays Button + Roadmap Button + Progress Bar
    local findBtn = CreateFrame("Button", "LL_SideFindBtn", sideFrame, "UIPanelButtonTemplate")
    if findBtn.SetSize then findBtn:SetSize(206, 26) end
    if findBtn.SetPoint then findBtn:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -126) end
    if findBtn.SetText then findBtn:SetText("Find Top 5 Plays") end
    findBtn:SetScript("OnClick", function()
        if LL.AHVerifier.IsRunning() then
            LL.AHVerifier.Stop("USER_STOP")
        else
            LL.SideWindow.RunSearch()
        end
    end)

    local roadmapBtn = CreateFrame("Button", "LL_SideRoadmapBtn", sideFrame, "UIPanelButtonTemplate")
    if roadmapBtn.SetSize then roadmapBtn:SetSize(134, 26) end
    if roadmapBtn.SetPoint then roadmapBtn:SetPoint("LEFT", findBtn, "RIGHT", 6, 0) end
    if roadmapBtn.SetText then roadmapBtn:SetText("Milestone Path") end
    roadmapBtn:SetScript("OnClick", function()
        local active = LL.RecipeScanner.GetActiveProfession()
        local target = LL.GetTargetSkill(active.rank, active.maxRank)
        local roadmap = LL.LevelingEngine.PlanMilestonePath(active.skillLine, active.rank, target)
        LevelingLad_DB.lastRoadmap = roadmap
        LL.DetailWindow.ShowRoadmap(roadmap)
    end)

    local statusBar = CreateFrame("StatusBar", "LL_SideStatusBar", sideFrame)
    if statusBar.SetSize then statusBar:SetSize(346, 16) end
    if statusBar.SetPoint then statusBar:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -158) end
    if statusBar.SetStatusBarTexture then statusBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar") end
    if statusBar.SetStatusBarColor then statusBar:SetStatusBarColor(0.10, 0.65, 0.90, 0.90) end
    SetBackdropSafe(statusBar, 0.12, 0.14, 0.18, 0.92)

    local statusText = statusBar.CreateFontString and statusBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if statusText then
        if statusText.SetPoint then statusText:SetPoint("CENTER", statusBar, "CENTER", 0, 0) end
    end

    local subBanner = sideFrame.CreateFontString and sideFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if subBanner then
        if subBanner.SetPoint then subBanner:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -182) end
        if subBanner.SetText then subBanner:SetText("Top 5 Cheapest Leveling Plays (click to open Shopping List):") end
    end

    for i = 1, TOP_ROWS do
        local yOff = -202 - ((i - 1) * 58)
        local btn = CreatePlayRowButton(sideFrame, i, yOff)
        btn:Hide()
        playButtons[i] = btn
    end

    sideFrame.profBtn = profBtn
    sideFrame.recoveryBtn = recoveryBtn
    sideFrame.targetPlus5Btn = targetPlus5Btn
    sideFrame.targetMilestoneBtn = targetMilestoneBtn
    sideFrame.targetCustomInput = targetCustomInput
    sideFrame.budgetInput = budgetInput
    sideFrame.budgetInfoText = budgetInfoText
    sideFrame.findBtn = findBtn
    sideFrame.roadmapBtn = roadmapBtn
    sideFrame.statusBar = statusBar
    sideFrame.statusText = statusText
    sideFrame.subBanner = subBanner
    sideFrame.playButtons = playButtons

    sideFrame:Hide()
    LL.SideWindow.frame = sideFrame
    return sideFrame
end

function LL.SideWindow.SetBudget(input)
    local parsed = LL.ParseGoldToCopper(input)
    if parsed == nil then
        print("|cffff5555[Leveling Lad]|r Invalid budget. Try '10g', '25g 50s', or 'auto'.")
        return false
    end
    LevelingLad_DB.settings.budgetCopper = parsed
    if parsed == 0 then
        print("|cff00ccff[Leveling Lad]|r Budget set to All Character Gold.")
    else
        print(string.format("|cff00ccff[Leveling Lad]|r Max budget cap set to %s.", LL.Formatter.FormatMoney(parsed)))
    end
    LL.SideWindow.RunSearch()
    return true
end

function LL.SideWindow.TriggerAHScan()
    if not LL.AHVerifier.IsAuctionHouseOpen() then
        print("|cffffcc00[Leveling Lad]|r Open the Auction House at any Auctioneer first, then click 'Scan AH Now'.")
        return false
    end
    if _G.PCF and _G.PCF.Scanner and type(_G.PCF.Scanner.StartScan) == "function" then
        _G.PCF.Scanner.StartScan()
        LL.SideWindow.Refresh()
        return true
    end
    print("|cffff5555[Leveling Lad]|r PriceCheckerForever scanner not ready. Open AH and try /reload.")
    return false
end

function LL.SideWindow.UpdateProgress(idx, total, targetItem)
    if not sideFrame then return end
    if sideFrame.findBtn then sideFrame.findBtn:SetText("Stop Verification") end
    if sideFrame.statusBar and total and total > 0 then
        sideFrame.statusBar:SetMinMaxValues(0, total)
        sideFrame.statusBar:SetValue(idx)
    end
    if sideFrame.statusText then
        sideFrame.statusText:SetText(string.format("Verifying %d/%d: %s", idx or 0, total or 0, (targetItem and targetItem.name) or "AH"))
    end
end

function LL.SideWindow.Refresh()
    local frame = EnsureSideWindow()
    local active = LL.RecipeScanner.GetActiveProfession()
    local nextTier = LL.GetNextMilestone(active.rank, active.maxRank)
    local effectiveBudget, isCapped = LL.GetEffectiveBudget()
    local mode = (LevelingLad_DB.settings.targetMode or "MILESTONE"):upper()
    local recovery = (LevelingLad_DB.settings.recoveryMode or "VENDOR"):upper()

    if frame.profBtn then
        frame.profBtn:SetText(string.format("%s: %d / %d", active.name or "Blacksmithing", active.rank or 1, active.maxRank or 75))
    end
    if frame.recoveryBtn then
        frame.recoveryBtn:SetText(RECOVERY_LABELS[recovery] or "Recovery: Vendor")
    end
    if frame.targetPlus5Btn then
        frame.targetPlus5Btn:SetText(mode == "PLUS5" and "|cff00ff88[+5 Points]|r" or "|cffaaaaaa[+5 Points]|r")
        SetBtnBgColor(frame.targetPlus5Btn, mode == "PLUS5" and 0.08 or 0.14, mode == "PLUS5" and 0.32 or 0.16, mode == "PLUS5" and 0.24 or 0.20, 0.94)
    end
    if frame.targetMilestoneBtn then
        local lbl = string.format("Next Tier: %d", nextTier)
        frame.targetMilestoneBtn:SetText(mode == "MILESTONE" and ("|cff00ff88[" .. lbl .. "]|r") or ("|cffaaaaaa[" .. lbl .. "]|r"))
        SetBtnBgColor(frame.targetMilestoneBtn, mode == "MILESTONE" and 0.08 or 0.14, mode == "MILESTONE" and 0.32 or 0.16, mode == "MILESTONE" and 0.24 or 0.20, 0.94)
    end
    if frame.budgetInfoText then
        frame.budgetInfoText:SetText(isCapped
            and ("Cap: " .. LL.Formatter.FormatMoneyShort(effectiveBudget))
            or ("All: " .. LL.Formatter.FormatMoneyShort(effectiveBudget)))
    end

    local dataStatus = LL.GetAHDataStatus and LL.GetAHDataStatus() or "FRESH"
    if not LL.AHVerifier.IsRunning() then
        if dataStatus == "NO_DATA" then
            frame.findBtn:SetText(LL.AHVerifier.IsAuctionHouseOpen() and "Scan AH Now" or "AH Scan Needed")
            frame.statusText:SetText("No AH scan data")
            frame.statusBar:SetMinMaxValues(0, 1)
            frame.statusBar:SetValue(0)
        else
            frame.findBtn:SetText("Find Top 5 Plays")
            local count = (LevelingLad_DB.lastTopPlays and #LevelingLad_DB.lastTopPlays) or 0
            frame.statusText:SetText(string.format("Top %d Ready (Target: %d)", count, LL.GetTargetSkill(active.rank, active.maxRank)))
            frame.statusBar:SetMinMaxValues(0, 1)
            frame.statusBar:SetValue(1)
        end
    end

    local plays = (LevelingLad_DB and LevelingLad_DB.lastTopPlays) or {}
    for i = 1, TOP_ROWS do
        local btn = playButtons[i]
        local play = plays[i]
        if play then
            btn._play = play
            btn._needsAHScan = false
            btn:Show()
            local badge = LL.Formatter.FormatDifficultyBadge(play.startDifficulty, play.endDifficulty)
            local trainerTag = play.needsTrainer and " |cff00ccff[Trainer]|r" or ""
            btn.mainText:SetText(string.format("#%d %s  %s%s", i, play.outputLink or play.recipeName, badge, trainerTag))
            btn.subText:SetText(string.format(
                "Craft %dx (%d->%d, +%d pts)  |  %s/pt  |  Total: %s",
                play.expectedCrafts, play.startSkill, play.targetSkill, play.pointsGained,
                LL.Formatter.FormatNetCost(play.cpspRounded, true),
                LL.Formatter.FormatNetCost(play.netCost, true)
            ))
            local verStr = play.verified and "|cff00ff00[Verified AH]|r" or "|cffffcc00[Cached]|r"
            local noteStr = ""
            if play.handoff then
                noteStr = string.format("  |cffffcc00-> Trainer @ %d|r", play.handoff.atSkill)
            elseif play.circuitBreakerNotice then
                noteStr = "  |cffff6644[Spike Guard]|r"
            end
            btn.extraText:SetText(string.format("   %s%s  — |cff88ccffClick for Shopping List|r", verStr, noteStr))
        else
            btn._play = nil
            btn._needsAHScan = (i == 1 and dataStatus == "NO_DATA")
            if i == 1 and #plays == 0 then
                btn:Show()
                if dataStatus == "NO_DATA" then
                    btn.mainText:SetText("|cffffcc00No Auction House Data Found|r")
                    btn.subText:SetText("Open the Auction House and run a PCF scan first.")
                    btn.extraText:SetText("")
                else
                    btn.mainText:SetText("|cffaaaaaaNo eligible leveling plays found.|r")
                    btn.subText:SetText("Check budget cap, profession rank, or click 'Find Top 5 Plays'.")
                    btn.extraText:SetText("")
                end
            else
                btn:Hide()
            end
        end
    end
end

function LL.SideWindow.RunSearch()
    EnsureSideWindow()
    local active = LL.RecipeScanner.GetActiveProfession()
    local plays = LL.AHVerifier.StartVerification(active.skillLine, {
        onUpdate = function(idx, total, target)
            LL.SideWindow.UpdateProgress(idx, total, target)
        end,
        onFinish = function()
            LL.SideWindow.Refresh()
        end,
    })
    LL.SideWindow.Refresh()
    return plays
end

function LL.SideWindow.Toggle()
    local frame = EnsureSideWindow()
    if frame.IsShown and frame:IsShown() then
        frame:Hide()
    else
        AnchorToAuctionHouse()
        frame:Show()
        if frame.Raise then frame:Raise() end
        LL.SideWindow.Refresh()
    end
end

function LL.SideWindow.Init()
    if LL.SideWindow._initialized then return end
    LL.SideWindow._initialized = true

    if eventFrame.RegisterEvent then
        pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_SHOW")
        pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_CLOSED")
        pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_MONEY")
        eventFrame:SetScript("OnEvent", function(_, event)
            if event == "AUCTION_HOUSE_SHOW" then
                if not LevelingLad_DB or not LevelingLad_DB.settings or LevelingLad_DB.settings.showSideWindow ~= false then
                    local frame = EnsureSideWindow()
                    AnchorToAuctionHouse()
                    frame:Show()
                    LL.SideWindow.Refresh()
                end
            elseif event == "AUCTION_HOUSE_CLOSED" then
                if LL.AHVerifier.IsRunning() then
                    LL.AHVerifier.Stop("AH_CLOSED")
                end
                if sideFrame then
                    sideFrame:Hide()
                end
            elseif event == "PLAYER_MONEY" then
                if sideFrame and (not sideFrame.IsShown or sideFrame:IsShown()) then
                    LL.SideWindow.Refresh()
                end
            end
        end)
    end
    LL.SideWindow.eventFrame = eventFrame
end
