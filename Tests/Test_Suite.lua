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
print(" Leveling Lad (LL) Headless LuaJIT Test Suite")
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

-- Verify MERCHANT_SHOW updates discounted vendor price dynamically
Mock.merchantItems = {
    { itemId = 2880, name = "Weak Flux", price = 90, quantity = 1, numAvailable = -1 }, -- Honored 10% discount
}
Mock.FireEvent("MERCHANT_SHOW")
Assert(LL.VendorDatabase.GetVendorBuyPrice(2880) == 90, "MERCHANT_SHOW updates discounted vendor price (90c)")
LevelingLad_DB.vendorBuyPrices[2880] = nil -- Restore default 100c for subsequent tests

-- 5. Recipe Database Coverage Check (All 8 Core Professions)
local requiredProfessions = { 164, 197, 165, 171, 202, 185, 333, 129 }
for _, skillLine in ipairs(requiredProfessions) do
    local list = LL.RecipeDatabase.GetRecipesForProfession(skillLine)
    Assert(#list >= 10, string.format("RecipeDatabase has full catalog (%d recipes) for %s (%d)",
        #list, LL.RecipeDatabase.GetProfessionName(skillLine), skillLine))
end

-- 6. Leveling Engine Deep Unit Tests
local TestEngine = require("Tests.Test_LevelingEngine")
TestEngine.Run(Assert, Mock)

-- 7. RecipeScanner, Live Skillup Detection & Smart Abort Tests
Mock.Reset()
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
        difficulty = "medium",
        reagents = { { itemID = 2835, qty = 2 } },
    },
}
local scannedModern = LL.RecipeScanner.ScanModernTradeSkillUI()
Assert(scannedModern == 1, "ScanModernTradeSkillUI scans learned C_TradeSkillUI recipe")
local bsRank, bsMax = LL.RecipeScanner.GetProfessionSkill(164)
Assert(bsRank == 45 and bsMax == 75, "GetProfessionSkill accurately reports Blacksmithing 45 / 75")

