local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.SideWindow = {}

local sideFrame = nil
local settingsFrame = nil
local snoozedFrame = nil
local ahToggleButton = nil
local minimapButton = nil
local minimapUsesLibDBIcon = false
local eventFrame = CreateFrame("Frame")
local playButtons = {}
local settingsCheckRows = {}
local priceSourceButtons = {}
local snoozedRows = {}
local TOP_ROWS = 5
local MAX_SNOOZED_ROWS = 12

local RECOVERY_CYCLE = { "VENDOR", "AH", "NONE" }
local RECOVERY_LABELS = {
    VENDOR = "Recovery: Vendor",
    AH     = "Recovery: AH",
    NONE   = "Recovery: None",
}

local SETTINGS_OPTIONS = {
    {
        key = "showSideWindow",
        frameName = "LL_SettingRow_AutoOpen",
        label = "Auto-Open Side Window at Auction House",
        desc = "Default OFF: keep Leveling Lad closed until you click the top-left AH button or /ll.",
        defaultVal = false,
    },
    {
        key = "showMinimapButton",
        frameName = "LL_SettingRow_Minimap",
        label = "Show Minimap Button (OneForAll / LibDBIcon Compatible)",
        desc = "Show a circular minimap button that collapses cleanly into button-collector addons.",
        defaultVal = true,
    },
    {
        key = "autoScanProfession",
        frameName = "LL_SettingRow_AutoScanProf",
        label = "Auto-Sync Crafting Window Outside AH",
        desc = "Automatically open & close your profession window in the background when recipes need syncing.",
        defaultVal = true,
    },
    {
        key = "buyoutOnly",
        frameName = "LL_SettingRow_BuyoutOnly",
        label = "Buyout Only (Exclude Bid-Only Auctions)",
        desc = "Ignore AH listings that only have a bid option and no instant buyout price.",
        defaultVal = true,
    },
    {
        key = "includeTrainerRecipes",
        frameName = "LL_SettingRow_Trainer",
        label = "Include Verified Trainer Recipe Lookahead",
        desc = "Include unlearned recipes verified at a WoW: Forever Profession Trainer.",
        defaultVal = true,
    },
    {
        key = "includeVendorArbitrage",
        frameName = "LL_SettingRow_VendorArb",
        label = "Use NPC Vendor Prices for Unlimited Reagents",
        desc = "Price threads, vials, flux, coal, salt, and spices at NPC vendor rates instead of AH.",
        defaultVal = true,
    },
}

local PRICE_SOURCE_CHOICES = {
    { key = "AUTO",        label = "Auto (Freshest)", frameName = "LL_SettingSource_Auto" },
    { key = "PCF",         label = "PCF Scan",        frameName = "LL_SettingSource_PCF" },
    { key = "AUCTIONATOR", label = "Auctionator",     frameName = "LL_SettingSource_Auctionator" },
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

local function GetActiveAuctionHouseFrame()
    if _G.AuctionHouseFrame and (not _G.AuctionHouseFrame.IsShown or _G.AuctionHouseFrame:IsShown()) then
        return _G.AuctionHouseFrame
    end
    if _G.AuctionFrame and (not _G.AuctionFrame.IsShown or _G.AuctionFrame:IsShown()) then
        return _G.AuctionFrame
    end
    return _G.AuctionHouseFrame or _G.AuctionFrame
end

-- Docks Leveling Lad on the LEFT side of the Auction House browser
local function AnchorToAuctionHouse()
    if not sideFrame or not sideFrame.SetPoint then return end
    local ahParent = _G.AuctionHouseFrame or _G.AuctionFrame
    if ahParent and (not ahParent.IsShown or ahParent:IsShown()) then
        if sideFrame.ClearAllPoints then sideFrame:ClearAllPoints() end
        sideFrame:SetPoint("TOPRIGHT", ahParent, "TOPLEFT", -6, 0)
    end
end

local function IsPCFScannerRunning()
    local btn = _G.PCF and _G.PCF.Scanner and _G.PCF.Scanner.scanButton
    if btn and btn.GetText and btn:GetText() == "Stop Scan" then
        return true
    end
    return false
end

local hookedPCFScanButtons = setmetatable({}, { __mode = "k" })

local function HookPCFScanButtonIfAvailable()
    local btn = _G.PCF and _G.PCF.Scanner and _G.PCF.Scanner.scanButton
    if not btn or hookedPCFScanButtons[btn] or type(btn.SetText) ~= "function" then
        return
    end
    hookedPCFScanButtons[btn] = true
    local function onSetText()
        if LL.InvalidateAHStatusCache then
            LL.InvalidateAHStatusCache()
        end
        if sideFrame and (not sideFrame.IsShown or sideFrame:IsShown()) then
            LL.SideWindow.Refresh()
        end
    end
    if _G.hooksecurefunc then
        pcall(_G.hooksecurefunc, btn, "SetText", onSetText)
    else
        local origSetText = btn.SetText
        btn.SetText = function(self, text, ...)
            local res = origSetText(self, text, ...)
            onSetText()
            return res
        end
    end
end

local function GetSettingBool(key, defaultVal)
    local s = LevelingLad_DB and LevelingLad_DB.settings
    if key == "showMinimapButton" then
        if s and type(s.minimap) == "table" and s.minimap.hide ~= nil then
            return s.minimap.hide ~= true
        end
        return defaultVal == true
    end
    if not s or s[key] == nil then
        return defaultVal == true
    end
    return s[key] == true
end

local function SyncPCFScanButtonForPriceSource()
    if not (_G.PCF_DB and type(_G.PCF_DB.settings) == "table") then
        return
    end
    if _G.PCF_DB.settings.userSetScanButton then
        return
    end
    local mode = (LL.GetPriceSourceMode and LL.GetPriceSourceMode()) or "AUTO"
    local desired = (mode ~= "AUCTIONATOR")
    if _G.PCF_DB.settings.showScanButton ~= desired then
        _G.PCF_DB.settings.showScanButton = desired
        if _G.PCF and _G.PCF.Scanner and type(_G.PCF.Scanner.UpdateVisibility) == "function" then
            _G.PCF.Scanner.UpdateVisibility()
        end
    end
end

function LL.SideWindow.SnoozeTopPlay(play, isPermanent)
    if type(play) ~= "table" or not LL.SnoozePlay then
        return nil
    end
    local dur = isPermanent and 0 or nil
    local reason = isPermanent and "permanent" or "manual"
    local entry = LL.SnoozePlay(play, dur, reason)
    if entry then
        local durSec = entry.durationSeconds or 86400
        local durLabel = isPermanent and "permanently" or ((durSec == 86400) and "for 24h" or ("for " .. LL.FormatAgeShort(durSec)))
        local dispName = entry.itemLink or entry.itemName or entry.key
        print(string.format(
            "|cff00ccff[Leveling Lad]|r Hidden %s from Top 5 %s (still usable in Milestone Path; restore in Options or /ll unhide).",
            dispName,
            durLabel
        ))
        LL.SideWindow.ApplySnoozeChange()
    end
    return entry
end

function LL.SideWindow.ApplySnoozeChange()
    local active = LL.RecipeScanner.GetActiveProfession()
    local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
    local dataStatus = (LL.GetAHDataStatus and LL.GetAHDataStatus()) or "FRESH"
    if scanStatus == "READY" and dataStatus == "FRESH" and not LL.AHVerifier.IsRunning() then
        if LL.AHVerifier.RefreshForSnoozeChange then
            LL.AHVerifier.RefreshForSnoozeChange(active.skillLine)
        elseif LL.AHVerifier.RecalculateFromCache then
            LL.AHVerifier.RecalculateFromCache(active.skillLine)
        end
    end
    LL.SideWindow.RefreshSettingsControls()
    if sideFrame and (not sideFrame.IsShown or sideFrame:IsShown()) then
        LL.SideWindow.Refresh()
    end
    if snoozedFrame and (not snoozedFrame.IsShown or snoozedFrame.IsShown(snoozedFrame)) and LL.SideWindow.RefreshSnoozedWindow then
        LL.SideWindow.RefreshSnoozedWindow()
    end
end

function LL.SideWindow.ApplyFilterChange()
    if LL.RecipeScanner and LL.RecipeScanner.InvalidateCache then
        LL.RecipeScanner.InvalidateCache()
    end
    if LL.AHVerifier and LL.AHVerifier.InvalidateEvaluatedPool then
        LL.AHVerifier.InvalidateEvaluatedPool()
    end
    if LL.InvalidateAHStatusCache then
        LL.InvalidateAHStatusCache()
    end

    local active = LL.RecipeScanner.GetActiveProfession()
    local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
    local dataStatus = (LL.GetAHDataStatus and LL.GetAHDataStatus()) or "FRESH"
    if scanStatus == "READY" and dataStatus == "FRESH" and not LL.AHVerifier.IsRunning() and LL.AHVerifier.RecalculateFromCache then
        LL.AHVerifier.RecalculateFromCache(active.skillLine)
    end

    LL.SideWindow.RefreshSettingsControls()
    if sideFrame and (not sideFrame.IsShown or sideFrame:IsShown()) then
        LL.SideWindow.Refresh()
    end
    if LL.DetailWindow and LL.DetailWindow.RefreshIfShown then
        LL.DetailWindow.RefreshIfShown()
    end
    if snoozedFrame and (not snoozedFrame.IsShown or snoozedFrame:IsShown()) and LL.SideWindow.RefreshSnoozedWindow then
        LL.SideWindow.RefreshSnoozedWindow()
    end
end

function LL.SideWindow.SetPriceSource(modeInput, quiet)
    if type(modeInput) ~= "string" then
        return false, LL.GetPriceSourceMode()
    end
    local normalized = modeInput:upper():match("^%s*(.-)%s*$") or ""
    if normalized == "ATR" or normalized == "AUCTIONATOR" then
        normalized = "AUCTIONATOR"
    elseif normalized == "PCF" or normalized == "SCAN" then
        normalized = "PCF"
    elseif normalized == "AUTO" or normalized == "BOTH" or normalized == "FRESHEST" then
        normalized = "AUTO"
    else
        if not quiet then
            print("|cffff5555[Leveling Lad]|r Invalid price source. Use 'auto', 'pcf', or 'auctionator'.")
        end
        return false, LL.GetPriceSourceMode()
    end

    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.settings = LevelingLad_DB.settings or {}
    LevelingLad_DB.settings.priceSource = normalized
    SyncPCFScanButtonForPriceSource()
    LL.SideWindow.ApplyFilterChange()

    if not quiet then
        local labels = {
            AUTO = "Auto (Freshest of PCF / Auctionator)",
            PCF = "PCF Scan Only",
            AUCTIONATOR = "Auctionator Only",
        }
        print(string.format("|cff00ccff[Leveling Lad]|r Price Data Source set to: %s.", labels[normalized] or normalized))
    end
    return true, normalized
end

function LL.SideWindow.SetMinimapButtonShown(shown)
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.settings = LevelingLad_DB.settings or {}
    LevelingLad_DB.settings.minimap = (type(LevelingLad_DB.settings.minimap) == "table" and LevelingLad_DB.settings.minimap) or { hide = false, minimapPos = 195 }
    local shouldShow = (shown == true)
    LevelingLad_DB.settings.minimap.hide = not shouldShow

    if minimapUsesLibDBIcon and _G.LibStub then
        local ok, ldbIcon = pcall(_G.LibStub, "LibDBIcon-1.0", true)
        if ok and ldbIcon then
            if shouldShow and ldbIcon.Show then
                pcall(ldbIcon.Show, ldbIcon, "LevelingLad")
            elseif not shouldShow and ldbIcon.Hide then
                pcall(ldbIcon.Hide, ldbIcon, "LevelingLad")
            end
        end
    elseif minimapButton then
        if shouldShow then
            minimapButton:Show()
        else
            minimapButton:Hide()
        end
    end

    LL.SideWindow.RefreshSettingsControls()
    return shouldShow
end

function LL.SideWindow.ToggleSetting(key, defaultVal)
    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.settings = LevelingLad_DB.settings or {}
    if key == "showMinimapButton" then
        local cur = GetSettingBool("showMinimapButton", defaultVal)
        return LL.SideWindow.SetMinimapButtonShown(not cur)
    end
    local cur = GetSettingBool(key, defaultVal)
    LevelingLad_DB.settings[key] = not cur
    LL.SideWindow.ApplyFilterChange()
    return LevelingLad_DB.settings[key]
end

local function CreatePlayRowButton(parent, index, yOffset)
    local btn = CreateFrame("Button", "LL_SidePlayBtn" .. index, parent)
    if btn.SetSize then btn:SetSize(346, 52) end
    if btn.SetPoint then btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, yOffset) end
    if btn.RegisterForClicks then
        pcall(btn.RegisterForClicks, btn, "LeftButtonUp", "RightButtonUp")
    end
    SetBackdropSafe(btn, 0.11, 0.13, 0.17, 0.92)

    local mainText = btn.CreateFontString and btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    if mainText then
        if mainText.SetPoint then mainText:SetPoint("TOPLEFT", btn, "TOPLEFT", 8, -6) end
        if mainText.SetWidth then mainText:SetWidth(312) end
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

    local snoozeBtn = CreateFrame("Button", "LL_SidePlayBtn" .. index .. "_Snooze", btn)
    if snoozeBtn.SetSize then snoozeBtn:SetSize(18, 18) end
    if snoozeBtn.SetPoint then snoozeBtn:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -4, -4) end
    SetBackdropSafe(snoozeBtn, 0.24, 0.14, 0.16, 0.88)
    local snoozeText = snoozeBtn.CreateFontString and snoozeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if snoozeText then
        if snoozeText.SetPoint then snoozeText:SetPoint("CENTER", snoozeBtn, "CENTER", 0, 0) end
        if snoozeText.SetText then snoozeText:SetText("|cffff9999x|r") end
    end
    snoozeBtn:SetScript("OnClick", function()
        if btn._play then
            local isPerm = (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) == true
            LL.SideWindow.SnoozeTopPlay(btn._play, isPerm)
        end
    end)
    snoozeBtn:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:AddLine("Snooze / Hide Play from Top 5", 0, 0.85, 1)
        _G.GameTooltip:AddLine("Click: Snooze this recipe from Top 5 for 24 hours.", 1, 1, 1, true)
        _G.GameTooltip:AddLine("Shift-Click: Hide permanently (restore in Options).", 0.7, 0.85, 1, true)
        _G.GameTooltip:AddLine("Snoozed recipes remain usable in Milestone Path.", 0.75, 0.75, 0.75, true)
        _G.GameTooltip:Show()
    end)
    snoozeBtn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    snoozeBtn:Hide()

    btn:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" and btn._play then
            local isPerm = (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) == true
            LL.SideWindow.SnoozeTopPlay(btn._play, isPerm)
            return
        end
        if btn._play then
            LL.DetailWindow.ShowPlay(btn._play)
        elseif btn._needsProfScan then
            LL.SideWindow.TriggerProfessionScan()
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
            _G.GameTooltip:AddLine("|cff00ff88Left-Click:|r Open Shopping List & Craft Launcher", 0.2, 1, 0.6)
            _G.GameTooltip:AddLine("|cffaaaaaaRight-Click (or 'x'): Snooze from Top 5 for 24h (Shift: permanent)|r", 0.75, 0.75, 0.75)
            _G.GameTooltip:Show()
        elseif btn._needsProfScan then
            local active = LL.RecipeScanner.GetActiveProfession()
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:AddLine(string.format("Open %s to Calculate Plays", active.name or "Profession"), 1, 0.85, 0.2)
            _G.GameTooltip:AddLine("WoW: Forever computes live orange/yellow/green/gray recipe states inside your profession window. Open it once at your current skill rank so Leveling Lad never shows outdated difficulty math.", 1, 1, 1, true)
            _G.GameTooltip:AddLine(" ")
            _G.GameTooltip:AddLine(string.format("|cff00ff88Click to open & scan %s now|r", active.name or "Profession"), 0.2, 1, 0.6)
            _G.GameTooltip:Show()
        elseif btn._needsAHScan then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:AddLine("Auction House Scan Required", 1, 0.8, 0.2)
            _G.GameTooltip:AddLine("Leveling Lad needs fresh Auction House price data (via PCF Scan or Auctionator) to price crafting reagents accurately.", 1, 1, 1, true)
            _G.GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    btn.mainText = mainText
    btn.subText = subText
    btn.extraText = extraText
    btn.snoozeBtn = snoozeBtn
    return btn
