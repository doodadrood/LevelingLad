-- Comprehensive Unit Tests for Leveling Lad LevelingEngine, Economics, Over-Buy Prevention,
-- Trainer Lookahead ("The Green/Yellow Trap"), Stepped Order-Book Pricing & Circuit Breakers.

local M = {}

local function ApproxEq(a, b, tol)
    tol = tol or 1e-6
    return math.abs((a or 0) - (b or 0)) <= tol
end

function M.Run(Assert, Mock)
    local LE = LL.LevelingEngine

    -- ========================================================================
    -- 1. Difficulty Classification & Exact Probability Curves (O / Y / G / Gr)
    -- ========================================================================
    local testRecipe = {
        recipeId = 90001,
        name = "Test Bronze Widget",
        profession = "Blacksmithing",
        skillLine = 164,
        minSkill = 1,
        orange = 1,
        yellow = 50,
        green = 75,
        gray = 100,
        reagents = { [2835] = 1 },
        outputItemId = 2862,
        outputQty = 1,
        source = "Trainer",
    }

    Assert(LE.GetDifficultyState(testRecipe, 1) == "ORANGE", "Skill 1 < 50 is ORANGE")
    Assert(LE.GetDifficultyState(testRecipe, 49) == "ORANGE", "Skill 49 < 50 is ORANGE")
    Assert(LE.GetDifficultyState(testRecipe, 50) == "YELLOW", "Skill 50 == T_yellow is YELLOW")
    Assert(LE.GetDifficultyState(testRecipe, 74) == "YELLOW", "Skill 74 < 75 is YELLOW")
    Assert(LE.GetDifficultyState(testRecipe, 75) == "GREEN", "Skill 75 == T_green is GREEN")
    Assert(LE.GetDifficultyState(testRecipe, 99) == "GREEN", "Skill 99 < 100 is GREEN")
    Assert(LE.GetDifficultyState(testRecipe, 100) == "GRAY", "Skill 100 == T_gray is GRAY")
    Assert(LE.GetDifficultyState(testRecipe, 120) == "GRAY", "Skill 120 > T_gray is GRAY")

    -- Orange: P = 1.0, E[C] = 1.0
    Assert(ApproxEq(LE.GetSkillupProbability(testRecipe, 45), 1.0), "Orange probability P(45) == 1.0")
    Assert(ApproxEq(LE.GetExpectedCraftsForPoint(testRecipe, 45), 1.0), "Orange expected crafts E[C|45] == 1.0")

    -- Yellow: P = max(0.50, (100 - S) / (100 - 50))
    -- At S = 50: (100-50)/50 = 1.0
    -- At S = 60: (100-60)/50 = 0.80 -> E[C] = 1.25
    -- At S = 74: (100-74)/50 = 0.52
    Assert(ApproxEq(LE.GetSkillupProbability(testRecipe, 50), 1.0), "Yellow probability P(50) == 1.0")
    Assert(ApproxEq(LE.GetSkillupProbability(testRecipe, 60), 0.80), "Yellow probability P(60) == 0.80")
    Assert(ApproxEq(LE.GetExpectedCraftsForPoint(testRecipe, 60), 1.25), "Yellow expected crafts E[C|60] == 1.25")
    Assert(ApproxEq(LE.GetSkillupProbability(testRecipe, 74), 0.52), "Yellow probability P(74) == 0.52")

    -- Yellow floor clamp: when T_green is closer to T_gray (e.g. Y=50, G=90, Gr=100), P(85) = max(0.50, 15/50) = 0.50
    local clampedYellow = { orange = 1, yellow = 50, green = 90, gray = 100 }
    Assert(ApproxEq(LE.GetSkillupProbability(clampedYellow, 85), 0.50), "Yellow probability enforces 0.50 floor")

    -- Green: P = max(0.10, (100 - S) / (2 * 50))
    -- At S = 75: 25 / 100 = 0.25 -> E[C] = 4.0
    -- At S = 85: 15 / 100 = 0.15
    -- At S = 95: max(0.10, 5 / 100) = 0.10 -> E[C] = 10.0
    Assert(ApproxEq(LE.GetSkillupProbability(testRecipe, 75), 0.25), "Green probability P(75) == 0.25")
    Assert(ApproxEq(LE.GetExpectedCraftsForPoint(testRecipe, 75), 4.0), "Green expected crafts E[C|75] == 4.0")
    Assert(ApproxEq(LE.GetSkillupProbability(testRecipe, 85), 0.15), "Green probability P(85) == 0.15")
    Assert(ApproxEq(LE.GetSkillupProbability(testRecipe, 95), 0.10), "Green probability P(95) clamps to 0.10 floor")
    Assert(ApproxEq(LE.GetExpectedCraftsForPoint(testRecipe, 95), 10.0), "Green expected crafts E[C|95] == 10.0")

    -- Gray: P = 0.0, E[C] = math.huge
    Assert(LE.GetSkillupProbability(testRecipe, 100) == 0.0, "Gray probability P(100) == 0.0")
    Assert(LE.GetExpectedCraftsForPoint(testRecipe, 100) == math.huge, "Gray expected crafts is infinite")

    -- ========================================================================
    -- 2. Expected Crafts Over Spans & Strict Zero-Craft Gray Enforcement
    -- ========================================================================
    -- Pure Orange span: 45 -> 50 => exactly 5 crafts for 5 points
    local cOrange, ptsOrange, endOrange = LE.CalculateExpectedCrafts(testRecipe, 45, 50)
    Assert(cOrange == 5 and ptsOrange == 5 and endOrange == 50, "Orange span 45->50 schedules exactly 5 crafts")

    -- Yellow span: 60 -> 62 => 1/0.80 + 1/0.78 = 1.25 + 1.28205 = 2.532 -> ceil = 3 crafts
    local cYellow, ptsYellow, endYellow = LE.CalculateExpectedCrafts(testRecipe, 60, 62)
    Assert(cYellow == 3 and ptsYellow == 2 and endYellow == 62, "Yellow span 60->62 ceils expected crafts to 3")

    -- Strict Zero-Craft enforcement at or past Gray
    local cGray, ptsGray, endGray = LE.CalculateExpectedCrafts(testRecipe, 100, 110)
    Assert(cGray == 0 and ptsGray == 0 and endGray == 100, "Strictly 0 crafts allowed when skill == Gray (100)")
    local cPastGray, ptsPastGray = LE.CalculateExpectedCrafts(testRecipe, 115, 125)
    Assert(cPastGray == 0 and ptsPastGray == 0, "Strictly 0 crafts allowed when skill > Gray (115)")

    -- ========================================================================
    -- 3. Over-Buy Prevention (Never Plans 7 Crafts if Recipe Turns Gray After 6)
    -- ========================================================================
    local grayCapRecipe = {
        recipeId = 90002,
        name = "Sharp Cap Blade",
        profession = "Blacksmithing",
        skillLine = 164,
        minSkill = 1,
        orange = 1,
        yellow = 55,
        green = 55,
        gray = 55,
        reagents = { [2835] = 1 },
        outputItemId = 2862,
        outputQty = 1,
        source = "Trainer",
    }
    -- Current skill 49, Gray at 55 -> max 6 crafts even if target is 60 (+11 points)!
    local cCap, ptsCap, endCap = LE.CalculateExpectedCrafts(grayCapRecipe, 49, 60)
    Assert(cCap == 6 and ptsCap == 6 and endCap == 55, "Over-buy prevention caps at 6 crafts (never 7) when recipe turns Gray after 6 points")

    Mock.Reset()
    _G.PCF_DB.prices[2835] = { minBuyout = 50, count = 200, lastUpdated = Mock.currentTime }
    local evalCap = LE.EvaluateCandidatePlay(grayCapRecipe, 49, 60, { grayCapRecipe }, { ignoreInventory = true })
    Assert(evalCap ~= nil and evalCap.expectedCrafts == 6 and evalCap.targetSkill == 55 and evalCap.shoppingList[1].totalQuantity == 6,
        "Shopping list strictly capped at 6 reagents (never over-buys for Gray crafts)")
    Assert(LE.EvaluateCandidatePlay(grayCapRecipe, 55, 60, { grayCapRecipe }, { ignoreInventory = true }) == nil,
        "EvaluateCandidatePlay rejects recipe entirely once skill hits Gray")

    -- ========================================================================
    -- 4. Trainer Unlock Lookahead ("The Green/Yellow Trap")
    -- ========================================================================
    -- Recipe A: Orange 1..49, turns Yellow at 50 (Y=50, G=60, Gr=70), uses 2x Copper Bar (200c gross, 0 recovery)
    --   At S=50: P=1.0 ->Wait: at S=50 yellow P=(70-50)/(70-50)=1.0, at S=51 P=19/20=0.95 -> CPSP=210.5c!
    --   Even simpler: Recipe B unlocks at Trainer at S=50 (Orange 50..80), uses 1x Rough Stone (50c gross, 0 recovery -> CPSP=50c < 200c)!
    local recipeA = {
        recipeId = 90101,
        name = "Old Copper Craft",
        profession = "Blacksmithing",
        skillLine = 164,
        minSkill = 1,
        orange = 1, yellow = 50, green = 60, gray = 70,
        reagents = { [2840] = 2 }, -- 2x Copper Bar @ 100c = 200c
        outputItemId = nil, outputQty = 1, source = "Trainer",
    }
    local recipeB = {
        recipeId = 90102,
        name = "New Trainer Orange Craft",
        profession = "Blacksmithing",
        skillLine = 164,
        minSkill = 50,
        orange = 50, yellow = 80, green = 95, gray = 110,
        reagents = { [2835] = 1 }, -- 1x Rough Stone @ 50c = 50c
        outputItemId = nil, outputQty = 1, source = "Trainer",
    }
    _G.PCF_DB.prices[2840] = { minBuyout = 100, count = 200, lastUpdated = Mock.currentTime }
    _G.PCF_DB.prices[2835] = { minBuyout = 50,  count = 200, lastUpdated = Mock.currentTime }

    local hEnd, hReason, handoff = LE.CalculateDynamicHorizon(recipeA, 45, 75, { recipeA, recipeB }, { recoveryMode = "NONE" })
    Assert(hEnd == 50, "Trainer lookahead caps Recipe A strictly at skill 50 (The Green/Yellow Trap)")
    Assert(hReason == "TRAINER_HANDOFF" and handoff ~= nil and handoff.nextRecipeId == 90102 and handoff.atSkill == 50,
        "Surfaces trainer handoff to cheaper orange recipe at skill 50")

    local evalA = LE.EvaluateCandidatePlay(recipeA, 45, 75, { recipeA, recipeB }, { recoveryMode = "NONE", ignoreInventory = true })
    Assert(evalA ~= nil and evalA.expectedCrafts == 5 and evalA.targetSkill == 50 and evalA.handoff ~= nil,
        "Evaluated play schedules exactly 5 crafts (45->50) and surfaces trainer handoff")

    -- ========================================================================
    -- 5. Vendor Reagent Price Enforcement (Never Overpay Inflated AH Rates!)
    -- ========================================================================
    -- Inflate Coarse Thread (2320, vendor 10c), Weak Flux (2880, vendor 100c), Leaded Vial (3372, vendor 40c)
    -- to absurd 50g (500,000c) on the AH!
    _G.PCF_DB.prices[2320] = { minBuyout = 500000, count = 50, lastUpdated = Mock.currentTime }
    _G.PCF_DB.prices[2880] = { minBuyout = 500000, count = 50, lastUpdated = Mock.currentTime }
    _G.PCF_DB.prices[3372] = { minBuyout = 500000, count = 50, lastUpdated = Mock.currentTime }

    local threadAcq = LE.ResolveReagentAcquisition(2320, 10)
    Assert(threadAcq.source == "Vendor" and threadAcq.unitPrice == 10 and threadAcq.totalCost == 100,
        "Coarse Thread priced at NPC vendor rate (10c), ignoring 50g AH listing")
    local fluxAcq = LE.ResolveReagentAcquisition(2880, 5)
    Assert(fluxAcq.source == "Vendor" and fluxAcq.unitPrice == 100 and fluxAcq.totalCost == 500,
        "Weak Flux priced at NPC vendor rate (1s), ignoring 50g AH listing")
    local vialAcq = LE.ResolveReagentAcquisition(3372, 10)
    Assert(vialAcq.source == "Vendor" and vialAcq.unitPrice == 40 and vialAcq.totalCost == 400,
        "Leaded Vial priced at NPC vendor rate (40c), ignoring 50g AH listing")

    -- ========================================================================
    -- 6. Net Cost per Skill Point (CPSP) & Resale Recovery Modes
    -- ========================================================================
    -- Copper Chain Pants (2662): 4x Copper Bar (2840 @ 50c = 200c gross), vendor sell = 107c -> Net = 93c
    -- AH resale @ 300c * 0.95 = 285c -> Net = -85c (profitable leveling craft!)
    -- NONE recovery -> Net = 200c
    _G.PCF_DB.prices[2840] = { minBuyout = 50,  count = 200, lastUpdated = Mock.currentTime }
    _G.PCF_DB.prices[2846] = { minBuyout = 300, count = 10,  lastUpdated = Mock.currentTime }
    local pantsRec = LL.RecipeDatabase.GetRecipeById(2662)

    local evalVendor = LE.EvaluateCandidatePlay(pantsRec, 35, 40, { pantsRec }, { recoveryMode = "VENDOR", ignoreInventory = true })
    Assert(evalVendor ~= nil and evalVendor.grossMatCost == 1000 and evalVendor.totalRecovery == 535 and evalVendor.netCost == 465 and ApproxEq(evalVendor.cpsp, 93),
        "VENDOR recovery: 5x Copper Chain Pants => 1000c gross - 535c vendor = 465c net (93c/pt)")

    local evalAH = LE.EvaluateCandidatePlay(pantsRec, 35, 40, { pantsRec }, { recoveryMode = "AH", ignoreInventory = true })
    Assert(evalAH ~= nil and evalAH.totalRecovery == 1425 and evalAH.netCost == -425 and ApproxEq(evalAH.cpsp, -85),
        "AH recovery (5% cut): 5x Copper Chain Pants => 1000c gross - 1425c AH = -425c net (-85c/pt profit!)")

    local evalNone = LE.EvaluateCandidatePlay(pantsRec, 35, 40, { pantsRec }, { recoveryMode = "NONE", ignoreInventory = true })
    Assert(evalNone ~= nil and evalNone.totalRecovery == 0 and evalNone.netCost == 1000 and ApproxEq(evalNone.cpsp, 200),
        "NONE recovery: 5x Copper Chain Pants => 1000c net (200c/pt)")

    -- ========================================================================
    -- 7. Stepped Order-Book Pricing & Dynamic Price Circuit Breaker
    -- ========================================================================
    -- Order book for Rough Stone (2835): 5x @ 200c (2s), 10x @ 400c (4s)
    local steppedBook = {
        [2835] = {
            { unitPrice = 200, quantity = 5 },
            { unitPrice = 400, quantity = 10 },
        },
    }
    local walk10 = LE.WalkOrderBook(steppedBook[2835], 10)
    -- 5 * 200 + 5 * 400 = 1000 + 2000 = 3000c total, avg = 300c, min = 200c, max = 400c
    Assert(walk10.filledQty == 10 and walk10.totalCost == 3000 and walk10.avgUnitPrice == 300 and walk10.minUnitPrice == 200 and walk10.maxUnitPrice == 400,
        "WalkOrderBook accurately walks stepped tiers (5x@2s + 5x@4s = 30s total)")

    -- Dynamic Circuit Breaker test:
    -- Candidate #1 (Rough Sharpening Stone, 1x Rough Stone, 2c vendor sell) has order book:
    --   3x @ 100c (98c net/pt), then spikes to 20x @ 5000c (4998c net/pt!)
    -- Candidate #2 (Rough Weightstone, 1x Rough Stone + 1x Linen, OR Copper Chain Pants @ 500c/pt) has CPSP = 500c/pt.
    local spikeBook = {
        [2835] = {
            { unitPrice = 100,  quantity = 3 },
            { unitPrice = 5000, quantity = 20 },
        },
    }
    local sharpRec = LL.RecipeDatabase.GetRecipeById(2660)
    local play1 = LE.EvaluateCandidatePlay(sharpRec, 1, 10, { sharpRec }, { customOrderBooks = spikeBook, recoveryMode = "VENDOR", ignoreInventory = true })
    local cbResult = LL.AHVerifier.VerifyPlayWithCircuitBreaker(play1, 500, spikeBook)
    Assert(cbResult.circuitBreakerTripped == true and cbResult.pivotRecommended == true,
        "AHVerifier circuit breaker trips when deeper AH price tier exceeds Candidate #2 CPSP")
    Assert(cbResult.safeCraftsBeforeSpike == 3 and cbResult.safePointsBeforeSpike == 3,
        "Circuit breaker identifies exact 3 safe crafts before the 50s price spike")

    -- Immediate spike on unit 1 -> pivots #2 ahead of #1
    local instantSpikeBook = {
        [2835] = { { unitPrice = 5000, quantity = 20 } },
    }
    local fakePlay1 = { recipe = sharpRec, recipeName = sharpRec.name, startSkill = 1, targetSkill = 5, cpsp = 100 }
    local fakePlay2 = { recipe = pantsRec, recipeName = pantsRec.name, startSkill = 1, targetSkill = 5, cpsp = 500 }
    local ranked, didPivot = LL.AHVerifier.EvaluateCircuitBreakersOnPlays({ fakePlay1, fakePlay2 }, instantSpikeBook)
    Assert(didPivot == true and ranked[1].recipeName == pantsRec.name and ranked[1].pivotedFromCircuitBreaker == true,
        "EvaluateCircuitBreakersOnPlays pivots Candidate #2 to #1 when #1 spikes immediately")

    -- ========================================================================
    -- 8. Hard Budget Cap Enforcement (Single Play & Multi-Step Roadmap)
    -- ========================================================================
    Mock.Reset()
    Mock.playerMoney = 500000 -- 50g in wallet
    LevelingLad_DB.settings.budgetCopper = 1000 -- 10s configured budget cap!
    local effBudget, isCapped = LL.GetEffectiveBudget()
    Assert(effBudget == 1000 and isCapped == true, "GetEffectiveBudget enforces configured budgetCopper (10s < 50g wallet)")

    -- If wallet drops below budgetCopper (e.g. 4s in wallet vs 10s cap), never exceed player gold!
    Mock.playerMoney = 400
    local effWallet = LL.GetEffectiveBudget()
    Assert(effWallet == 400, "GetEffectiveBudget never exceeds current character gold (4s < 10s cap)")

    -- Rough Stone = 100c ea, target 1->15 (14 crafts = 1400c), budget = 350c -> strictly caps at 3 crafts (300c <= 350c)!
    Mock.playerMoney = 500000
    LevelingLad_DB.settings.budgetCopper = 350
    _G.PCF_DB.prices[2835] = { minBuyout = 100, count = 200, lastUpdated = Mock.currentTime }
    local budgetPlay = LE.EvaluateCandidatePlay(sharpRec, 1, 15, { sharpRec }, { recoveryMode = "NONE", ignoreInventory = true })
    Assert(budgetPlay ~= nil and budgetPlay.expectedCrafts == 3 and budgetPlay.outOfPocketCost == 300 and budgetPlay.budgetCapped == true,
        "Hard budget cap limits crafts to 3 (300c <= 350c budget)")

    -- Budget too low for even 1 craft -> returns nil
    LevelingLad_DB.settings.budgetCopper = 50
    local unaffordable = LE.EvaluateCandidatePlay(sharpRec, 1, 15, { sharpRec }, { recoveryMode = "NONE", ignoreInventory = true })
    Assert(unaffordable == nil, "Returns nil when budget (50c) cannot afford even 1 craft (100c)")

    -- Roadmap stops gracefully when gold budget is exhausted
    LevelingLad_DB.settings.budgetCopper = 0
    local cappedRoadmap = LE.PlanMilestonePath(164, 1, 75, {
        budgetOverride = 500, -- Only 5s total budget
        recoveryMode = "VENDOR",
        customRecipes = { sharpRec },
    })
    Assert(cappedRoadmap.totalGrossCost <= 500 and cappedRoadmap.reachedSkill == 6 and cappedRoadmap.budgetExhausted == true,
        "PlanMilestonePath halts cleanly at skill 6 when 5s gold budget is exhausted")

    -- ========================================================================
    -- 9. Full Milestone Pathing Across Classic Professions (1 -> 75 & 1 -> 300)
    -- ========================================================================
    Mock.Reset()
    Mock.playerMoney = 50000000 -- 5000g for full 1-300 simulation
    LevelingLad_DB.settings.budgetCopper = 0
    -- Seed market prices for all reagents in First Aid (cloths) & Blacksmithing (stones/bars)
    _G.PCF_DB.prices[2835]  = { minBuyout = 20,  count = 500, lastUpdated = Mock.currentTime } -- Rough Stone
    _G.PCF_DB.prices[2836]  = { minBuyout = 60,  count = 500, lastUpdated = Mock.currentTime } -- Coarse Stone
    _G.PCF_DB.prices[2840]  = { minBuyout = 150, count = 500, lastUpdated = Mock.currentTime } -- Copper Bar
    _G.PCF_DB.prices[2589]  = { minBuyout = 30,  count = 500, lastUpdated = Mock.currentTime } -- Linen Cloth
    _G.PCF_DB.prices[2592]  = { minBuyout = 80,  count = 500, lastUpdated = Mock.currentTime } -- Wool Cloth
    _G.PCF_DB.prices[4306]  = { minBuyout = 220, count = 500, lastUpdated = Mock.currentTime } -- Silk Cloth
    _G.PCF_DB.prices[4338]  = { minBuyout = 350, count = 500, lastUpdated = Mock.currentTime } -- Mageweave Cloth
    _G.PCF_DB.prices[14047] = { minBuyout = 550, count = 500, lastUpdated = Mock.currentTime } -- Runecloth

    local bs75 = LE.PlanMilestonePath(164, 1, 75, { recoveryMode = "VENDOR" })
    Assert(bs75.reachedTarget == true and bs75.reachedSkill == 75 and #bs75.steps >= 2,
        string.format("Blacksmithing 1->75 roadmap succeeds cleanly in %d chained steps (Net: %s)",
            #bs75.steps, LL.Formatter.FormatMoneyPlain(bs75.totalNetCost)))

    local fa300 = LE.PlanMilestonePath(129, 1, 300, { recoveryMode = "VENDOR" })
    Assert(fa300.reachedTarget == true and fa300.reachedSkill == 300 and #fa300.steps >= 6,
        string.format("First Aid 1->300 full roadmap succeeds cleanly in %d chained steps (Net: %s)",
            #fa300.steps, LL.Formatter.FormatMoneyPlain(fa300.totalNetCost)))

    -- Top 5 Ranking Test: verify plays are strictly sorted ascending by CPSP
    _G.PCF_DB.prices[2996] = { minBuyout = 80, count = 500, lastUpdated = Mock.currentTime }
    local topPlays = LE.FindTopPlays(164, 35, 75, { recoveryMode = "VENDOR", ignoreInventory = true })
    Assert(#topPlays >= 3, "FindTopPlays returns multiple ranked Blacksmithing plays at skill 35")
    for i = 2, #topPlays do
        Assert(topPlays[i - 1].cpsp <= topPlays[i].cpsp + 1e-6,
            string.format("Top plays ranked ascending by CPSP (#%d <= #%d)", i - 1, i))
    end
end

return M