-- Track an active play targeting skill 50, open DetailWindow, and simulate live CHAT_MSG_SKILL!
_G.PCF_DB.prices[2835] = { minBuyout = 30, count = 300, lastUpdated = Mock.currentTime }
LevelingLad_DB.settings.selectedProfession = 164
LevelingLad_DB.settings.targetMode = "PLUS5"
local plays = LL.LevelingEngine.FindTopPlays(164, 45, 50)
Assert(#plays >= 1, "FindTopPlays finds eligible plays at Blacksmithing 45 -> 50")

local activePlay = plays[1]
Mock.bagCounts[2835] = 4 -- 4 in bags
LL.AHVerifier.RecordConfirmedPurchase(2835, "Rough Stone", 2, "EVENT") -- 2 in mail
LL.DetailWindow.ShowPlay(activePlay)
Assert(LL.DetailWindow.frame:IsShown() == true, "DetailWindow opens for selected leveling play")

local firstShop = activePlay.shoppingList[1]
if firstShop and firstShop.itemId == 2835 then
    Assert(firstShop.haveInBags == 4 and firstShop.inMail == 2 and firstShop.remainingToBuy == math.max(0, firstShop.totalQuantity - 6),
        "DetailWindow accurately tracks Need / In Bags (4) / In Mail (2) / To Buy")
end

-- Test 1-click AH Search from DetailWindow
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

-- 8. SideWindow Docking & Slash Command Smoke Tests
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
Assert(#(LevelingLad_DB.lastTopPlays or {}) >= 1, "/ll run populates Top 5 leveling plays")

Mock.FireEvent("AUCTION_HOUSE_CLOSED")
Assert(LL.SideWindow.frame:IsShown() == false, "SideWindow hides cleanly on AUCTION_HOUSE_CLOSED")

-- 9. Mailbox Auto-Decrement on Bag Arrival Test
Mock.Reset()
Mock.bagCounts[2835] = 4
LL.AHVerifier.ClearPurchasedTracker()
LL.AHVerifier.RecordConfirmedPurchase(2835, "Rough Stone", 10, "EVENT")
Assert(LL.AHVerifier.GetPurchasedInMailCount(2835) == 10, "Purchased mail tracker records 10 Rough Stone in mail")
Mock.bagCounts[2835] = 10 -- Player looted 6 Rough Stone from mailbox into bags
Assert(LL.AHVerifier.GetPurchasedInMailCount(2835) == 4, "Purchased mail count auto-decrements from 10 to 4 when 6 arrive in bags")
Mock.bagCounts[2835] = 14 -- Remaining 4 looted
Assert(LL.AHVerifier.GetPurchasedInMailCount(2835) == 0, "Purchased mail count clears to 0 once all items are looted")

-- 10. Live Legacy AH Order-Book Verification Flow Test
Mock.Reset()
Mock.playerMoney = 500000
_G.AuctionFrame:Show()
_G.PCF_DB.prices[2835] = { minBuyout = 20, count = 100, lastUpdated = Mock.currentTime }
Mock.auctionListingsByQuery["Rough Stone"] = {
    { itemId = 2835, name = "Rough Stone", count = 5, buyoutPrice = 1000 }, -- 2s ea (5x)
    { itemId = 2835, name = "Rough Stone", count = 10, buyoutPrice = 4000 }, -- 4s ea (10x)
}
local verifyDone = false
local verifiedPlays = nil
LevelingLad_DB.settings.selectedProfession = 164
LevelingLad_DB.settings.targetMode = "PLUS5"
Mock.professions = { { name = "Blacksmithing", skillLevel = 1, maxSkillLevel = 75, skillLine = 164 } }
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

-- 11. Legacy TradeSkillFrame Scan & DoTradeSkill Fallback Test
Mock.Reset()
local savedModernUI = _G.C_TradeSkillUI
_G.C_TradeSkillUI = nil
Mock.tradeSkillLine = "Tailoring"
Mock.tradeSkillRank = 30
Mock.tradeSkillMaxRank = 75
Mock.tradeSkills = {
    {
        name = "Brown Linen Robe",
        skillType = "optimal",
        outputItemId = 6238,
        reagents = {
            { itemId = 2996, name = "Bolt of Linen Cloth", count = 3 },
            { itemId = 2320, name = "Coarse Thread", count = 1 },
        },
    },
}
local scannedLegacy = LL.RecipeScanner.ScanLegacyTradeSkill()
Assert(scannedLegacy == 1, "ScanLegacyTradeSkill scans legacy TradeSkillFrame recipes")
local legacyCraftOk = LL.RecipeScanner.CraftRecipe({ name = "Brown Linen Robe", outputItemId = 6238, profession = "Tailoring", skillLine = 197 }, 4)
Assert(legacyCraftOk == true and Mock.craftedTradeSkill ~= nil and Mock.craftedTradeSkill.quantity == 4,
    "CraftRecipe falls back to legacy DoTradeSkill when C_TradeSkillUI is absent")
_G.C_TradeSkillUI = savedModernUI

-- 12. All-Professions 1->300 Continuity & Seed Metadata Completeness Check
Mock.Reset()
Mock.playerMoney = 100000000 -- 10,000g for full 1->300 continuity validation
LevelingLad_DB.settings.budgetCopper = 0
LevelingLad_DB.orderBookCache = {}
for _, prof in ipairs(LL.RecipeDatabase.GetSupportedProfessions()) do
    local recipes = LL.RecipeDatabase.GetRecipesForProfession(prof.skillLine)
    local validatedItems = 0
    for _, rec in ipairs(recipes) do
        if not (rec.orange <= rec.yellow and rec.yellow <= rec.green and rec.green <= rec.gray) then
            Assert(false, string.format("Invalid thresholds O<=Y<=G<=Gr for [%s]", rec.name))
        end
        for itemId, qty in pairs(rec.reagents or {}) do
            local meta = LL.VendorDatabase.GetItemMetadata(itemId, nil, true)
            if not (qty > 0 and meta and meta.name) then
                Assert(false, string.format("Missing reagent metadata/qty for item %d in [%s]", itemId, rec.name))
            end
            validatedItems = validatedItems + 1
            if not LL.VendorDatabase.IsVendorReagent(itemId) then
                _G.PCF_DB.prices[itemId] = { minBuyout = 100, count = 999, lastUpdated = Mock.currentTime }
            end
        end
        if rec.outputItemId then
            local outMeta = LL.VendorDatabase.GetItemMetadata(rec.outputItemId, nil, true)
            if not (outMeta and outMeta.name) then
                Assert(false, string.format("Missing output metadata for item %d of [%s]", rec.outputItemId, rec.name))
            end
            validatedItems = validatedItems + 1
        end
    end
    Assert(#recipes >= 10 and validatedItems > 0,
        string.format("%s catalog integrity verified (%d recipes, %d item refs)", prof.name, #recipes, validatedItems))

    local targetCap = (prof.skillLine == 186) and 290 or 300
    local roadmap = LL.LevelingEngine.PlanMilestonePath(prof.skillLine, 1, targetCap, {
        recoveryMode = "VENDOR",
        customRecipes = recipes,
    })
    Assert(roadmap.reachedTarget == true and roadmap.reachedSkill == targetCap,
        string.format("Full 1->%d zero-gap roadmap continuity verified for %s (%d steps)",
            targetCap, prof.name, #roadmap.steps))
end

print("================================================================")
print(string.format(" ALL TESTS PASSED! (%d passed, %d failed)", passed, failed))
print("================================================================")