end

local function EnsureSnoozedWindow()
    if snoozedFrame then
        return snoozedFrame
    end

    snoozedFrame = CreateFrame("Frame", "LL_SnoozedPlaysWindow", _G.UIParent)
    if snoozedFrame.SetSize then snoozedFrame:SetSize(410, 380) end
    if snoozedFrame.SetPoint then snoozedFrame:SetPoint("CENTER", _G.UIParent, "CENTER", 140, 20) end
    if snoozedFrame.SetFrameStrata then snoozedFrame:SetFrameStrata("DIALOG") end
    if snoozedFrame.SetToplevel then snoozedFrame:SetToplevel(true) end
    if snoozedFrame.SetMovable then snoozedFrame:SetMovable(true) end
    if snoozedFrame.SetClampedToScreen then pcall(snoozedFrame.SetClampedToScreen, snoozedFrame, true) end
    if snoozedFrame.EnableMouse then snoozedFrame:EnableMouse(true) end
    if snoozedFrame.RegisterForDrag then snoozedFrame:RegisterForDrag("LeftButton") end
    snoozedFrame:SetScript("OnDragStart", function(self)
        if self.StartMoving then self:StartMoving() end
    end)
    snoozedFrame:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    end)
    SetBackdropSafe(snoozedFrame, 0.05, 0.06, 0.09, 0.97)

    local title = snoozedFrame.CreateFontString and snoozedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if title then
        if title.SetPoint then title:SetPoint("TOPLEFT", snoozedFrame, "TOPLEFT", 14, -12) end
        if title.SetText then title:SetText("|cff00ccffLeveling Lad|r — Snoozed Top 5 Plays") end
    end

    local closeBtn = CreateFrame("Button", "LL_SnoozedCloseButton", snoozedFrame, "UIPanelCloseButton")
    if closeBtn.SetPoint then closeBtn:SetPoint("TOPRIGHT", snoozedFrame, "TOPRIGHT", -4, -4) end
    closeBtn:SetScript("OnClick", function()
        snoozedFrame:Hide()
    end)

    local emptyText = snoozedFrame.CreateFontString and snoozedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if emptyText then
        if emptyText.SetPoint then emptyText:SetPoint("TOPLEFT", snoozedFrame, "TOPLEFT", 16, -46) end
        if emptyText.SetWidth then emptyText:SetWidth(378) end
        if emptyText.SetJustifyH then emptyText:SetJustifyH("LEFT") end
        if emptyText.SetText then emptyText:SetText("|cffaaaaaaNo snoozed or hidden Top 5 plays right now.|r") end
    end

    for i = 1, MAX_SNOOZED_ROWS do
        local yOff = -44 - ((i - 1) * 24)
        local row = CreateFrame("Frame", "LL_SnoozedRow" .. i, snoozedFrame)
        if row.SetSize then row:SetSize(382, 22) end
        if row.SetPoint then row:SetPoint("TOPLEFT", snoozedFrame, "TOPLEFT", 14, yOff) end
        SetBackdropSafe(row, 0.11, 0.13, 0.16, 0.92)

        local label = row.CreateFontString and row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if label then
            if label.SetPoint then label:SetPoint("LEFT", row, "LEFT", 6, 0) end
            if label.SetWidth then label:SetWidth(302) end
            if label.SetJustifyH then label:SetJustifyH("LEFT") end
            if label.SetWordWrap then pcall(label.SetWordWrap, label, false) end
        end

        local unhideBtn = CreateFrame("Button", "LL_SnoozedUnhideBtn" .. i, row, "UIPanelButtonTemplate")
        if unhideBtn.SetSize then unhideBtn:SetSize(64, 18) end
        if unhideBtn.SetPoint then unhideBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0) end
        if unhideBtn.SetText then unhideBtn:SetText("Unhide") end
        unhideBtn:SetScript("OnClick", function()
            if row._snoozeKey and LL.UnsnoozePlay then
                local removed, entry = LL.UnsnoozePlay(row._snoozeKey)
                if removed then
                    print(string.format("|cff00ccff[Leveling Lad]|r Restored %s to Top 5 plays.", (entry and (entry.itemLink or entry.itemName)) or row._snoozeKey))
                    LL.SideWindow.ApplySnoozeChange()
                end
            end
        end)

        row.label = label
        row.unhideBtn = unhideBtn
        row:Hide()
        snoozedRows[i] = row
    end

    local clearAllBtn = CreateFrame("Button", "LL_SnoozedClearAllButton", snoozedFrame, "UIPanelButtonTemplate")
    if clearAllBtn.SetSize then clearAllBtn:SetSize(140, 24) end
    if clearAllBtn.SetPoint then clearAllBtn:SetPoint("BOTTOMLEFT", snoozedFrame, "BOTTOMLEFT", 14, 12) end
    if clearAllBtn.SetText then clearAllBtn:SetText("Clear All Hidden") end
    clearAllBtn:SetScript("OnClick", function()
        local cleared = (LL.ClearAllSnoozedPlays and LL.ClearAllSnoozedPlays()) or 0
        if cleared > 0 then
            print(string.format("|cff00ccff[Leveling Lad]|r Restored all %d snoozed/hidden plays.", cleared))
            LL.SideWindow.ApplySnoozeChange()
        end
    end)

    local closeFooterBtn = CreateFrame("Button", "LL_SnoozedDoneButton", snoozedFrame, "UIPanelButtonTemplate")
    if closeFooterBtn.SetSize then closeFooterBtn:SetSize(100, 24) end
    if closeFooterBtn.SetPoint then closeFooterBtn:SetPoint("BOTTOMRIGHT", snoozedFrame, "BOTTOMRIGHT", -14, 12) end
    if closeFooterBtn.SetText then closeFooterBtn:SetText("Close") end
    closeFooterBtn:SetScript("OnClick", function()
        snoozedFrame:Hide()
    end)

    snoozedFrame.emptyText = emptyText
    snoozedFrame.rows = snoozedRows
    snoozedFrame.clearAllBtn = clearAllBtn
    snoozedFrame:Hide()
    LL.SideWindow.snoozedFrame = snoozedFrame
    return snoozedFrame
