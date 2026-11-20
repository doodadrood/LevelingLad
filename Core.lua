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
            print(string.format("|cff00ccff[Leveling Lad]|r Top %d cheapest leveling plays:", #(plays or {})))
            for i, p in ipairs(plays or {}) do
                print("  " .. (p.summaryLine or LL.LevelingEngine.FormatPlaySummary(i, p)))
            end
        elseif cmd == "roadmap" or cmd == "plan" then
            local active = LL.RecipeScanner.GetActiveProfession()
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
                print("|cff00ccff[Leveling Lad]|r Target mode set to +5 skill points.")
                LL.SideWindow.RunSearch()
            elseif arg == "+10" or arg == "plus10" then
                LevelingLad_DB.settings.targetMode = "PLUS10"
                LevelingLad_DB.settings.targetSkillRank = 0
                print("|cff00ccff[Leveling Lad]|r Target mode set to +10 skill points.")
                LL.SideWindow.RunSearch()
            elseif arg == "milestone" or arg == "next" then
                LevelingLad_DB.settings.targetMode = "MILESTONE"
                LevelingLad_DB.settings.targetSkillRank = 0
                print("|cff00ccff[Leveling Lad]|r Target mode set to Next Milestone (75/150/225/300).")
                LL.SideWindow.RunSearch()
            elseif tonumber(arg) then
                local n = math.max(2, math.min(300, math.floor(tonumber(arg))))
                LevelingLad_DB.settings.targetMode = "CUSTOM"
                LevelingLad_DB.settings.customTargetSkill = n
                LevelingLad_DB.settings.targetSkillRank = n
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
                print(string.format("|cff00ccff[Leveling Lad]|r Selected profession: %s.", LL.RecipeDatabase.GetProfessionName(skillLine)))
                LL.SideWindow.RunSearch()
            else
                print("|cffff5555[Leveling Lad]|r Unknown profession. Try: blacksmithing, tailoring, leatherworking, alchemy, engineering, cooking, enchanting, first aid.")
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
            print("  /ll budget X         - Cap leveling budget (e.g. '/ll budget 25g' or 'auto')")
            print("  /ll target X         - Set goal (+5, +10, milestone, or skill rank 1-300)")
            print("  /ll recovery X       - Set resale recovery strategy (vendor, ah, none)")
            print("  /ll prof <name>      - Select profession to optimize")
            print("  /ll scan             - Scan AH (when open) or recalculate plays")
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
    print("|cff00ccffLeveling Lad (LL) loaded.|r Open the Auction House or type /ll to find the cheapest leveling plays.")
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
