local addonName = ...
local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL_API = _G.LL_API or {}
_G.LL_API = LL_API
_G.LevelingLad_API = LL_API

function LL_API.FindTopPlays(professionOrLine, currentSkill, targetSkill, options)
    return LL.LevelingEngine.FindTopPlays(professionOrLine, currentSkill, targetSkill, options)
end

function LL_API.PlanMilestonePath(professionOrLine, startSkill, targetSkill, options)
    return LL.LevelingEngine.PlanMilestonePath(professionOrLine, startSkill, targetSkill, options)
end

function LL_API.ShowPlay(indexOrPlay)
    if type(indexOrPlay) == "number" then
        local plays = LevelingLad_DB and LevelingLad_DB.lastTopPlays
        local play = plays and plays[indexOrPlay]
        if play then
            LL.DetailWindow.ShowPlay(play)
            return true
        end
        return false
    elseif type(indexOrPlay) == "table" then
        LL.DetailWindow.ShowPlay(indexOrPlay)
        return true
    end
    return false
end

function LL_API.IsReady()
    return _G.LL_INITIALIZED == true
        and type(LevelingLad_DB) == "table"
        and type(LL.LevelingEngine) == "table"
end

local function RegisterSlashCommands()
    SLASH_LEVELINGLAD1 = "/ll"
    SLASH_LEVELINGLAD2 = "/levelinglad"
    SlashCmdList["LEVELINGLAD"] = function(msg)
        local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
        if cmd == "" or cmd == "toggle" or cmd == "show" then
            LL.SideWindow.Toggle()
        elseif cmd == "run" or cmd == "find" then
            local plays = LL.SideWindow.RunSearch()
            if #(plays or {}) > 0 then
                print(string.format("|cff00ccff[Leveling Lad]|r Top %d cheapest leveling plays:", #(plays or {})))
                for i, p in ipairs(plays or {}) do
                    print("  " .. (p.summaryLine or LL.LevelingEngine.FormatPlaySummary(i, p)))
                end
            else
                local active = LL.RecipeScanner.GetActiveProfession()
                local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
                if scanStatus ~= "READY" then
                    print(string.format("|cffffcc00[Leveling Lad]|r Open %s first so Leveling Lad can scan live orange/yellow/green recipes!", active.name or "Profession"))
                end
            end
        elseif cmd == "roadmap" or cmd == "plan" then
            local active = LL.RecipeScanner.GetActiveProfession()
            local scanStatus = LL.RecipeScanner.GetProfessionScanStatus and LL.RecipeScanner.GetProfessionScanStatus(active.skillLine) or "READY"
            if scanStatus ~= "READY" then
                print(string.format("|cffffcc00[Leveling Lad]|r Open %s first to scan live WoW: Forever recipes before building a Milestone Path.", active.name or "Profession"))
                LL.SideWindow.TriggerProfessionScan()
                return
            end
            local customGoal = tonumber(arg)
            local goal = LL.GetTargetSkill(active.rank, active.maxRank, customGoal)
            local roadmap = LL.LevelingEngine.PlanMilestonePath(active.skillLine, active.rank, goal)
            LevelingLad_DB.lastRoadmap = roadmap
            LL.DetailWindow.ShowRoadmap(roadmap)
            print(string.format(
                "|cff00ccff[Leveling Lad]|r %s Roadmap (%d -> %d): %d steps, Est. Net Cost: %s",
                roadmap.profession, roadmap.startSkill, roadmap.reachedSkill, #(roadmap.steps or {}),
                LL.Formatter.FormatNetCost(roadmap.totalNetCost)
            ))
            for _, step in ipairs(roadmap.steps or {}) do
                print(string.format("  Step %d: %s — Craft %dx (%d->%d) | %s",
                    step.stepNumber, step.recipeName, step.expectedCrafts,
                    step.startSkill, step.targetSkill, LL.Formatter.FormatNetCost(step.netCost, true)
                ))
            end
        elseif cmd == "detail" or tonumber(cmd) then
            local idx = tonumber(cmd) or tonumber(arg) or 1
            if not LL_API.ShowPlay(idx) then
                print(string.format("|cffff5555[Leveling Lad]|r Play #%d not found. Run /ll run first.", idx))
            end
        elseif cmd == "options" or cmd == "settings" or cmd == "config" then
            LL.SideWindow.ToggleSettingsWindow()
        elseif cmd == "source" or cmd == "pricesource" then
            if not arg or arg == "" then
                local mode = (LL.GetPriceSourceMode and LL.GetPriceSourceMode()) or "AUTO"
                local _, info = LL.GetAHDataStatus()
                print(string.format(
                    "|cff00ccff[Leveling Lad]|r Price Data Source: %s (Active: %s, %d items). Use '/ll source auto', '/ll source pcf', or '/ll source auctionator'.",
                    mode, (info and info.activeSource) or "None", (info and info.itemCount) or 0
                ))
            else
                LL.SideWindow.SetPriceSource(arg)
            end
        elseif cmd == "autoopen" then
            LevelingLad_DB.settings.showSideWindow = not (LevelingLad_DB.settings.showSideWindow == true)
            LL.SideWindow.RefreshSettingsControls()
            print(string.format("|cff00ccff[Leveling Lad]|r Auto-Open Side Window at AH: %s", LevelingLad_DB.settings.showSideWindow and "ON" or "OFF"))
        elseif cmd == "minimap" then
            local curHidden = LevelingLad_DB.settings.minimap and LevelingLad_DB.settings.minimap.hide == true
            local nowShown = LL.SideWindow.SetMinimapButtonShown(curHidden)
            print(string.format("|cff00ccff[Leveling Lad]|r Minimap Button: %s", nowShown and "SHOWN" or "HIDDEN"))
        elseif cmd == "buyout" or cmd == "buyoutonly" then
            LevelingLad_DB.settings.buyoutOnly = not (LevelingLad_DB.settings.buyoutOnly ~= false)
            LL.SideWindow.ApplyFilterChange()
            print(string.format("|cff00ccff[Leveling Lad]|r Buyout Only (Exclude Bid-Only Auctions): %s", LevelingLad_DB.settings.buyoutOnly and "ON" or "OFF"))
        elseif cmd == "snooze" or cmd == "hidden" or cmd == "snoozed" then
            LL.SideWindow.ToggleSnoozedWindow()
        elseif cmd == "clearhidden" or cmd == "clearsnooze" then
            local cleared = (LL.ClearAllSnoozedPlays and LL.ClearAllSnoozedPlays()) or 0
            LL.SideWindow.ApplySnoozeChange()
            print(string.format("|cff00ccff[Leveling Lad]|r Restored %d snoozed/hidden plays.", cleared))
        elseif cmd == "unhide" or cmd == "unsnooze" then
            if not arg or arg == "" or arg == "all" then
                local cleared = (LL.ClearAllSnoozedPlays and LL.ClearAllSnoozedPlays()) or 0
                LL.SideWindow.ApplySnoozeChange()
                print(string.format("|cff00ccff[Leveling Lad]|r Restored %d snoozed/hidden plays.", cleared))
            else
                local removed, entry = LL.UnsnoozePlay(arg)
                if removed then
                    LL.SideWindow.ApplySnoozeChange()
                    print(string.format("|cff00ccff[Leveling Lad]|r Restored %s.", (entry and (entry.itemLink or entry.itemName)) or arg))
                else
                    print(string.format("|cffff9900[Leveling Lad]|r No snoozed play matched '%s'. Use '/ll hidden' to view or '/ll unhide all'.", arg))
                end
            end
        elseif cmd == "budget" then
            if not arg or arg == "" then
                local eff, isCapped, wallet = LL.GetEffectiveBudget()
                print(string.format(
                    "|cff00ccff[Leveling Lad]|r Effective Budget: %s (%s, Wallet: %s). Use '/ll budget 25g' or '/ll budget auto'.",
                    LL.Formatter.FormatMoney(eff), isCapped and "Capped" or "All Gold", LL.Formatter.FormatMoney(wallet)
                ))
            else
                LL.SideWindow.SetBudget(arg)
            end
        elseif cmd == "target" then
            if arg == "+5" or arg == "plus5" then
                LevelingLad_DB.settings.targetMode = "PLUS5"
                LevelingLad_DB.settings.targetSkillRank = 0
                if LL.SyncActivePlayWithGoal then LL.SyncActivePlayWithGoal() end
                print("|cff00ccff[Leveling Lad]|r Target mode set to +5 skill points.")
                LL.SideWindow.RunSearch()
            elseif arg == "+10" or arg == "plus10" then
                LevelingLad_DB.settings.targetMode = "PLUS10"
                LevelingLad_DB.settings.targetSkillRank = 0
                if LL.SyncActivePlayWithGoal then LL.SyncActivePlayWithGoal() end
                print("|cff00ccff[Leveling Lad]|r Target mode set to +10 skill points.")
                LL.SideWindow.RunSearch()
            elseif arg == "milestone" or arg == "next" then
                LevelingLad_DB.settings.targetMode = "MILESTONE"
                LevelingLad_DB.settings.targetSkillRank = 0
                if LL.SyncActivePlayWithGoal then LL.SyncActivePlayWithGoal() end
                print("|cff00ccff[Leveling Lad]|r Target mode set to Next Milestone (75/150/225/300).")
                LL.SideWindow.RunSearch()
            elseif tonumber(arg) then
                local n = math.max(2, math.min(300, math.floor(tonumber(arg))))
                LevelingLad_DB.settings.targetMode = "CUSTOM"
                LevelingLad_DB.settings.customTargetSkill = n
                LevelingLad_DB.settings.targetSkillRank = n
                if LL.SyncActivePlayWithGoal then LL.SyncActivePlayWithGoal(n) end
                print(string.format("|cff00ccff[Leveling Lad]|r Target skill set to %d.", n))
                LL.SideWindow.RunSearch()
            else
                print("|cffffcc00[Leveling Lad]|r Usage: /ll target <+5|+10|milestone|NUMBER>")
            end
        elseif cmd == "recovery" then
            local m = (arg or ""):upper()
            if m == "VENDOR" or m == "AH" or m == "NONE" then
                LevelingLad_DB.settings.recoveryMode = m
                print(string.format("|cff00ccff[Leveling Lad]|r Recovery mode set to %s.", m))
                LL.SideWindow.RunSearch()
            else
                print("|cffffcc00[Leveling Lad]|r Usage: /ll recovery <vendor|ah|none>")
            end
        elseif cmd == "prof" or cmd == "profession" then
            local skillLine = LL.RecipeDatabase.ResolveSkillLineId(arg)
            if skillLine then
                LevelingLad_DB.settings.selectedProfession = skillLine
                if LL.SyncActivePlayWithGoal then LL.SyncActivePlayWithGoal() end
                print(string.format("|cff00ccff[Leveling Lad]|r Selected profession: %s.", LL.RecipeDatabase.GetProfessionName(skillLine)))
                LL.SideWindow.RunSearch()
            else
                print("|cffff5555[Leveling Lad]|r Unknown profession. Try: blacksmithing, tailoring, leatherworking, alchemy, engineering, cooking, enchanting, first aid.")
            end
        elseif cmd == "debug" then
            if LL.RecipeScanner and LL.RecipeScanner.DebugDump then
                LL.RecipeScanner.DebugDump()
            end
        elseif cmd == "scan" then
            local status = LL.GetAHDataStatus and LL.GetAHDataStatus() or "FRESH"
            if (status == "NO_DATA" or status == "STALE") and LL.AHVerifier.IsAuctionHouseOpen() then
                LL.SideWindow.TriggerAHScan()
            else
                LL.SideWindow.RunSearch()
            end
        else
            print("|cff00ccffLeveling Lad (LL) Commands:|r")
            print("  /ll                  - Toggle the Leveling Lad AH side window")
            print("  /ll run              - Calculate and display Top 5 cheapest leveling plays")
            print("  /ll roadmap [target] - Plan a multi-step milestone path (e.g. 1->75)")
            print("  /ll detail N         - Open the shopping & crafting tracker for play #1-#5")
            print("  /ll options          - Open Options, Price Source & Snoozed Plays panel")
            print("  /ll source X         - Set price source: auto (freshest), pcf, or auctionator")
            print("  /ll autoopen         - Toggle auto-opening Leveling Lad when visiting the AH")
            print("  /ll minimap          - Show or hide the Minimap button")
            print("  /ll hidden           - View & restore snoozed Top 5 plays (or '/ll unhide all')")
            print("  /ll budget X         - Cap leveling budget (e.g. '/ll budget 25g' or 'auto')")
            print("  /ll target X         - Set goal (+5, +10, milestone, or skill rank 1-300)")
            print("  /ll recovery X       - Set resale recovery strategy (vendor, ah, none)")
            print("  /ll prof <name>      - Select profession to optimize")
            print("  /ll scan             - Scan AH (when open) or recalculate plays")
            print("  /ll debug            - Dump live WoW: Forever C_TradeSkillUI recipe difficulty info")
        end
    end
end

local function IsStandalonePCFLoaded()
    if LL._standalonePCFActive == true then
        return true
    end
    local isLoadedFn = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if type(isLoadedFn) == "function" then
        local ok, loaded = pcall(isLoadedFn, "PriceCheckerForever")
        if ok and loaded then return true end
    end
    return false
end

local function ConfigureEmbeddedPCF()
    if LL._embeddedPCFActive and not IsStandalonePCFLoaded() then
        if not _G.PCF_INITIALIZED and _G.PCF and type(_G.PCF.Initialize) == "function" then
            _G.PCF.Initialize()
        end
        LevelingLad_DB.embeddedPCF = (type(LevelingLad_DB.embeddedPCF) == "table" and LevelingLad_DB.embeddedPCF) or {}
        if _G.PCF_API and type(_G.PCF_API.SetSavedVariables) == "function" then
            _G.PCF_API.SetSavedVariables(LevelingLad_DB.embeddedPCF)
        elseif _G.PCF and type(_G.PCF.LoadConfig) == "function" then
            _G.PCF.LoadConfig(LevelingLad_DB.embeddedPCF)
        end
    end

    local sourceMode = (LL.GetPriceSourceMode and LL.GetPriceSourceMode()) or "AUTO"
    if _G.PCF_DB and type(_G.PCF_DB.settings) == "table" and not _G.PCF_DB.settings.userSetScanButton then
        local desiredShow = (sourceMode ~= "AUCTIONATOR")
        if _G.PCF_DB.settings.showScanButton ~= desiredShow then
            _G.PCF_DB.settings.showScanButton = desiredShow
            if _G.PCF and _G.PCF.Scanner and type(_G.PCF.Scanner.UpdateVisibility) == "function" then
                _G.PCF.Scanner.UpdateVisibility()
            end
        end
    end
end

function LL.Initialize()
    if _G.LL_INITIALIZED then
        return false
    end
    _G.LL_INITIALIZED = true

    LL.LoadConfig()
    ConfigureEmbeddedPCF()
    if LL.VendorDatabase and LL.VendorDatabase.Init then
        LL.VendorDatabase.Init()
    end
    if LL.AuctionatorSource and LL.AuctionatorSource.Init then
        LL.AuctionatorSource.Init()
    end
    if LL.RecipeScanner and LL.RecipeScanner.Init then
        LL.RecipeScanner.Init()
    end
    if LL.AHVerifier and LL.AHVerifier.Init then
        LL.AHVerifier.Init()
    end
    if LL.DetailWindow and LL.DetailWindow.Init then
        LL.DetailWindow.Init()
    end
    if LL.SideWindow and LL.SideWindow.Init then
        LL.SideWindow.Init()
    end

    RegisterSlashCommands()
    print("|cff00ccffLeveling Lad (LL) loaded.|r Click 'Leveling Lad' on the top-left of the Auction House or type /ll to find the cheapest leveling plays.")
    return true
end

if _G.LL_INITIALIZED then
    return
end

local coreFrame = CreateFrame("Frame")
coreFrame:RegisterEvent("ADDON_LOADED")
if coreFrame.RegisterEvent then
    pcall(coreFrame.RegisterEvent, coreFrame, "PLAYER_LOGIN")
end

coreFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon ~= addonName and loadedAddon ~= "LevelingLad" then
        return
    end
    if _G.LL_INITIALIZED then
        self:UnregisterEvent("ADDON_LOADED")
        pcall(self.UnregisterEvent, self, "PLAYER_LOGIN")
        return
    end
    LL.Initialize()
    self:UnregisterEvent("ADDON_LOADED")
    pcall(self.UnregisterEvent, self, "PLAYER_LOGIN")
end)

LL.coreFrame = coreFrame