end

function LL.SideWindow.RefreshSnoozedWindow()
    if not snoozedFrame then return end
    local list = (LL.GetActiveSnoozedPlays and LL.GetActiveSnoozedPlays()) or {}
    if snoozedFrame.emptyText then
        if #list == 0 then
            snoozedFrame.emptyText:Show()
        else
            snoozedFrame.emptyText:Hide()
        end
    end
    for i = 1, MAX_SNOOZED_ROWS do
        local row = snoozedRows[i]
        local entry = list[i]
        if entry then
            row._snoozeKey = entry.key
            local tag = entry.isPermanent and "|cffff7777[Permanent]|r" or string.format("|cffffd100[%s left]|r", entry.remainingText)
            if row.label then
                row.label:SetText(string.format("%s  %s", entry.itemLink or entry.itemName or entry.key, tag))
            end
            row:Show()
        else
            row._snoozeKey = nil
            row:Hide()
        end
    end
end

function LL.SideWindow.ToggleSnoozedWindow()
    local frame = EnsureSnoozedWindow()
    if frame.IsShown and frame:IsShown() then
        frame:Hide()
    else
        LL.SideWindow.RefreshSnoozedWindow()
        frame:Show()
        if frame.Raise then frame:Raise() end
    end
end

function LL.SideWindow.RefreshSettingsControls()
    if not settingsFrame then return end

    for _, opt in ipairs(SETTINGS_OPTIONS) do
        local row = settingsCheckRows[opt.key]
        if row then
            local enabled = GetSettingBool(opt.key, opt.defaultVal)
            local box = enabled and "|cff00ff88[ON]|r" or "|cff777777[OFF]|r"
            local text = string.format("%s  %s", box, opt.label)
            if row.SetText then row:SetText(text) end
            if row.titleText and row.titleText.SetText then
                row.titleText:SetText(text)
            end
            SetBtnBgColor(row, enabled and 0.10 or 0.12, enabled and 0.22 or 0.13, enabled and 0.20 or 0.15, 0.92)
        end
    end

    local activeMode = (LL.GetPriceSourceMode and LL.GetPriceSourceMode()) or "AUTO"
    for _, choice in ipairs(PRICE_SOURCE_CHOICES) do
        local btn = priceSourceButtons[choice.key]
        if btn then
            local selected = (activeMode == choice.key)
            SetBtnBgColor(btn, selected and 0.08 or 0.14, selected and 0.34 or 0.15, selected and 0.30 or 0.18, 0.95)
            local txt = selected
                and string.format("|cff00ff88[%s]|r", choice.label)
                or string.format("|cffaaaaaa%s|r", choice.label)
            if btn.SetText then btn:SetText(txt) end
            if btn.labelText and btn.labelText.SetText then
                btn.labelText:SetText(txt)
            end
        end
    end

    if settingsFrame.sourceTitleText then
        local status, info = "NO_DATA", {}
        if LL.GetAHDataStatus then
            status, info = LL.GetAHDataStatus()
        end
        local activeNote
        if status == "FRESH" then
            activeNote = string.format("|cff00ff88Active: %s (%d items)|r", info.activeSource or "PCF", info.itemCount or 0)
        elseif status == "STALE" then
            activeNote = string.format("|cffff9900Stale: %s (%s old)|r", info.activeSource or "PCF", info.ageText or "24h+")
        else
            activeNote = "|cffffcc00No scan data yet (run PCF or Auctionator scan)|r"
        end
        settingsFrame.sourceTitleText:SetText("Price Data Source:  " .. activeNote)
    end

    if settingsFrame.budgetTitleText then
        local effectiveBudget, isCapped, playerGold, customCap = LL.GetEffectiveBudget()
        if isCapped then
            settingsFrame.budgetTitleText:SetText(string.format(
                "Max Leveling Budget: |cff00ff88%s Cap|r |cffaaaaaa(Effective: %s | Wallet: %s)|r",
                LL.Formatter.FormatMoneyShort(customCap),
                LL.Formatter.FormatMoneyShort(effectiveBudget),
                LL.Formatter.FormatMoneyShort(playerGold)
            ))
        else
            settingsFrame.budgetTitleText:SetText(string.format(
                "Max Leveling Budget: |cffffd100All Gold (%s)|r",
                LL.Formatter.FormatMoneyShort(playerGold)
            ))
        end
        if settingsFrame.budgetInput and not (settingsFrame.budgetInput.HasFocus and settingsFrame.budgetInput:HasFocus()) then
            settingsFrame.budgetInput:SetText(isCapped and LL.Formatter.FormatMoneyShort(customCap) or "")
        end
    end

    if settingsFrame.snoozedTitleText then
        local snoozed = (LL.GetActiveSnoozedPlays and LL.GetActiveSnoozedPlays()) or {}
        if #snoozed > 0 then
            settingsFrame.snoozedTitleText:SetText(string.format(
                "Snoozed Top 5 Plays: |cffffd100%d active|r |cffaaaaaa(Still usable in Milestone Path)|r",
                #snoozed
            ))
        else
            settingsFrame.snoozedTitleText:SetText("Snoozed Top 5 Plays: |cffaaaaaaNone — right-click or click 'x' on any row to hide 24h|r")
        end
    end
end

