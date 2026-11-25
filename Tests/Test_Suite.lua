package.path = package.path .. ";../?.lua;./?.lua"

local Mock = require("Tests.MockWoW")

-- Setup PriceCheckerForever Mock DB
_G.PCF_DB = {
    prices = {},
    lastFullScan = Mock.currentTime,
}

require("Modules.PCFEmbedPre")
require("Modules.PCFEmbedPost")
require("Config")
require("Utils.Formatter")
require("Data.VendorDatabase")
require("Data.RecipeDatabase")
require("Modules.RecipeScanner")
require("Modules.LevelingEngine")
require("Modules.AHVerifier")
require("UI.DetailWindow")
require("UI.SideWindow")
require("Core")

LL.Initialize()

local passed = 0
local failed = 0

local function Assert(condition, testName)
    if condition then
        passed = passed + 1
        print(string.format("[PASS] %s", testName))
    else
        failed = failed + 1
        print(string.format("[FAIL] %s", testName))
        error("Test assertion failed: " .. tostring(testName))
    end
end

print("================================================================")
print(" Leveling Lad (LL) — Strictly WoW: Forever LuaJIT Test Suite")
print("================================================================")

-- 1. Core Initialization & API Readiness
Assert(LL_API.IsReady() == true, "LL_API.IsReady() returns true after Initialize()")
Assert(type(_G.SlashCmdList["LEVELINGLAD"]) == "function", "Slash commands /ll and /levelinglad registered")

-- 2. Formatter Tests (Gold/Silver/Copper colors, Badges, Links)
Assert(LL.Formatter.FormatMoneyPlain(220000) == "22g", "FormatMoneyPlain 22g")
Assert(LL.Formatter.FormatMoneyPlain(24550) == "2g 45s 50c", "FormatMoneyPlain 2g 45s 50c")
Assert(LL.Formatter.FormatMoney(10203) == "1|cffffd700g|r 2|cffc7c7cfs|r 3|cffeda55fc|r",
    "FormatMoney emits |cffffd700g|r, |cffc7c7cfs|r, |cffeda55fc|r color codes")
Assert(LL.Formatter.FormatDifficultyBadge("ORANGE", "YELLOW"):find("Orange") ~= nil
    and LL.Formatter.FormatDifficultyBadge("ORANGE", "YELLOW"):find("Yellow") ~= nil,
    "FormatDifficultyBadge renders Orange -> Yellow progression badge")
Assert(LL.Formatter.BuildItemLink(2835, "Rough Stone"):find("|Hitem:2835:") ~= nil,
    "BuildItemLink creates valid WoW hyperlink")

-- 3. Config Parsing & Target Milestone Helpers
Assert(LL.ParseGoldToCopper("25g") == 250000, "ParseGoldToCopper('25g') == 250000c")
Assert(LL.ParseGoldToCopper("1g 50s 25c") == 15025, "ParseGoldToCopper('1g 50s 25c') == 15025c")
Assert(LL.ParseGoldToCopper("auto") == 0, "ParseGoldToCopper('auto') == 0 (all gold)")
Assert(LL.GetNextMilestone(1) == 75, "Next milestone after 1 is 75")
Assert(LL.GetNextMilestone(75) == 150, "Next milestone after 75 is 150")
Assert(LL.GetNextMilestone(150) == 225, "Next milestone after 150 is 225")
Assert(LL.GetNextMilestone(225) == 300, "Next milestone after 225 is 300")

-- 4. Vendor Database & Merchant Scan Tests
Assert(LL.VendorDatabase.GetVendorBuyPrice(2320) == 10, "Coarse Thread vendor price == 10c")
Assert(LL.VendorDatabase.GetVendorBuyPrice(2880) == 100, "Weak Flux vendor price == 100c")
Assert(LL.VendorDatabase.GetVendorBuyPrice(3372) == 40, "Leaded Vial vendor price == 40c")
Assert(LL.VendorDatabase.GetVendorBuyPrice(3857) == 500, "Coal vendor price == 500c")
Assert(LL.VendorDatabase.GetVendorBuyPrice(4289) == 50, "Salt vendor price == 50c")
Assert(LL.VendorDatabase.GetVendorBuyPrice(2678) == 10, "Mild Spices vendor price == 10c")