local function EnsureSettingsWindow()
    if settingsFrame then
        return settingsFrame
    end

    local rowHeight = 31
    local rowPitch = 34
    local listStartY = -52
    local afterListY = listStartY - (#SETTINGS_OPTIONS * rowPitch) - 4
    local sourceCardHeight = 52
    local budgetCardHeight = 62
    local snoozedCardHeight = 50
    local totalHeight = math.abs(afterListY) + sourceCardHeight + 6 + budgetCardHeight + 6 + snoozedCardHeight + 46

    settingsFrame = CreateFrame("Frame", "LL_SettingsWindow", _G.UIParent)
    if settingsFrame.SetSize then settingsFrame:SetSize(430, totalHeight) end
    if settingsFrame.SetPoint then settingsFrame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 10) end
    if settingsFrame.SetFrameStrata then settingsFrame:SetFrameStrata("MEDIUM") end
    if settingsFrame.SetToplevel then settingsFrame:SetToplevel(true) end
    if settingsFrame.SetMovable then settingsFrame:SetMovable(true) end
    if settingsFrame.SetClampedToScreen then pcall(settingsFrame.SetClampedToScreen, settingsFrame, true) end
    if settingsFrame.EnableMouse then settingsFrame:EnableMouse(true) end
    if settingsFrame.RegisterForDrag then settingsFrame:RegisterForDrag("LeftButton") end
    settingsFrame:SetScript("OnDragStart", function(self)
        if self.StartMoving then self:StartMoving() end
    end)
    settingsFrame:SetScript("OnDragStop", function(self)
        if self.StopMovingOrSizing then self:StopMovingOrSizing() end
    end)
    SetBackdropSafe(settingsFrame, 0.05, 0.06, 0.09, 0.97)

    local title = settingsFrame.CreateFontString and settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if title then
        if title.SetPoint then title:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 14, -12) end
        if title.SetText then title:SetText("|cff00ccffLeveling Lad|r — Options & Snoozed Plays") end
    end

    local closeBtn = CreateFrame("Button", "LL_SettingsCloseButton", settingsFrame, "UIPanelCloseButton")
    if closeBtn.SetPoint then closeBtn:SetPoint("TOPRIGHT", settingsFrame, "TOPRIGHT", -4, -4) end
    closeBtn:SetScript("OnClick", function()
        settingsFrame:Hide()
    end)

    local subtitle = settingsFrame.CreateFontString and settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if subtitle then
        if subtitle.SetPoint then subtitle:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 14, -33) end
        if subtitle.SetText then subtitle:SetText("Configure AH window behavior, price source, and snoozed Top 5 recipes:") end
    end

    for idx, opt in ipairs(SETTINGS_OPTIONS) do
        local yOff = listStartY - ((idx - 1) * rowPitch)
        local row = CreateFrame("Button", opt.frameName, settingsFrame)
        if row.SetSize then row:SetSize(402, rowHeight) end
        if row.SetPoint then row:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 14, yOff) end
        SetBackdropSafe(row, 0.11, 0.13, 0.16, 0.92)

        local titleText = row.CreateFontString and row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if titleText then
            if titleText.SetPoint then titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -3) end
            if titleText.SetWidth then titleText:SetWidth(386) end
            if titleText.SetJustifyH then titleText:SetJustifyH("LEFT") end
        end

        local descText = row.CreateFontString and row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if descText then
            if descText.SetPoint then descText:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -1) end
            if descText.SetWidth then descText:SetWidth(386) end
            if descText.SetJustifyH then descText:SetJustifyH("LEFT") end
            if descText.SetWordWrap then pcall(descText.SetWordWrap, descText, false) end
            if descText.SetText then descText:SetText("|cffaaaaaa" .. opt.desc .. "|r") end
        end

        row:SetScript("OnClick", function()
            LL.SideWindow.ToggleSetting(opt.key, opt.defaultVal)
        end)

        row.titleText = titleText
        row.descText = descText
        settingsCheckRows[opt.key] = row
    end

    local sourceYOff = afterListY
    local sourceCard = CreateFrame("Frame", "LL_SettingsSourceCard", settingsFrame)
    if sourceCard.SetSize then sourceCard:SetSize(402, sourceCardHeight) end
    if sourceCard.SetPoint then sourceCard:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 14, sourceYOff) end
    SetBackdropSafe(sourceCard, 0.10, 0.13, 0.18, 0.94)

    local sourceTitleText = sourceCard.CreateFontString and sourceCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if sourceTitleText then
        if sourceTitleText.SetPoint then sourceTitleText:SetPoint("TOPLEFT", sourceCard, "TOPLEFT", 8, -6) end
        if sourceTitleText.SetWidth then sourceTitleText:SetWidth(386) end
        if sourceTitleText.SetJustifyH then sourceTitleText:SetJustifyH("LEFT") end
    end

    for idx, choice in ipairs(PRICE_SOURCE_CHOICES) do
        local btn = CreateFrame("Button", choice.frameName, sourceCard)
        if btn.SetSize then btn:SetSize(124, 22) end
        if btn.SetPoint then
            btn:SetPoint("BOTTOMLEFT", sourceCard, "BOTTOMLEFT", 8 + ((idx - 1) * 131), 6)
        end
        SetBackdropSafe(btn, 0.14, 0.15, 0.18, 0.95)
        local labelText = btn.CreateFontString and btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        if labelText then
            if labelText.SetPoint then labelText:SetPoint("CENTER", btn, "CENTER", 0, 0) end
        end
        btn.labelText = labelText
        btn:SetScript("OnClick", function()
            LL.SideWindow.SetPriceSource(choice.key)
        end)
        priceSourceButtons[choice.key] = btn
    end

    local budgetYOff = sourceYOff - sourceCardHeight - 6
    local budgetCard = CreateFrame("Frame", "LL_SettingsBudgetCard", settingsFrame)
    if budgetCard.SetSize then budgetCard:SetSize(402, budgetCardHeight) end
    if budgetCard.SetPoint then budgetCard:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 14, budgetYOff) end
    SetBackdropSafe(budgetCard, 0.10, 0.13, 0.18, 0.94)

    local budgetTitleText = budgetCard.CreateFontString and budgetCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if budgetTitleText then
        if budgetTitleText.SetPoint then budgetTitleText:SetPoint("TOPLEFT", budgetCard, "TOPLEFT", 8, -5) end
        if budgetTitleText.SetWidth then budgetTitleText:SetWidth(386) end
        if budgetTitleText.SetJustifyH then budgetTitleText:SetJustifyH("LEFT") end
    end

    local budgetDescText = budgetCard.CreateFontString and budgetCard:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if budgetDescText then
        if budgetDescText.SetPoint then budgetDescText:SetPoint("TOPLEFT", budgetTitleText, "BOTTOMLEFT", 0, -2) end
        if budgetDescText.SetWidth then budgetDescText:SetWidth(386) end
        if budgetDescText.SetJustifyH then budgetDescText:SetJustifyH("LEFT") end
        if budgetDescText.SetText then
            budgetDescText:SetText("|cffaaaaaaLimit gold spent on leveling reagents (e.g. 25g, 10g 50s, or blank for All Gold):|r")
        end
    end

    local budgetInput = CreateFrame("EditBox", "LL_SettingsBudgetInput", budgetCard, "InputBoxTemplate")
    if budgetInput.SetSize then budgetInput:SetSize(136, 20) end
    if budgetInput.SetPoint then budgetInput:SetPoint("BOTTOMLEFT", budgetCard, "BOTTOMLEFT", 14, 6) end
    if budgetInput.SetAutoFocus then pcall(budgetInput.SetAutoFocus, budgetInput, false) end

    local function CommitSettingsBudget()
        local raw = (budgetInput.GetText and budgetInput:GetText()) or ""
        if budgetInput.ClearFocus then pcall(budgetInput.ClearFocus, budgetInput) end
        LL.SideWindow.SetBudget(raw)
    end

    budgetInput:SetScript("OnEnterPressed", CommitSettingsBudget)
    budgetInput:SetScript("OnEscapePressed", function(self)
        if self.ClearFocus then pcall(self.ClearFocus, self) end
        LL.SideWindow.RefreshSettingsControls()
    end)

    local budgetApplyBtn = CreateFrame("Button", "LL_SettingsBudgetApplyButton", budgetCard, "UIPanelButtonTemplate")
    if budgetApplyBtn.SetSize then budgetApplyBtn:SetSize(74, 22) end
    if budgetApplyBtn.SetPoint then budgetApplyBtn:SetPoint("LEFT", budgetInput, "RIGHT", 10, 0) end
    if budgetApplyBtn.SetText then budgetApplyBtn:SetText("Apply") end
    budgetApplyBtn:SetScript("OnClick", CommitSettingsBudget)

    local budgetAutoBtn = CreateFrame("Button", "LL_SettingsBudgetAutoButton", budgetCard, "UIPanelButtonTemplate")
    if budgetAutoBtn.SetSize then budgetAutoBtn:SetSize(112, 22) end
    if budgetAutoBtn.SetPoint then budgetAutoBtn:SetPoint("LEFT", budgetApplyBtn, "RIGHT", 8, 0) end
    if budgetAutoBtn.SetText then budgetAutoBtn:SetText("Use All Gold") end
    budgetAutoBtn:SetScript("OnClick", function()
        if budgetInput.ClearFocus then pcall(budgetInput.ClearFocus, budgetInput) end
        if budgetInput.SetText then budgetInput:SetText("") end
        LL.SideWindow.SetBudget("auto")
    end)

    local snoozedYOff = budgetYOff - budgetCardHeight - 6
    local snoozedCard = CreateFrame("Frame", "LL_SettingsSnoozedCard", settingsFrame)
    if snoozedCard.SetSize then snoozedCard:SetSize(402, snoozedCardHeight) end
    if snoozedCard.SetPoint then snoozedCard:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 14, snoozedYOff) end
    SetBackdropSafe(snoozedCard, 0.10, 0.13, 0.18, 0.94)

    local snoozedTitleText = snoozedCard.CreateFontString and snoozedCard:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    if snoozedTitleText then
        if snoozedTitleText.SetPoint then snoozedTitleText:SetPoint("TOPLEFT", snoozedCard, "TOPLEFT", 8, -5) end
        if snoozedTitleText.SetWidth then snoozedTitleText:SetWidth(386) end
        if snoozedTitleText.SetJustifyH then snoozedTitleText:SetJustifyH("LEFT") end
    end

    local manageSnoozedBtn = CreateFrame("Button", "LL_SettingsManageSnoozedButton", snoozedCard, "UIPanelButtonTemplate")
    if manageSnoozedBtn.SetSize then manageSnoozedBtn:SetSize(170, 22) end
    if manageSnoozedBtn.SetPoint then manageSnoozedBtn:SetPoint("BOTTOMLEFT", snoozedCard, "BOTTOMLEFT", 8, 6) end
    if manageSnoozedBtn.SetText then manageSnoozedBtn:SetText("Manage Snoozed Plays") end
    manageSnoozedBtn:SetScript("OnClick", function()
        LL.SideWindow.ToggleSnoozedWindow()
    end)

    local clearSnoozedBtn = CreateFrame("Button", "LL_SettingsClearSnoozedButton", snoozedCard, "UIPanelButtonTemplate")
    if clearSnoozedBtn.SetSize then clearSnoozedBtn:SetSize(130, 22) end
    if clearSnoozedBtn.SetPoint then clearSnoozedBtn:SetPoint("LEFT", manageSnoozedBtn, "RIGHT", 10, 0) end
    if clearSnoozedBtn.SetText then clearSnoozedBtn:SetText("Clear All Hidden") end
    clearSnoozedBtn:SetScript("OnClick", function()
        local cleared = (LL.ClearAllSnoozedPlays and LL.ClearAllSnoozedPlays()) or 0
        if cleared > 0 then
            print(string.format("|cff00ccff[Leveling Lad]|r Restored all %d snoozed/hidden plays.", cleared))
            LL.SideWindow.ApplySnoozeChange()
        else
            print("|cff00ccff[Leveling Lad]|r No snoozed/hidden plays to clear.")
        end
    end)

    local resetBtn = CreateFrame("Button", "LL_SettingsResetButton", settingsFrame, "UIPanelButtonTemplate")
    if resetBtn.SetSize then resetBtn:SetSize(160, 24) end
    if resetBtn.SetPoint then resetBtn:SetPoint("BOTTOMLEFT", settingsFrame, "BOTTOMLEFT", 14, 12) end
    if resetBtn.SetText then resetBtn:SetText("Reset Defaults") end
    resetBtn:SetScript("OnClick", function()
        LevelingLad_DB = LevelingLad_DB or {}
        LevelingLad_DB.settings = LevelingLad_DB.settings or {}
        for _, opt in ipairs(SETTINGS_OPTIONS) do
            if opt.key == "showMinimapButton" then
                LL.SideWindow.SetMinimapButtonShown(opt.defaultVal)
            else
                LevelingLad_DB.settings[opt.key] = opt.defaultVal
            end
        end
        LevelingLad_DB.settings.priceSource = "AUTO"
        LevelingLad_DB.settings.budgetCopper = 0
        SyncPCFScanButtonForPriceSource()
        if budgetInput.ClearFocus then pcall(budgetInput.ClearFocus, budgetInput) end
        if budgetInput.SetText then budgetInput:SetText("") end
        LL.SideWindow.ApplyFilterChange()
    end)

    local doneBtn = CreateFrame("Button", "LL_SettingsDoneButton", settingsFrame, "UIPanelButtonTemplate")
    if doneBtn.SetSize then doneBtn:SetSize(110, 24) end
    if doneBtn.SetPoint then doneBtn:SetPoint("BOTTOMRIGHT", settingsFrame, "BOTTOMRIGHT", -14, 12) end
    if doneBtn.SetText then doneBtn:SetText("Done") end
    doneBtn:SetScript("OnClick", function()
        settingsFrame:Hide()
    end)

    settingsFrame.sourceTitleText = sourceTitleText
    settingsFrame.budgetTitleText = budgetTitleText
    settingsFrame.budgetInput = budgetInput
    settingsFrame.snoozedTitleText = snoozedTitleText

    settingsFrame:Hide()
    LL.SideWindow.settingsFrame = settingsFrame
    LL.SideWindow.RefreshSettingsControls()
    return settingsFrame
end

function LL.SideWindow.ToggleSettingsWindow()
    local frame = EnsureSettingsWindow()
    if frame.IsShown and frame:IsShown() then
        frame:Hide()
    else
        LL.SideWindow.RefreshSettingsControls()
        frame:Show()
        if frame.Raise then frame:Raise() end
    end
end

local function TryAutoSyncActiveProfession()
    local s = LevelingLad_DB and LevelingLad_DB.settings
    if s and s.autoScanProfession == false then
        LL.RecipeScanner.ScanCurrentProfessionWindow()
        return
    end
    local active = LL.RecipeScanner.GetActiveProfession()
    LL.RecipeScanner.SyncProfessionRecipes(active.skillLine, {
        allowOpenWindow = true,
        closeAfterScan = true,
        quiet = true,
        onComplete = function()
            LL.SideWindow.OnProfessionWindowScanned()
        end,
    })
end

function LL.SideWindow.TriggerProfessionScan()
    local active = LL.RecipeScanner.GetActiveProfession()
    local opened, res = LL.RecipeScanner.SyncProfessionRecipes(active.skillLine, {
        allowOpenWindow = true,
        userClickedScan = true,
        closeAfterScan = false,
        onComplete = function()
            LL.SideWindow.OnProfessionWindowScanned()
        end,
    })
    if opened and res == "READY" then
        LL.SideWindow.OnProfessionWindowScanned()
    elseif not opened and res ~= "COMBAT" then
        print(string.format("|cffffcc00[Leveling Lad]|r Open your %s profession window once to scan live orange/yellow/green recipes.", active.name or "Profession"))
    end
    LL.SideWindow.Refresh()
    return opened
end