Mock.merchantItems = {
    { itemId = 2880, name = "Weak Flux", price = 90, quantity = 1, numAvailable = -1 },
}
Mock.FireEvent("MERCHANT_SHOW")
Assert(LL.VendorDatabase.GetVendorBuyPrice(2880) == 90, "MERCHANT_SHOW updates discounted vendor price (90c)")
LevelingLad_DB.vendorBuyPrices[2880] = nil

-- 5. Strictly WoW: Forever Verification — Zero Hardcoded WoW Classic Recipes!
for _, prof in ipairs(LL.RecipeDatabase.GetSupportedProfessions()) do
    local staticList = LL.RecipeDatabase.GetRecipesForProfession(prof.skillLine)
    Assert(#staticList == 0, string.format("Zero Classic Era recipe poisoning in static RecipeDatabase for %s (%d)", prof.name, prof.skillLine))
end

-- 6. Leveling Engine Deep Unit Tests
local TestEngine = require("Tests.Test_LevelingEngine")
TestEngine.Run(Assert, Mock)

-- 7. Live WoW: Forever C_TradeSkillUI + Trainer Scanning, Live Skillup & Smart Abort
Mock.Reset()
LevelingLad_DB.charRecipes = {}
LevelingLad_DB.trainerRecipes = {}
Mock.professions = {
    { name = "Blacksmithing", skillLevel = 45, maxSkillLevel = 75, skillLine = 164 },
}
Mock.modernProfession = {
    professionID = 164,
    parentProfessionID = 164,
    professionName = "Blacksmithing",
    parentProfessionName = "Blacksmithing",
    skillLevel = 45,
    maxSkillLevel = 75,
}
Mock.modernRecipes = {
    [3320] = {
        recipeID = 3320,
        name = "Rough Grinding Stone",
        learned = true,
        outputItemID = 3470,
        quantityMin = 1,
        quantityMax = 1,
        skillLine = 164,
        professionName = "Blacksmithing",
        difficulty = nil,
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Medium, -- YELLOW
        reagents = { { itemID = 2835, qty = 2 } },
    },
    [994444] = {
        recipeID = 994444,
        name = "Forever Apprentice Hammer",
        learned = false, -- Trainer-taught recipe (verified via TRAINER_SHOW below)
        outputItemID = 2846,
        quantityMin = 1,
        quantityMax = 1,
        skillLine = 164,
        professionName = "Blacksmithing",
        difficulty = nil,
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Optimal, -- ORANGE
        reagents = { { itemID = 2840, qty = 2 } },
    },
    [999300] = {
        recipeID = 999300,
        name = "Elemental Sharpening Stone",
        learned = false, -- Unverified phase-locked / drop recipe NOT at trainer -> MUST BE IGNORED!
        outputItemID = 18262,
        quantityMin = 1,
        quantityMax = 1,
        skillLine = 164,
        professionName = "Blacksmithing",
        difficulty = nil,
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Optimal,
        reagents = { { itemID = 2835, qty = 1 } },
    },
}

-- Without visiting a trainer, unlearned C_TradeSkillUI recipes MUST NOT be imported
local scannedBeforeTrainer = LL.RecipeScanner.ScanModernTradeSkillUI()
Assert(scannedBeforeTrainer == 1, "ScanModernTradeSkillUI ignores unverified unlearned C_TradeSkillUI recipes")

-- Visit Blacksmithing Trainer: teaches Forever Apprentice Hammer (minSkill 45), NOT Elemental Sharpening Stone
Mock.trainerServices = {
    { name = "Plans: Forever Apprentice Hammer", serviceType = "available", skillName = "Blacksmithing", minSkill = 45, cost = 500 },
}
Mock.FireEvent("TRAINER_SHOW")
local scannedModern = LL.RecipeScanner.ScanModernTradeSkillUI()
Assert(scannedModern == 2, "ScanModernTradeSkillUI includes trainer-verified recipe and still excludes Elemental Sharpening Stone")
local bsRank, bsMax = LL.RecipeScanner.GetProfessionSkill(164)
Assert(bsRank == 45 and bsMax == 75, "GetProfessionSkill accurately reports Blacksmithing 45 / 75")

_G.PCF_DB.prices[2835] = { minBuyout = 30, count = 300, lastUpdated = Mock.currentTime }
_G.PCF_DB.prices[2840] = { minBuyout = 100, count = 300, lastUpdated = Mock.currentTime }
LevelingLad_DB.settings.selectedProfession = 164
LevelingLad_DB.settings.targetMode = "PLUS5"
local plays = LL.LevelingEngine.FindTopPlays(164, 45, 50)
Assert(#plays == 2, "FindTopPlays returns learned + trainer-verified WoW: Forever recipes (and excludes Elemental Sharpening Stone)")

local activePlay = plays[1]
Mock.bagCounts[2835] = 4
LL.AHVerifier.RecordConfirmedPurchase(2835, "Rough Stone", 2, "EVENT")
LL.DetailWindow.ShowPlay(activePlay)
Assert(LL.DetailWindow.frame:IsShown() == true, "DetailWindow opens for selected leveling play")

local firstShop = activePlay.shoppingList[1]
if firstShop and firstShop.itemId == 2835 then
    Assert(firstShop.haveInBags == 4 and firstShop.inMail == 2 and firstShop.remainingToBuy == math.max(0, firstShop.totalQuantity - 6),
        "DetailWindow accurately tracks Need / In Bags (4) / In Mail (2) / To Buy")
end

-- Test 1-click AH Search
LL.AHVerifier.SearchItemOnAH(2835, "Rough Stone", nil, 10)
Assert(Mock.lastAuctionQuery == "Rough Stone" and _G.BrowseName:GetText() == "Rough Stone",
    "1-Click Search AH fills search bar and executes AH query")

-- Test taint-free OpenRecipe & CraftRecipe
local opened = LL.RecipeScanner.OpenRecipe(activePlay.recipe)
Assert(opened == true and Mock.lastOpenedRecipeId == activePlay.recipeId,
    "OpenRecipe navigates via C_TradeSkillUI.OpenRecipe without Blizzard UI taint")
local craftedOk, craftStatus = LL.RecipeScanner.CraftRecipe(activePlay.recipe, 5)
Assert(craftedOk == true and craftStatus == "CRAFTING" and Mock.lastCraftedModern.quantity == 5,
    "CraftRecipe invokes C_TradeSkillUI.CraftRecipe with target craft count")

-- Simulate live skill-up reaching target skill 50 -> triggers Smart Abort alert & blocks further crafting!
local _, newRank, reached = LL.RecipeScanner.HandleSkillMessage("Your skill in Blacksmithing has increased to 50.")
Assert(newRank == 50 and reached == true and activePlay.goalReached == true,
    "CHAT_MSG_SKILL detects skillup to 50 and triggers Smart Abort goalReached flag")
Assert(LL.DetailWindow.frame.alertBanner:IsShown() == true
    and LL.DetailWindow.frame.alertBanner.text:GetText():find("Goal reached") ~= nil,
    "DetailWindow highlights Smart Abort alert banner when target skill is reached")

local blockedCraft, blockReason = LL.RecipeScanner.CraftRecipe(activePlay.recipe, 2)
Assert(blockedCraft == false and blockReason == "TARGET_REACHED",
    "CraftRecipe automatically halts crafting once target skill is reached to save remaining mats")

-- 8. SideWindow Docking & Slash Command Smoke Tests (including /ll debug)
Mock.FireEvent("AUCTION_HOUSE_SHOW")
Assert(LL.SideWindow.frame ~= nil and LL.SideWindow.frame:IsShown() == true,
    "SideWindow automatically opens and docks on AUCTION_HOUSE_SHOW")

_G.SlashCmdList["LEVELINGLAD"]("budget 15g")
Assert(LevelingLad_DB.settings.budgetCopper == 150000, "/ll budget 15g updates budgetCopper to 150000c")
_G.SlashCmdList["LEVELINGLAD"]("recovery ah")
Assert(LevelingLad_DB.settings.recoveryMode == "AH", "/ll recovery ah switches recovery mode to AH")
_G.SlashCmdList["LEVELINGLAD"]("target milestone")
Assert(LevelingLad_DB.settings.targetMode == "MILESTONE", "/ll target milestone switches target mode")
_G.SlashCmdList["LEVELINGLAD"]("run")
Assert(#(LevelingLad_DB.lastTopPlays or {}) >= 1, "/ll run populates Top leveling plays")

local dbgCounts = LL.RecipeScanner.DebugDump()
Assert(dbgCounts ~= nil and dbgCounts.ORANGE == 2 and dbgCounts.YELLOW == 1, "/ll debug reports live C_TradeSkillUI difficulty breakdown")

Mock.FireEvent("AUCTION_HOUSE_CLOSED")
Assert(LL.SideWindow.frame:IsShown() == false, "SideWindow hides cleanly on AUCTION_HOUSE_CLOSED")

-- 9. Mailbox Auto-Decrement on Bag Arrival Test
Mock.Reset()
Mock.bagCounts[2835] = 4
LL.AHVerifier.ClearPurchasedTracker()
LL.AHVerifier.RecordConfirmedPurchase(2835, "Rough Stone", 10, "EVENT")
Assert(LL.AHVerifier.GetPurchasedInMailCount(2835) == 10, "Purchased mail tracker records 10 Rough Stone in mail")
Mock.bagCounts[2835] = 10
Assert(LL.AHVerifier.GetPurchasedInMailCount(2835) == 4, "Purchased mail count auto-decrements from 10 to 4 when 6 arrive in bags")
Mock.bagCounts[2835] = 14
Assert(LL.AHVerifier.GetPurchasedInMailCount(2835) == 0, "Purchased mail count clears to 0 once all items are looted")

-- 10. Live Legacy AH Order-Book Verification Flow Test
Mock.Reset()
Mock.playerMoney = 500000
_G.AuctionFrame:Show()
LevelingLad_DB.charRecipes = {}
Mock.professions = { { name = "Blacksmithing", skillLevel = 1, maxSkillLevel = 75, skillLine = 164 } }
Mock.modernProfession = { professionID = 164, parentProfessionID = 164, professionName = "Blacksmithing", parentProfessionName = "Blacksmithing", skillLevel = 1, maxSkillLevel = 75 }
Mock.modernRecipes = {
    [2660] = {
        recipeID = 2660, name = "Rough Sharpening Stone", learned = true, outputItemID = 2862,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Optimal,
        reagents = { { itemID = 2835, qty = 1 } },
    },
}
LL.RecipeScanner.ScanModernTradeSkillUI()
_G.PCF_DB.prices[2835] = { minBuyout = 20, count = 100, lastUpdated = Mock.currentTime }
Mock.auctionListingsByQuery["Rough Stone"] = {
    { itemId = 2835, name = "Rough Stone", count = 5, buyoutPrice = 1000 },
    { itemId = 2835, name = "Rough Stone", count = 10, buyoutPrice = 4000 },
}
local verifyDone = false
local verifiedPlays = nil
LevelingLad_DB.settings.selectedProfession = 164
LevelingLad_DB.settings.targetMode = "PLUS5"
LL.AHVerifier.StartVerification(164, {
    onFinish = function(resultPlays)
        verifyDone = true
        verifiedPlays = resultPlays
    end,
})
Mock.FlushTimers(50)
Assert(verifyDone == true and type(verifiedPlays) == "table" and #verifiedPlays >= 1,
    "Live AHVerifier async verification loop queries AH, records stepped order books, and finishes")
local cachedOB = LevelingLad_DB.orderBookCache[2835]
Assert(cachedOB ~= nil and #cachedOB.listings == 2 and cachedOB.listings[1].unitPrice == 200 and cachedOB.listings[2].unitPrice == 400,
    "Live AH query populates multi-tier orderBookCache (200c x5, 400c x10)")

-- 11. Regression Test: WoW: Forever Blacksmithing 255 -> 260 (Zero Classic Poisoning!)
Mock.Reset()
Mock.playerMoney = 5000000
LevelingLad_DB.settings.budgetCopper = 0
LevelingLad_DB.charRecipes = {}
LevelingLad_DB.orderBookCache = {}
LevelingLad_DB.settings.includeTrainerRecipes = true
Mock.professions = {
    { name = "Blacksmithing", skillLevel = 255, maxSkillLevel = 300, skillLine = 164 },
}
Mock.modernProfession = {
    professionID = 164,
    parentProfessionID = 164,
    professionName = "Blacksmithing",
    parentProfessionName = "Blacksmithing",
    skillLevel = 255,
    maxSkillLevel = 300,
}
Mock.modernRecipes = {
    [3116] = {
        recipeID = 3116, name = "Coarse Weightstone", learned = true, outputItemID = 3240,
        skillLine = 164, professionName = "Blacksmithing",
        difficulty = nil, relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Trivial, -- GRAY
        reagents = { { itemID = 2836, qty = 1 } },
    },
    [16639] = {
        recipeID = 16639, name = "Dense Sharpening Stone", learned = true, outputItemID = 12404,
        skillLine = 164, professionName = "Blacksmithing",
        difficulty = nil, relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Trivial, -- GRAY on Forever at 255
        reagents = { { itemID = 12365, qty = 1 } },
    },
    [993117] = {
        recipeID = 993117, name = "Unknown Difficulty Stone", learned = true, outputItemID = 2862,
        skillLine = 164, professionName = "Blacksmithing",
        difficulty = nil, relativeDifficulty = nil, -- Unknown -> defaults safely to GRAY
        reagents = { { itemID = 2835, qty = 1 } },
    },
    [997937] = {
        recipeID = 997937, name = "Ornate Mithril Helm", learned = true, outputItemID = 7937,
        skillLine = 164, professionName = "Blacksmithing",
        difficulty = nil, relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Easy, -- GREEN
        reagents = { { itemID = 3860, qty = 16 } },
    },
}
_G.PCF_DB.prices[2835]  = { minBuyout = 10,  count = 500, lastUpdated = Mock.currentTime }
_G.PCF_DB.prices[2836]  = { minBuyout = 61,  count = 500, lastUpdated = Mock.currentTime }
_G.PCF_DB.prices[12365] = { minBuyout = 50,  count = 500, lastUpdated = Mock.currentTime }
_G.PCF_DB.prices[3860]  = { minBuyout = 500, count = 500, lastUpdated = Mock.currentTime }

local scanned255 = LL.RecipeScanner.ScanModernTradeSkillUI()
Assert(scanned255 == 4, "ScanModernTradeSkillUI scans all 4 WoW: Forever Blacksmithing recipes at 255")

local plays255 = LL.LevelingEngine.FindTopPlays(164, 255, 260)
Assert(#plays255 == 1 and plays255[1].recipeName == "Ornate Mithril Helm" and plays255[1].startDifficulty == "GREEN",
    "Blacksmithing 255->260 strictly excludes gray recipes & Classic Era entries, recommending only GREEN Ornate Mithril Helm")

local roadmap255 = LL.LevelingEngine.PlanMilestonePath(164, 255, 260)
Assert(roadmap255.reachedTarget == true and #roadmap255.steps == 1 and roadmap255.steps[1].recipeName == "Ornate Mithril Helm",
    "Blacksmithing 255->260 roadmap cleanly uses live WoW: Forever Ornate Mithril Helm (zero Classic poisoning)")

-- 12. Regression Test: Blacksmithing 260 -> 265 (No Unverified Unlearned Recipes, No Stale Goal Alerts, Visible Button Labels)
Mock.Reset()
_G.AuctionFrame:Hide() -- Crafting at the anvil away from the Auction House
Mock.playerMoney = 2134500 -- 213g 45s
LevelingLad_DB.settings.budgetCopper = 500000 -- 50g cap
LevelingLad_DB.charRecipes = {}
LevelingLad_DB.trainerRecipes = {}
LevelingLad_DB.orderBookCache = {}
LevelingLad_DB.settings.includeTrainerRecipes = true
LevelingLad_DB.settings.selectedProfession = 164

-- Seed a stale activePlay from a previous 255->260 session
LevelingLad_DB.activePlay = {
    recipeName = "Ornate Mithril Helm",
    profession = "Blacksmithing",
    skillLine = 164,
    startSkill = 255,
    targetSkill = 260,
    goalTargetSkill = 260,
    liveSkill = 260,
}

Mock.professions = {
    { name = "Blacksmithing", skillLevel = 260, maxSkillLevel = 300, skillLine = 164 },
}
Mock.modernProfession = {
    professionID = 164,
    parentProfessionID = 164,
    professionName = "Blacksmithing",
    parentProfessionName = "Blacksmithing",
    skillLevel = 260,
    maxSkillLevel = 300,
}
Mock.modernRecipes = {
    [16657] = {
        recipeID = 16657, name = "Imperial Plate Bracers", learned = true, outputItemID = 12424,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Optimal, -- ORANGE learned recipe!
        reagents = { { itemID = 12359, qty = 12 } },
    },
    -- Unlearned unavailable / drop / high-level recipes in C_TradeSkillUI (NOT at trainer):
    [22757] = {
        recipeID = 22757, name = "Elemental Sharpening Stone", learned = false, outputItemID = 18262,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Optimal,
        reagents = { { itemID = 7067, qty = 1 }, { itemID = 12365, qty = 1 } },
    },
    [23638] = {
        recipeID = 23638, name = "Ebon Shiv", learned = false, outputItemID = 19170,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Medium,
        reagents = { { itemID = 12359, qty = 12 } },
    },
    [16664] = {
        recipeID = 16664, name = "Thorium Greatsword", learned = false, outputItemID = 12406,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Medium,
        reagents = { { itemID = 12359, qty = 12 } },
    },
    [16729] = {
        recipeID = 16729, name = "Blight", learned = false, outputItemID = 12774,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Medium,
        reagents = { { itemID = 12359, qty = 12 } },
    },
    [16655] = {
        recipeID = 16655, name = "Ornate Thorium Handaxe", learned = false, outputItemID = 12773,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Optimal,
        reagents = { { itemID = 12359, qty = 12 } },
    },
    -- Future trainer recipe requiring skill 265:
    [16658] = {
        recipeID = 16658, name = "Imperial Plate Belt", learned = false, outputItemID = 12425,
        skillLine = 164, professionName = "Blacksmithing",
        relativeDifficulty = _G.Enum.TradeskillRelativeDifficulty.Optimal,
        reagents = { { itemID = 12359, qty = 8 } },
    },
}
_G.PCF_DB.prices[12359] = { minBuyout = 1000, count = 500, lastUpdated = Mock.currentTime }
_G.PCF_DB.prices[7067]  = { minBuyout = 2000, count = 500, lastUpdated = Mock.currentTime }
_G.PCF_DB.prices[12365] = { minBuyout = 500,  count = 500, lastUpdated = Mock.currentTime }

-- Trainer teaches Imperial Plate Belt at minSkill = 265 (unavailable at 260!)
Mock.trainerServices = {
    { name = "Imperial Plate Belt", serviceType = "unavailable", skillName = "Blacksmithing", minSkill = 265, cost = 20000 },
}
Mock.FireEvent("TRAINER_SHOW")
LL.RecipeScanner.ScanModernTradeSkillUI()

-- User opens SideWindow, types 265, and clicks "Set Goal"
LL.SideWindow.Toggle()
Assert(LL.SideWindow.frame.targetPlus5Btn.labelText ~= nil
    and LL.SideWindow.frame.targetPlus5Btn.labelText:GetText():find("%+5 Points") ~= nil,
    "SideWindow +5 Points button has a rendered FontString labelText (not a blank box)")
Assert(LL.SideWindow.frame.targetMilestoneBtn.labelText ~= nil
    and LL.SideWindow.frame.targetMilestoneBtn.labelText:GetText():find("Next Tier: 300") ~= nil,
    "SideWindow Next Tier button has a rendered FontString labelText (not a blank box)")

LL.SideWindow.frame.targetCustomInput:SetText("265")
_G["LL_SideCustomTargetApply"]:Click()

Assert(LevelingLad_DB.activePlay == nil, "Clicking 'Set Goal' (265) clears stale target=260 activePlay")
local plays260 = LevelingLad_DB.lastTopPlays or {}
Assert(#plays260 == 1 and plays260[1].recipeName == "Imperial Plate Bracers",
    "At Blacksmithing 260, Top 5 excludes Elemental Sharpening Stone / Ebon Shiv / 265 trainer recipe and recommends learned Imperial Plate Bracers")

-- Verify Milestone Path 260 -> 270 DOES unlock Imperial Plate Belt once simulated skill reaches 265!
local roadmap270 = LL.LevelingEngine.PlanMilestonePath(164, 260, 270)
local usedTrainer265 = false
for _, st in ipairs(roadmap270.steps or {}) do
    if st.recipeName == "Imperial Plate Belt" and st.startSkill >= 265 then
        usedTrainer265 = true
    end
end
Assert(usedTrainer265 == true, "Milestone Path 260->270 routes to trainer-verified Imperial Plate Belt only at skill >= 265")

-- Craft Imperial Plate Bracers at 261 & 262 without opening DetailWindow -> ZERO stale target=260 alerts!
local _, r261, hit261 = LL.RecipeScanner.HandleSkillMessage("Your skill in Blacksmithing has increased to 261.")
local _, r262, hit262 = LL.RecipeScanner.HandleSkillMessage("Your skill in Blacksmithing has increased to 262.")
Assert(r261 == 261 and hit261 == false and r262 == 262 and hit262 == false,
    "Skillups to 261 and 262 do NOT fire stale 'Goal reached (target: 260)' alerts")
Assert(LevelingLad_DB.lastTopPlays[1] and LevelingLad_DB.lastTopPlays[1].startSkill == 262 and LevelingLad_DB.lastTopPlays[1].targetSkill == 265,
    "SideWindow cached plays automatically refresh skill range to (262->265) on live skillup")

-- Now open DetailWindow for the 262->265 play and verify single-fire alert at 265 (and silence at 266)
LL.DetailWindow.ShowPlay(LevelingLad_DB.lastTopPlays[1])
local _, r265, hit265 = LL.RecipeScanner.HandleSkillMessage("Your skill in Blacksmithing has increased to 265.")
local _, r266, hit266 = LL.RecipeScanner.HandleSkillMessage("Your skill in Blacksmithing has increased to 266.")
Assert(r265 == 265 and hit265 == true and r266 == 266 and hit266 == false,
    "Goal alert fires exactly once at target 265 and never repeats at 266")

-- 13. Verify v2/v3 -> v4 DB migration purges tainted unlearned recipes and stale activePlay
local v3DB = {
    version = 3,
    charRecipes = { ["SkillTester-Forever"] = { ["164:22757"] = { name = "Elemental Sharpening Stone", learned = false, orange = 260, gray = 295 } } },
    lastTopPlays = { { recipeName = "Elemental Sharpening Stone" } },
    lastRoadmap = { steps = { { recipeName = "Elemental Sharpening Stone" } } },
    activePlay = { recipeName = "Ornate Mithril Helm", targetSkill = 260 },
}
LL.LoadConfig(v3DB)
Assert(v3DB.version == 4 and next(v3DB.charRecipes) == nil and #v3DB.lastTopPlays == 0 and v3DB.lastRoadmap == nil and v3DB.activePlay == nil,
    "Config v3->v4 migration purges unverified unlearned charRecipes, lastTopPlays, lastRoadmap, and stale activePlay")

print("================================================================")
print(string.format(" ALL TESTS PASSED! (%d passed, %d failed)", passed, failed))
print("================================================================")