function LL.SideWindow.OnProfessionWindowScanned()
    local active = LL.RecipeScanner.GetActiveProfession()
    local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
    local dataStatus = (LL.GetAHDataStatus and LL.GetAHDataStatus()) or "FRESH"
    if scanStatus == "READY" and dataStatus == "FRESH" and not LL.AHVerifier.IsRunning() then
        LL.AHVerifier.RecalculateFromCache(active.skillLine)
    end
    LL.SideWindow.RefreshIfShown()
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
    if LL.SyncActivePlayWithGoal then
        LL.SyncActivePlayWithGoal()
    end
    TryAutoSyncActiveProfession()
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
    if sideFrame.SetPoint then sideFrame:SetPoint("CENTER", _G.UIParent, "CENTER", -240, 0) end
    if sideFrame.SetFrameStrata then sideFrame:SetFrameStrata("MEDIUM") end
    if sideFrame.SetToplevel then sideFrame:SetToplevel(true) end
    if sideFrame.SetMovable then sideFrame:SetMovable(true) end
    if sideFrame.SetClampedToScreen then pcall(sideFrame.SetClampedToScreen, sideFrame, true) end
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
        if title.SetPoint then title:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -11) end
        if title.SetText then title:SetText("|cff00ccffLeveling Lad|r — Cheapest Plays") end
    end

    local closeBtn = CreateFrame("Button", "LL_SideCloseBtn", sideFrame, "UIPanelCloseButton")
    if closeBtn.SetPoint then closeBtn:SetPoint("TOPRIGHT", sideFrame, "TOPRIGHT", -2, -2) end
    closeBtn:SetScript("OnClick", function()
        sideFrame:Hide()
    end)

    local settingsBtn = CreateFrame("Button", "LL_SideSettingsBtn", sideFrame, "UIPanelButtonTemplate")
    if settingsBtn.SetSize then settingsBtn:SetSize(64, 20) end
    if settingsBtn.SetPoint then settingsBtn:SetPoint("TOPRIGHT", sideFrame, "TOPRIGHT", -30, -8) end
    if settingsBtn.SetText then settingsBtn:SetText("Options") end
    settingsBtn:SetScript("OnClick", function()
        LL.SideWindow.ToggleSettingsWindow()
    end)
    settingsBtn:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:AddLine("Leveling Lad Options", 0, 0.85, 1)
        _G.GameTooltip:AddLine("Configure Auto-Open, Price Source (Auto / PCF / Auctionator), Minimap button, and Snoozed Plays.", 1, 1, 1, true)
        _G.GameTooltip:Show()
    end)
    settingsBtn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    -- Row 1: Profession Selector + Recovery Mode
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
    local plus5Text = targetPlus5Btn.CreateFontString and targetPlus5Btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if plus5Text then
        if plus5Text.SetPoint then plus5Text:SetPoint("CENTER", targetPlus5Btn, "CENTER", 0, 0) end
        targetPlus5Btn.labelText = plus5Text
    end
    targetPlus5Btn:SetScript("OnClick", function()
        LevelingLad_DB.settings.targetMode = "PLUS5"
        LevelingLad_DB.settings.targetSkillRank = 0
        if LL.SyncActivePlayWithGoal then
            LL.SyncActivePlayWithGoal()
        end
        LL.SideWindow.RunSearch()
    end)

    local targetMilestoneBtn = CreateFrame("Button", "LL_SideTargetMilestoneBtn", sideFrame)
    if targetMilestoneBtn.SetSize then targetMilestoneBtn:SetSize(128, 22) end
    if targetMilestoneBtn.SetPoint then targetMilestoneBtn:SetPoint("LEFT", targetPlus5Btn, "RIGHT", 6, 0) end
    SetBackdropSafe(targetMilestoneBtn, 0.10, 0.30, 0.42, 0.95)
    local milestoneText = targetMilestoneBtn.CreateFontString and targetMilestoneBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if milestoneText then
        if milestoneText.SetPoint then milestoneText:SetPoint("CENTER", targetMilestoneBtn, "CENTER", 0, 0) end
        targetMilestoneBtn.labelText = milestoneText
    end
    targetMilestoneBtn:SetScript("OnClick", function()
        LevelingLad_DB.settings.targetMode = "MILESTONE"
        LevelingLad_DB.settings.targetSkillRank = 0
        if LL.SyncActivePlayWithGoal then
            LL.SyncActivePlayWithGoal()
        end
        LL.SideWindow.RunSearch()
    end)

    local targetCustomInput = CreateFrame("EditBox", "LL_SideCustomTargetInput", sideFrame, "InputBoxTemplate")
    if targetCustomInput.SetSize then targetCustomInput:SetSize(52, 22) end
    if targetCustomInput.SetPoint then targetCustomInput:SetPoint("LEFT", targetMilestoneBtn, "RIGHT", 10, 0) end
    if targetCustomInput.SetAutoFocus then targetCustomInput:SetAutoFocus(false) end
    targetCustomInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val > 1 and val <= 300 then
            local goal = math.floor(val)
            LevelingLad_DB.settings.targetMode = "CUSTOM"
            LevelingLad_DB.settings.customTargetSkill = goal
            LevelingLad_DB.settings.targetSkillRank = goal
            if LL.SyncActivePlayWithGoal then
                LL.SyncActivePlayWithGoal(goal)
            end
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
            local goal = math.floor(val)
            LevelingLad_DB.settings.targetMode = "CUSTOM"
            LevelingLad_DB.settings.customTargetSkill = goal
            LevelingLad_DB.settings.targetSkillRank = goal
            if LL.SyncActivePlayWithGoal then
                LL.SyncActivePlayWithGoal(goal)
            end
            LL.SideWindow.RunSearch()
        end
        if targetCustomInput.ClearFocus then targetCustomInput:ClearFocus() end
    end)

    -- Row 3: Budget Input + Apply + Source/Items Indicator
    local budgetLabel = sideFrame.CreateFontString and sideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if budgetLabel then
        if budgetLabel.SetPoint then budgetLabel:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -98) end
        if budgetLabel.SetText then budgetLabel:SetText("Budget:") end
    end

    local budgetInput = CreateFrame("EditBox", "LL_SideBudgetInput", sideFrame, "InputBoxTemplate")
    if budgetInput.SetSize then budgetInput:SetSize(84, 22) end
    if budgetInput.SetPoint then budgetInput:SetPoint("LEFT", budgetLabel, "RIGHT", 8, 0) end
    if budgetInput.SetAutoFocus then budgetInput:SetAutoFocus(false) end
    budgetInput:SetScript("OnEnterPressed", function(self)
        LL.SideWindow.SetBudget(self:GetText())
        if self.ClearFocus then self:ClearFocus() end
    end)

    local budgetApplyBtn = CreateFrame("Button", "LL_SideBudgetApplyBtn", sideFrame, "UIPanelButtonTemplate")
    if budgetApplyBtn.SetSize then budgetApplyBtn:SetSize(64, 22) end
    if budgetApplyBtn.SetPoint then budgetApplyBtn:SetPoint("LEFT", budgetInput, "RIGHT", 6, 0) end
    if budgetApplyBtn.SetText then budgetApplyBtn:SetText("Apply") end
    budgetApplyBtn:SetScript("OnClick", function()
        LL.SideWindow.SetBudget(budgetInput:GetText())
    end)

    local budgetInfoText = sideFrame.CreateFontString and sideFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if budgetInfoText then
        if budgetInfoText.SetPoint then budgetInfoText:SetPoint("LEFT", budgetApplyBtn, "RIGHT", 6, 0) end
    end

    -- Row 4: Find Cheapest Plays Button + Roadmap Button + Progress Bar
    local findBtn = CreateFrame("Button", "LL_SideFindBtn", sideFrame, "UIPanelButtonTemplate")
    if findBtn.SetSize then findBtn:SetSize(206, 26) end
    if findBtn.SetPoint then findBtn:SetPoint("TOPLEFT", sideFrame, "TOPLEFT", 12, -126) end
    if findBtn.SetText then findBtn:SetText("Find Top 5 Plays") end
    findBtn:SetScript("OnClick", function()
        if LL.AHVerifier.IsRunning() then
            LL.AHVerifier.Stop("USER_STOP")
            return
        end
        local active = LL.RecipeScanner.GetActiveProfession()
        local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
        if scanStatus ~= "READY" then
            LL.SideWindow.TriggerProfessionScan()
            return
        end
        local dataStatus = (LL.GetAHDataStatus and LL.GetAHDataStatus()) or "FRESH"
        local forceLive = (_G.IsShiftKeyDown and _G.IsShiftKeyDown()) == true
        if dataStatus == "NO_DATA" or (dataStatus == "STALE" and not forceLive) then
            LL.SideWindow.TriggerAHScan()
            return
        end
        LL.SideWindow.RunSearch()
    end)

    local roadmapBtn = CreateFrame("Button", "LL_SideRoadmapBtn", sideFrame, "UIPanelButtonTemplate")
    if roadmapBtn.SetSize then roadmapBtn:SetSize(134, 26) end
    if roadmapBtn.SetPoint then roadmapBtn:SetPoint("LEFT", findBtn, "RIGHT", 6, 0) end
    if roadmapBtn.SetText then roadmapBtn:SetText("Milestone Path") end
    roadmapBtn:SetScript("OnClick", function()
        TryAutoSyncActiveProfession()
        local active = LL.RecipeScanner.GetActiveProfession()
        local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
        if scanStatus ~= "READY" then
            LL.SideWindow.TriggerProfessionScan()
            return
        end
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
        if subBanner.SetText then subBanner:SetText("Top 5 Plays (click for Shopping List; right-click or 'x' to snooze):") end
    end

    for i = 1, TOP_ROWS do
        local yOff = -202 - ((i - 1) * 58)
        local btn = CreatePlayRowButton(sideFrame, i, yOff)
        btn:Hide()
        playButtons[i] = btn
    end

    sideFrame.settingsBtn = settingsBtn
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
    LL.SideWindow.ApplyFilterChange()
    if LL.AHVerifier.IsAuctionHouseOpen() then
        LL.SideWindow.RunSearch()
    end
    return true
end

function LL.SideWindow.TriggerAHScan()
    local mode = (LL.GetPriceSourceMode and LL.GetPriceSourceMode()) or "AUTO"
    if mode == "AUCTIONATOR" then
        print("|cffffcc00[Leveling Lad]|r Price Source is set to Auctionator. Run an Auctionator Full Scan at the AH (or switch Price Source to Auto/PCF in Options).")
        return false
    end
    if not LL.AHVerifier.IsAuctionHouseOpen() then
        print("|cffffcc00[Leveling Lad]|r Open the Auction House at any Auctioneer first, then click 'Scan AH Now' (or run an Auctionator Full Scan).")
        return false
    end
    if _G.PCF_DB and type(_G.PCF_DB.settings) == "table" then
        _G.PCF_DB.settings.showScanButton = true
    end
    if _G.PCF and _G.PCF.Scanner and type(_G.PCF.Scanner.StartScan) == "function" then
        _G.PCF.Scanner.StartScan()
        HookPCFScanButtonIfAvailable()
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

function LL.SideWindow.RefreshIfShown()
    if sideFrame and (not sideFrame.IsShown or sideFrame:IsShown()) then
        LL.SideWindow.Refresh()
    else
        LL.SideWindow.RefreshSettingsControls()
    end
end

function LL.SideWindow.Refresh()
    local frame = EnsureSideWindow()
    HookPCFScanButtonIfAvailable()
    LL.SideWindow.RefreshSettingsControls()

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
        local txt = mode == "PLUS5" and "|cff00ff88[+5 Points]|r" or "|cffaaaaaa[+5 Points]|r"
        frame.targetPlus5Btn:SetText(txt)
        if frame.targetPlus5Btn.labelText then
            frame.targetPlus5Btn.labelText:SetText(txt)
        end
        SetBtnBgColor(frame.targetPlus5Btn, mode == "PLUS5" and 0.08 or 0.14, mode == "PLUS5" and 0.32 or 0.16, mode == "PLUS5" and 0.24 or 0.20, 0.94)
    end
    if frame.targetMilestoneBtn then
        local lbl = string.format("Next Tier: %d", nextTier)
        local txt = mode == "MILESTONE" and ("|cff00ff88[" .. lbl .. "]|r") or ("|cffaaaaaa[" .. lbl .. "]|r")
        frame.targetMilestoneBtn:SetText(txt)
        if frame.targetMilestoneBtn.labelText then
            frame.targetMilestoneBtn.labelText:SetText(txt)
        end
        SetBtnBgColor(frame.targetMilestoneBtn, mode == "MILESTONE" and 0.08 or 0.14, mode == "MILESTONE" and 0.32 or 0.16, mode == "MILESTONE" and 0.24 or 0.20, 0.94)
    end
    if frame.targetCustomInput then
        local hasFocus = frame.targetCustomInput.HasFocus and frame.targetCustomInput:HasFocus()
        if not hasFocus then
            local customVal = tonumber(LevelingLad_DB.settings.customTargetSkill)
            if mode == "CUSTOM" and customVal and customVal > 0 then
                frame.targetCustomInput:SetText(tostring(math.floor(customVal)))
            elseif (frame.targetCustomInput:GetText() or "") == "" then
                frame.targetCustomInput:SetText(tostring(LL.GetTargetSkill(active.rank, active.maxRank)))
            end
        end
    end

    local dataStatus, dataInfo = "FRESH", { itemCount = 0, activeSource = "PCF", ageText = "0m" }
    if LL.GetAHDataStatus then
        dataStatus, dataInfo = LL.GetAHDataStatus()
    end
    if frame.budgetInfoText then
        local bStr = isCapped
            and ("Cap: " .. LL.Formatter.FormatMoneyShort(effectiveBudget))
            or ("All: " .. LL.Formatter.FormatMoneyShort(effectiveBudget))
        local srcSuffix = (dataInfo and dataInfo.activeSource == "Auctionator") and " |cff00ccff(Atr)|r" or ""
        frame.budgetInfoText:SetText(bStr .. srcSuffix)
    end

    local scanStatus, scanInfo = "READY", {}
    if LL.RecipeScanner and LL.RecipeScanner.GetProfessionScanStatus then
        scanStatus, scanInfo = LL.RecipeScanner.GetProfessionScanStatus(active.skillLine)
    end

    -- 1. Profession window has not been scanned at current skill rank -> NEVER show outdated green/yellow/orange math!
    if scanStatus ~= "READY" then
        local profName = active.name or "Profession"
        if not LL.AHVerifier.IsRunning() then
            frame.findBtn:SetText("Open " .. profName)
            frame.statusBar:SetMinMaxValues(0, 1)
            frame.statusBar:SetValue(0)
            if scanStatus == "UNSCANNED" then
                frame.statusText:SetText(string.format("Open %s to Scan", profName))
            else
                frame.statusText:SetText(string.format("Rescan %s (Skill %d)", profName, active.rank or 1))
            end
        end
        if frame.subBanner then
            frame.subBanner:SetText(string.format("|cffffcc00Open %s to Calculate Plays:|r", profName))
        end

        local btn1 = playButtons[1]
        if btn1 then
            btn1._play = nil
            btn1._needsProfScan = true
            btn1._needsAHScan = false
            if btn1.snoozeBtn then btn1.snoozeBtn:Hide() end
            btn1:Show()
            btn1.mainText:SetText(string.format("|cffffcc00Open %s to Calculate Plays|r", profName))
            if scanStatus == "UNSCANNED" then
                btn1.subText:SetText(string.format("%s recipes haven't been scanned yet on this character.", profName))
            elseif scanInfo and scanInfo.reason == "NEW_RECIPE_LEARNED" then
                btn1.subText:SetText(string.format("New %s recipe learned — open %s to scan reagents & difficulty.", profName, profName))
            else
                btn1.subText:SetText(string.format(
                    "Skill changed (%d -> %d) — open %s to check green/yellow/orange states.",
                    (scanInfo and scanInfo.scannedRank) or 1,
                    active.rank or 1,
                    profName
                ))
            end
            btn1.extraText:SetText("|cff00ff88Click here (or open your crafting window) to scan now|r")
        end

        for i = 2, TOP_ROWS do
            local b = playButtons[i]
            if b then
                b._play = nil
                b._needsProfScan = false
                b._needsAHScan = false
                if b.snoozeBtn then b.snoozeBtn:Hide() end
                b:Hide()
            end
        end
        return
    end

    -- 2. AH Scan Data Missing or Stale (>24h)
    local pcfScanning = IsPCFScannerRunning()
    if dataStatus == "NO_DATA" or dataStatus == "STALE" then
        local ahOpen = LL.AHVerifier.IsAuctionHouseOpen()
        local sourceMode = (LL.GetPriceSourceMode and LL.GetPriceSourceMode()) or "AUTO"
        if not LL.AHVerifier.IsRunning() then
            if pcfScanning then
                frame.findBtn:SetText("Scanning AH...")
                frame.statusText:SetText("PCF Scan Running")
            elseif dataStatus == "NO_DATA" then
                frame.findBtn:SetText(ahOpen and "Scan AH Now" or "AH Scan Needed")
                frame.statusText:SetText("No AH scan data")
            else
                frame.findBtn:SetText(ahOpen and "Scan AH Now" or "AH Data Stale")
                frame.statusText:SetText("Stale (" .. (dataInfo.ageText or "24h+") .. ")")
            end
            frame.statusBar:SetMinMaxValues(0, 1)
            frame.statusBar:SetValue(0)
        end

        if frame.subBanner then
            if dataStatus == "NO_DATA" then
                frame.subBanner:SetText("|cffffcc00Auction House Scan Required Before Calculating Plays:|r")
            else
                frame.subBanner:SetText(string.format("|cffff9900Auction House Data Is Stale (%s old) — Rescan Required:|r", dataInfo.ageText or "24h+"))
            end
        end

        local btn1 = playButtons[1]
        if btn1 then
            btn1._play = nil
            btn1._needsProfScan = false
            btn1._needsAHScan = true
            if btn1.snoozeBtn then btn1.snoozeBtn:Hide() end
            btn1:Show()
            if pcfScanning then
                btn1.mainText:SetText("|cff00ccffAuction House Scan in Progress...|r")
                btn1.subText:SetText("Wait for PCF Scan to reach 100%, then click 'Find Top 5 Plays'.")
                btn1.extraText:SetText("")
            elseif sourceMode == "AUCTIONATOR" then
                btn1.mainText:SetText(dataStatus == "NO_DATA"
                    and "|cffffcc00Auctionator Data Required: No Scan Found!|r"
                    or string.format("|cffff9900Auctionator Data is Stale (%s old)|r", dataInfo.ageText or "24h+"))
                btn1.subText:SetText("Run an Auctionator Full Scan at the AH (or switch Price Source in Options).")
                btn1.extraText:SetText("")
            elseif dataStatus == "NO_DATA" then
                btn1.mainText:SetText("|cffffcc00No Auction House Data Found|r")
                btn1.subText:SetText(ahOpen
                    and "Click here or 'Scan AH Now' above (or run an Auctionator Full Scan)."
                    or "Open the Auction House and run a PCF or Auctionator scan first.")
                btn1.extraText:SetText("")
            else
                btn1.mainText:SetText(string.format("|cffff9900AH Data is Stale (%s old) — Old Plays Hidden|r", dataInfo.ageText or "24h+"))
                btn1.subText:SetText(ahOpen
                    and "Click here or 'Scan AH Now' above (or run an Auctionator scan) to refresh."
                    or "Open the Auction House at an Auctioneer and run a fresh scan.")
                btn1.extraText:SetText("")
            end
        end

        for i = 2, TOP_ROWS do
            local b = playButtons[i]
            if b then
                b._play = nil
                b._needsProfScan = false
                b._needsAHScan = false
                if b.snoozeBtn then b.snoozeBtn:Hide() end
                b:Hide()
            end
        end
        return
    end

    -- 3. Ready state: render Top 5 non-snoozed plays
    if frame.subBanner then
        frame.subBanner:SetText("Top 5 Plays (click for Shopping List; right-click or 'x' to snooze):")
    end

    if not LL.AHVerifier.IsRunning() then
        frame.findBtn:SetText("Find Top 5 Plays")
        local count = (LevelingLad_DB.lastTopPlays and #LevelingLad_DB.lastTopPlays) or 0
        local srcNote = (dataInfo.activeSource and dataInfo.activeSource ~= "None") and (" | " .. dataInfo.activeSource) or ""
        frame.statusText:SetText(string.format("Top %d Ready (Target: %d%s)", count, LL.GetTargetSkill(active.rank, active.maxRank), srcNote))
        frame.statusBar:SetMinMaxValues(0, 1)
        frame.statusBar:SetValue(1)
    end

    local plays = (LevelingLad_DB and LevelingLad_DB.lastTopPlays) or {}
    for i = 1, TOP_ROWS do
        local btn = playButtons[i]
        local play = plays[i]
        if play then
            btn._play = play
            btn._needsProfScan = false
            btn._needsAHScan = false
            btn:Show()
            if btn.snoozeBtn then btn.snoozeBtn:Show() end
            local badge = LL.Formatter.FormatDifficultyBadge(play.startDifficulty, play.endDifficulty)
            local trainerLabel = (play.source and play.source ~= "" and play.source ~= "Known") and play.source or "Trainer"
            local trainerTag = play.needsTrainer and string.format(" |cff00ccff[%s]|r", trainerLabel) or ""
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
            btn._needsProfScan = false
            btn._needsAHScan = false
            if btn.snoozeBtn then btn.snoozeBtn:Hide() end
            if i == 1 and #plays == 0 then
                btn:Show()
                local snoozedCount = LL.GetActiveSnoozedPlays and #LL.GetActiveSnoozedPlays() or 0
                if snoozedCount > 0 then
                    btn.mainText:SetText("|cffaaaaaaNo un-snoozed leveling plays found.|r")
                    btn.subText:SetText(string.format("%d play(s) snoozed — click 'Options' or /ll unhide to restore.", snoozedCount))
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
    TryAutoSyncActiveProfession()

    local active = LL.RecipeScanner.GetActiveProfession()
    local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
    if scanStatus ~= "READY" then
        if LevelingLad_DB then
            LevelingLad_DB.lastTopPlays = {}
        end
        LL.SideWindow.Refresh()
        return {}
    end

    local dataStatus = (LL.GetAHDataStatus and LL.GetAHDataStatus()) or "FRESH"
    if dataStatus == "NO_DATA" then
        if LevelingLad_DB then
            LevelingLad_DB.lastTopPlays = {}
        end
        LL.SideWindow.Refresh()
        return {}
    end

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
        TryAutoSyncActiveProfession()
        local active = LL.RecipeScanner.GetActiveProfession()
        local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
        local dataStatus = (LL.GetAHDataStatus and LL.GetAHDataStatus()) or "FRESH"
        if scanStatus == "READY" and dataStatus == "FRESH"
            and (not LevelingLad_DB.lastTopPlays or #LevelingLad_DB.lastTopPlays == 0)
            and not LL.AHVerifier.IsRunning() then
            LL.AHVerifier.RecalculateFromCache(active.skillLine)
        end
        AnchorToAuctionHouse()
        frame:Show()
        if frame.Raise then frame:Raise() end
        LL.SideWindow.Refresh()
    end
end

-- ============================================================================
-- Top-Left Auction House Toggle Button ("Leveling Lad")
-- ============================================================================

function LL.SideWindow.UpdateAHToggleButtonAnchor()
    if not ahToggleButton or not ahToggleButton.SetPoint then return end
    local parent = (ahToggleButton.GetParent and ahToggleButton:GetParent()) or GetActiveAuctionHouseFrame()
    if not parent then return end

    if ahToggleButton.ClearAllPoints then
        ahToggleButton:ClearAllPoints()
    end
    -- Anchor on the top-left of the Auction House browser immediately beside the circular portrait icon
    -- (mirroring PCF Scan & Profitable on TOPRIGHT so neither side overlaps).
    local isLegacyFrame = (_G.AuctionFrame ~= nil and parent == _G.AuctionFrame)
    local offsetX = isLegacyFrame and 70 or 60
    local offsetY = isLegacyFrame and -13 or -3
    ahToggleButton:SetPoint("TOPLEFT", parent, "TOPLEFT", offsetX, offsetY)
end

function LL.SideWindow.EnsureAHToggleButton()
    local parent = GetActiveAuctionHouseFrame()
    if not parent then return nil end

    if ahToggleButton then
        if ahToggleButton.GetParent and ahToggleButton:GetParent() ~= parent and ahToggleButton.SetParent then
            ahToggleButton:SetParent(parent)
        end
        LL.SideWindow.UpdateAHToggleButtonAnchor()
        ahToggleButton:Show()
        return ahToggleButton
    end

    ahToggleButton = CreateFrame("Button", "LL_AuctionToggleButton", parent, "UIPanelButtonTemplate")
    if ahToggleButton.SetSize then ahToggleButton:SetSize(92, 20) end
    if ahToggleButton.SetFrameStrata then ahToggleButton:SetFrameStrata("HIGH") end
    if ahToggleButton.SetText then ahToggleButton:SetText("Leveling Lad") end
    if ahToggleButton.RegisterForClicks then
        pcall(ahToggleButton.RegisterForClicks, ahToggleButton, "LeftButtonUp", "RightButtonUp")
    end

    ahToggleButton:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then
            LL.SideWindow.ToggleSettingsWindow()
        else
            LL.SideWindow.Toggle()
        end
    end)
    ahToggleButton:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        _G.GameTooltip:AddLine("|cff00ccffLeveling Lad (LL)|r", 1, 1, 1)
        _G.GameTooltip:AddLine("|cff00ff88Left-Click:|r Open / Close Leveling Lad on the left of the AH.", 1, 1, 1, true)
        _G.GameTooltip:AddLine("|cff88ccffRight-Click:|r Open Options, Price Source & Snoozed Plays.", 0.8, 0.9, 1, true)
        _G.GameTooltip:Show()
    end)
    ahToggleButton:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)

    LL.SideWindow.UpdateAHToggleButtonAnchor()
    ahToggleButton:Show()
    LL.SideWindow.ahToggleButton = ahToggleButton
    return ahToggleButton
end

-- ============================================================================
-- LibDBIcon-1.0 / OneForAll-Compatible Minimap Button
-- ============================================================================

local function PopulateMinimapTooltip(tooltip)
    if not tooltip or not tooltip.AddLine then return end
    tooltip:AddLine("|cff00ccffLeveling Lad (LL)|r", 1, 1, 1)
    local active = LL.RecipeScanner.GetActiveProfession()
    tooltip:AddLine(string.format("Profession: |cffffd100%s (%d/%d)|r", active.name or "Blacksmithing", active.rank or 1, active.maxRank or 75), 0.9, 0.9, 0.9)
    local status, info = "NO_DATA", {}
    if LL.GetAHDataStatus then
        status, info = LL.GetAHDataStatus()
    end
    if status == "FRESH" then
        tooltip:AddLine(string.format("AH Data: |cff00ff88%d items (%s, %s old)|r", info.itemCount or 0, info.activeSource or "PCF", info.ageText or "0m"), 0.85, 0.85, 0.85)
    elseif status == "STALE" then
        tooltip:AddLine(string.format("AH Data: |cffff9900Stale (%s old)|r", info.ageText or "24h+"), 1, 0.65, 0.2)
    else
        tooltip:AddLine("AH Data: |cffff5555No AH scan data yet|r", 1, 0.4, 0.4)
    end
    local snoozedCount = LL.GetActiveSnoozedPlays and #LL.GetActiveSnoozedPlays() or 0
    if snoozedCount > 0 then
        tooltip:AddLine(string.format("Snoozed Top 5 Plays: |cffffd100%d|r", snoozedCount), 0.85, 0.85, 0.85)
    end
    tooltip:AddLine(" ")
    tooltip:AddLine("|cff00ff88Left-Click:|r Toggle Leveling Lad Window", 0.9, 0.9, 0.9)
    tooltip:AddLine("|cff88ccffRight-Click:|r Open Options", 0.9, 0.9, 0.9)
    tooltip:AddLine("|cffffd100Shift-Left-Click:|r Find Top 5 Plays", 0.9, 0.9, 0.9)
    tooltip:AddLine("|cffaaaaaaDrag:|r Move around Minimap", 0.7, 0.7, 0.7)
end

local function OnMinimapButtonClick(_, mouseButton)
    if mouseButton == "RightButton" then
        LL.SideWindow.ToggleSettingsWindow()
    elseif _G.IsShiftKeyDown and _G.IsShiftKeyDown() then
        local frame = EnsureSideWindow()
        AnchorToAuctionHouse()
        frame:Show()
        LL.SideWindow.RunSearch()
    else
        LL.SideWindow.Toggle()
    end
end

local function PositionMinimapButtonByAngle(btn, angleDeg)
    if not btn or not btn.SetPoint or not _G.Minimap then return end
    local rad = math.rad(tonumber(angleDeg) or 195)
    local radius = 80
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    if btn.ClearAllPoints then btn:ClearAllPoints() end
    btn:SetPoint("CENTER", _G.Minimap, "CENTER", x, y)
end

function LL.SideWindow.InitMinimapButton()
    if minimapButton then
        return minimapButton
    end

    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.settings = LevelingLad_DB.settings or {}
    if type(LevelingLad_DB.settings.minimap) ~= "table" then
        LevelingLad_DB.settings.minimap = { hide = false, minimapPos = 195 }
    end
    local minimapDB = LevelingLad_DB.settings.minimap
    if minimapDB.minimapPos == nil then
        minimapDB.minimapPos = 195
    end

    local dataObject = {
        type = "launcher",
        label = "Leveling Lad",
        text = "Leveling Lad",
        icon = "Interface\\Icons\\INV_Hammer_20",
        OnClick = OnMinimapButtonClick,
        OnTooltipShow = PopulateMinimapTooltip,
    }

    if _G.LibStub then
        local okLDB, ldb = pcall(_G.LibStub, "LibDataBroker-1.1", true)
        local okIcon, ldbIcon = pcall(_G.LibStub, "LibDBIcon-1.0", true)
        if okLDB and ldb and okIcon and ldbIcon and type(ldb.NewDataObject) == "function" and type(ldbIcon.Register) == "function" then
            local registeredObj = (ldb.GetDataObjectByName and ldb:GetDataObjectByName("LevelingLad"))
                or ldb:NewDataObject("LevelingLad", dataObject)
            if registeredObj then
                local alreadyReg = ldbIcon.IsRegistered and ldbIcon:IsRegistered("LevelingLad")
                if not alreadyReg then
                    pcall(ldbIcon.Register, ldbIcon, "LevelingLad", registeredObj, minimapDB)
                end
                minimapUsesLibDBIcon = true
                minimapButton = (ldbIcon.GetMinimapButton and ldbIcon:GetMinimapButton("LevelingLad"))
                    or _G["LibDBIcon10_LevelingLad"]
                if minimapDB.hide and ldbIcon.Hide then
                    pcall(ldbIcon.Hide, ldbIcon, "LevelingLad")
                elseif not minimapDB.hide and ldbIcon.Show then
                    pcall(ldbIcon.Show, ldbIcon, "LevelingLad")
                end
                LL.SideWindow.minimapButton = minimapButton
                return minimapButton
            end
        end
    end

    local parent = _G.Minimap or _G.UIParent
    local btn = CreateFrame("Button", "LibDBIcon10_LevelingLad", parent)
    if btn.SetSize then btn:SetSize(31, 31) end
    if btn.SetFrameStrata then btn:SetFrameStrata("MEDIUM") end
    if btn.SetFrameLevel then pcall(btn.SetFrameLevel, btn, 8) end
    if btn.SetMovable then btn:SetMovable(true) end
    if btn.EnableMouse then btn:EnableMouse(true) end
    if btn.RegisterForClicks then
        pcall(btn.RegisterForClicks, btn, "LeftButtonUp", "RightButtonUp")
    end
    if btn.RegisterForDrag then
        pcall(btn.RegisterForDrag, btn, "LeftButton")
    end
    if btn.SetHighlightTexture then
        pcall(btn.SetHighlightTexture, btn, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    end

    if btn.CreateTexture then
        local overlay = btn:CreateTexture(nil, "OVERLAY")
        if overlay then
            if overlay.SetSize then overlay:SetSize(53, 53) end
            if overlay.SetTexture then overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder") end
            if overlay.SetPoint then overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0) end
            btn.overlay = overlay
        end

        local background = btn:CreateTexture(nil, "BACKGROUND")
        if background then
            if background.SetSize then background:SetSize(20, 20) end
            if background.SetTexture then background:SetTexture("Interface\\Minimap\\UI-Minimap-Background") end
            if background.SetPoint then background:SetPoint("TOPLEFT", btn, "TOPLEFT", 7, -5) end
            btn.background = background
        end

        local icon = btn:CreateTexture(nil, "ARTWORK")
        if icon then
            if icon.SetSize then icon:SetSize(17, 17) end
            if icon.SetTexture then icon:SetTexture("Interface\\Icons\\INV_Hammer_20") end
            if icon.SetPoint then icon:SetPoint("CENTER", btn, "CENTER", 0, 0) end
            if icon.SetTexCoord then pcall(icon.SetTexCoord, icon, 0.05, 0.95, 0.05, 0.95) end
            btn.icon = icon
        end
    end

    btn.dataObject = dataObject
    btn.db = minimapDB

    btn:SetScript("OnClick", OnMinimapButtonClick)
    btn:SetScript("OnEnter", function(self)
        if not _G.GameTooltip then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        PopulateMinimapTooltip(_G.GameTooltip)
        _G.GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end)
    btn:SetScript("OnDragStart", function(self)
        if self.GetParent and _G.Minimap and self:GetParent() ~= _G.Minimap then
            return
        end
        if self.SetScript then
            self:SetScript("OnUpdate", function(frame)
                if not _G.Minimap or not _G.GetCursorPosition or not _G.Minimap.GetCenter then
                    return
                end
                local mx, my = _G.Minimap:GetCenter()
                local cx, cy = _G.GetCursorPosition()
                local scale = (_G.Minimap.GetEffectiveScale and _G.Minimap:GetEffectiveScale()) or 1
                cx, cy = cx / scale, cy / scale
                if mx and my then
                    local angle = math.deg(math.atan2(cy - my, cx - mx))
                    minimapDB.minimapPos = angle
                    PositionMinimapButtonByAngle(frame, angle)
                end
            end)
        end
    end)
    btn:SetScript("OnDragStop", function(self)
        if self.SetScript then
            self:SetScript("OnUpdate", nil)
        end
    end)

    PositionMinimapButtonByAngle(btn, minimapDB.minimapPos)
    if minimapDB.hide then
        btn:Hide()
    else
        btn:Show()
    end

    minimapButton = btn
    LL.SideWindow.minimapButton = minimapButton
    return minimapButton
end

function LL.SideWindow.Init()
    if LL.SideWindow._initialized then return end
    LL.SideWindow._initialized = true

    LL.SideWindow.InitMinimapButton()

    if eventFrame.RegisterEvent then
        pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_SHOW")
        pcall(eventFrame.RegisterEvent, eventFrame, "AUCTION_HOUSE_CLOSED")
        pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_MONEY")
        eventFrame:SetScript("OnEvent", function(_, event)
            if event == "AUCTION_HOUSE_SHOW" then
                HookPCFScanButtonIfAvailable()
                LL.RecipeScanner.ScanCurrentProfessionWindow()
                LL.SideWindow.EnsureAHToggleButton()
                if _G.C_Timer and _G.C_Timer.After then
                    _G.C_Timer.After(0, function()
                        HookPCFScanButtonIfAvailable()
                        LL.SideWindow.UpdateAHToggleButtonAnchor()
                    end)
                end
                if LevelingLad_DB and LevelingLad_DB.settings and LevelingLad_DB.settings.showSideWindow == true then
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
