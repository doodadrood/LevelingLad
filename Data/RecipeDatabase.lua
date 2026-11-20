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

-- Complete Classic Era / WoW: Forever 1-300 recipe catalog indexed by [skillLine][recipeId].
-- Every recipe defines skill brackets [orange, yellow, green, gray], reagents = { [itemId] = qty },
-- outputItemId (nil for enchants), outputQty, and source.
local RECIPES = {
    -- ========================================================================
    -- BLACKSMITHING (164)
    -- ========================================================================
    [164] = {
        [2660] = {
            name = "Rough Sharpening Stone",
            skillLine = 164, minSkill = 1,
            orange = 1, yellow = 15, green = 35, gray = 55,
            reagents = { [2835] = 1 },
            outputItemId = 2862, outputQty = 1, source = "Trainer",
        },
        [3115] = {
            name = "Rough Weightstone",
            skillLine = 164, minSkill = 1,
            orange = 1, yellow = 15, green = 35, gray = 55,
            reagents = { [2835] = 1, [2589] = 1 },
            outputItemId = 3239, outputQty = 1, source = "Trainer",
        },
        [3320] = {
            name = "Rough Grinding Stone",
            skillLine = 164, minSkill = 25,
            orange = 25, yellow = 45, green = 60, gray = 75,
            reagents = { [2835] = 2 },
            outputItemId = 3470, outputQty = 1, source = "Trainer",
        },
        [2661] = {
            name = "Copper Chain Belt",
            skillLine = 164, minSkill = 30,
            orange = 30, yellow = 55, green = 70, gray = 85,
            reagents = { [2840] = 6 },
            outputItemId = 2853, outputQty = 1, source = "Trainer",
        },
        [2662] = {
            name = "Copper Chain Pants",
            skillLine = 164, minSkill = 35,
            orange = 35, yellow = 60, green = 75, gray = 90,
            reagents = { [2840] = 4 },
            outputItemId = 2846, outputQty = 1, source = "Trainer",
        },
        [2665] = {
            name = "Coarse Sharpening Stone",
            skillLine = 164, minSkill = 65,
            orange = 65, yellow = 85, green = 100, gray = 115,
            reagents = { [2836] = 1 },
            outputItemId = 2863, outputQty = 1, source = "Trainer",
        },
        [3326] = {
            name = "Coarse Grinding Stone",
            skillLine = 164, minSkill = 65,
            orange = 65, yellow = 85, green = 100, gray = 115,
            reagents = { [2836] = 2 },
            outputItemId = 3478, outputQty = 1, source = "Trainer",
        },
        [3323] = {
            name = "Runed Copper Belt",
            skillLine = 164, minSkill = 75,
            orange = 75, yellow = 100, green = 115, gray = 130,
            reagents = { [2840] = 10 },
            outputItemId = 3472, outputQty = 1, source = "Trainer",
        },
        [3324] = {
            name = "Runed Copper Bracers",
            skillLine = 164, minSkill = 90,
            orange = 90, yellow = 110, green = 125, gray = 140,
            reagents = { [2840] = 10, [3470] = 3 },
            outputItemId = 3473, outputQty = 1, source = "Trainer",
        },
        [7817] = {
            name = "Silver Rod",
            skillLine = 164, minSkill = 100,
            orange = 100, yellow = 115, green = 130, gray = 145,
            reagents = { [2842] = 1, [3470] = 2 },
            outputItemId = 6338, outputQty = 1, source = "Trainer",
        },
        [2670] = {
            name = "Rough Bronze Leggings",
            skillLine = 164, minSkill = 105,
            orange = 105, yellow = 125, green = 140, gray = 155,
            reagents = { [2841] = 6 },
            outputItemId = 2866, outputQty = 1, source = "Trainer",
        },
        [3328] = {
            name = "Rough Bronze Shoulders",
            skillLine = 164, minSkill = 110,
            orange = 110, yellow = 130, green = 145, gray = 160,
            reagents = { [2841] = 5, [1210] = 1 },
            outputItemId = 3481, outputQty = 1, source = "Trainer",
        },
        [2674] = {
            name = "Heavy Sharpening Stone",
            skillLine = 164, minSkill = 125,
            orange = 125, yellow = 145, green = 160, gray = 175,
            reagents = { [2838] = 1 },
            outputItemId = 2871, outputQty = 1, source = "Trainer",
        },
        [3337] = {
            name = "Heavy Grinding Stone",
            skillLine = 164, minSkill = 125,
            orange = 125, yellow = 145, green = 160, gray = 175,
            reagents = { [2838] = 3 },
            outputItemId = 3486, outputQty = 1, source = "Trainer",
        },
        [2672] = {
            name = "Patterned Bronze Bracers",
            skillLine = 164, minSkill = 130,
            orange = 130, yellow = 150, green = 165, gray = 180,
            reagents = { [2841] = 5, [3478] = 2 },
            outputItemId = 2868, outputQty = 1, source = "Trainer",
        },
        [6518] = {
            name = "Iridescent Hammer",
            skillLine = 164, minSkill = 140,
            orange = 140, yellow = 160, green = 175, gray = 190,
            reagents = { [2841] = 10, [5500] = 1, [2880] = 2 },
            outputItemId = 5540, outputQty = 1, source = "Trainer",
        },
        [14379] = {
            name = "Golden Rod",
            skillLine = 164, minSkill = 150,
            orange = 150, yellow = 165, green = 180, gray = 195,
            reagents = { [3577] = 1, [3478] = 2 },
            outputItemId = 11128, outputQty = 1, source = "Trainer",
        },
        [3501] = {
            name = "Green Iron Leggings",
            skillLine = 164, minSkill = 155,
            orange = 155, yellow = 175, green = 190, gray = 205,
            reagents = { [3575] = 8, [3486] = 1, [2605] = 1 },
            outputItemId = 3842, outputQty = 1, source = "Trainer",
        },
        [3508] = {
            name = "Green Iron Bracers",
            skillLine = 164, minSkill = 165,
            orange = 165, yellow = 185, green = 200, gray = 215,
            reagents = { [3575] = 6, [2605] = 1 },
            outputItemId = 3835, outputQty = 1, source = "Trainer",
        },
        [7223] = {
            name = "Golden Scale Bracers",
            skillLine = 164, minSkill = 170,
            orange = 170, yellow = 190, green = 205, gray = 220,
            reagents = { [3859] = 5, [3486] = 2 },
            outputItemId = 6040, outputQty = 1, source = "Trainer",
        },
        [3506] = {
            name = "Golden Scale Coif",
            skillLine = 164, minSkill = 185,
            orange = 185, yellow = 205, green = 220, gray = 235,
            reagents = { [3859] = 8, [3486] = 2 },
            outputItemId = 3844, outputQty = 1, source = "Trainer",
        },
        [9918] = {
            name = "Solid Sharpening Stone",
            skillLine = 164, minSkill = 200,
            orange = 200, yellow = 215, green = 230, gray = 245,
            reagents = { [7912] = 1 },
            outputItemId = 7964, outputQty = 1, source = "Trainer",
        },
        [9920] = {
            name = "Solid Grinding Stone",
            skillLine = 164, minSkill = 200,
            orange = 200, yellow = 215, green = 230, gray = 245,
            reagents = { [7912] = 4 },
            outputItemId = 7966, outputQty = 1, source = "Trainer",
        },
        [14380] = {
            name = "Truesilver Rod",
            skillLine = 164, minSkill = 200,
            orange = 200, yellow = 215, green = 230, gray = 245,
            reagents = { [6037] = 1, [3486] = 1 },
            outputItemId = 11144, outputQty = 1, source = "Trainer",
        },
        [9926] = {
            name = "Heavy Mithril Gauntlets",
            skillLine = 164, minSkill = 205,
            orange = 205, yellow = 225, green = 240, gray = 255,
            reagents = { [3860] = 6, [4339] = 4 },
            outputItemId = 7920, outputQty = 1, source = "Trainer",
        },
        [9928] = {
            name = "Heavy Mithril Shoulder",
            skillLine = 164, minSkill = 210,
            orange = 210, yellow = 230, green = 245, gray = 260,
            reagents = { [3860] = 8, [4234] = 6 },
            outputItemId = 7919, outputQty = 1, source = "Trainer",
        },
        [9935] = {
            name = "Mithril Scale Bracers",
            skillLine = 164, minSkill = 215,
            orange = 215, yellow = 235, green = 250, gray = 265,
            reagents = { [3860] = 8 },
            outputItemId = 7924, outputQty = 1, source = "Vendor",
        },
        [9959] = {
            name = "Mithril Spurs",
            skillLine = 164, minSkill = 235,
            orange = 235, yellow = 255, green = 270, gray = 285,
            reagents = { [3860] = 4, [7966] = 3 },
            outputItemId = 7969, outputQty = 1, source = "Trainer",
        },
        [9954] = {
            name = "Mithril Coif",
            skillLine = 164, minSkill = 235,
            orange = 235, yellow = 255, green = 270, gray = 285,
            reagents = { [3860] = 10, [4338] = 6 },
            outputItemId = 7931, outputQty = 1, source = "Trainer",
        },
        [16639] = {
            name = "Dense Sharpening Stone",
            skillLine = 164, minSkill = 250,
            orange = 250, yellow = 265, green = 280, gray = 295,
            reagents = { [12365] = 1 },
            outputItemId = 12404, outputQty = 1, source = "Trainer",
        },
        [16641] = {
            name = "Dense Grinding Stone",
            skillLine = 164, minSkill = 250,
            orange = 250, yellow = 265, green = 280, gray = 295,
            reagents = { [12365] = 4 },
            outputItemId = 12644, outputQty = 1, source = "Trainer",
        },
        [16643] = {
            name = "Thorium Belt",
            skillLine = 164, minSkill = 250,
            orange = 250, yellow = 270, green = 285, gray = 300,
            reagents = { [12359] = 12 },
            outputItemId = 12406, outputQty = 1, source = "Trainer",
        },
        [16644] = {
            name = "Thorium Bracers",
            skillLine = 164, minSkill = 255,
            orange = 255, yellow = 275, green = 290, gray = 305,
            reagents = { [12359] = 8 },
            outputItemId = 12408, outputQty = 1, source = "Trainer",
        },
        [16646] = {
            name = "Imperial Plate Belt",
            skillLine = 164, minSkill = 265,
            orange = 265, yellow = 285, green = 295, gray = 310,
            reagents = { [12359] = 10 },
            outputItemId = 12424, outputQty = 1, source = "Trainer",
        },
        [16647] = {
            name = "Imperial Plate Bracers",
            skillLine = 164, minSkill = 270,
            orange = 270, yellow = 290, green = 300, gray = 310,
            reagents = { [12359] = 12 },
            outputItemId = 12425, outputQty = 1, source = "Trainer",
        },
        [16649] = {
            name = "Thorium Boots",
            skillLine = 164, minSkill = 280,
            orange = 280, yellow = 295, green = 305, gray = 315,
            reagents = { [12359] = 12, [8170] = 8 },
            outputItemId = 12409, outputQty = 1, source = "Trainer",
        },
        [16658] = {
            name = "Imperial Plate Boots",
            skillLine = 164, minSkill = 295,
            orange = 295, yellow = 310, green = 320, gray = 330,
            reagents = { [12359] = 18 },
            outputItemId = 12426, outputQty = 1, source = "Trainer",
        },
    },

    -- ========================================================================
    -- TAILORING (197)
    -- ========================================================================
    [197] = {
        [2963] = {
            name = "Bolt of Linen Cloth",
            skillLine = 197, minSkill = 1,
            orange = 1, yellow = 25, green = 42, gray = 60,
            reagents = { [2589] = 2 },
            outputItemId = 2996, outputQty = 1, source = "Trainer",
        },
        [7623] = {
            name = "Brown Linen Robe",
            skillLine = 197, minSkill = 30,
            orange = 30, yellow = 55, green = 70, gray = 85,
            reagents = { [2996] = 3, [2320] = 1 },
            outputItemId = 6238, outputQty = 1, source = "Trainer",
        },
        [3840] = {
            name = "Heavy Linen Gloves",
            skillLine = 197, minSkill = 40,
            orange = 40, yellow = 65, green = 80, gray = 95,
            reagents = { [2996] = 2, [2320] = 1 },
            outputItemId = 4307, outputQty = 1, source = "Trainer",
        },
        [3755] = {
            name = "Linen Bag",
            skillLine = 197, minSkill = 45,
            orange = 45, yellow = 70, green = 85, gray = 100,
            reagents = { [2996] = 3, [2320] = 3 },
            outputItemId = 4238, outputQty = 1, source = "Trainer",
        },
        [2397] = {
            name = "Reinforced Linen Cape",
            skillLine = 197, minSkill = 60,
            orange = 60, yellow = 80, green = 95, gray = 110,
            reagents = { [2996] = 2, [2320] = 3 },
            outputItemId = 2580, outputQty = 1, source = "Trainer",
        },
        [2964] = {
            name = "Bolt of Woolen Cloth",
            skillLine = 197, minSkill = 75,
            orange = 75, yellow = 95, green = 110, gray = 125,
            reagents = { [2592] = 3 },
            outputItemId = 2997, outputQty = 1, source = "Trainer",
        },
        [3757] = {
            name = "Woolen Bag",
            skillLine = 197, minSkill = 80,
            orange = 80, yellow = 105, green = 120, gray = 135,
            reagents = { [2997] = 3, [2321] = 1 },
            outputItemId = 4240, outputQty = 1, source = "Trainer",
        },
        [12046] = {
            name = "Simple Kilt",
            skillLine = 197, minSkill = 100,
            orange = 100, yellow = 120, green = 135, gray = 150,
            reagents = { [2996] = 4, [2321] = 1 },
            outputItemId = 10047, outputQty = 1, source = "Trainer",
        },
        [3848] = {
            name = "Double-stitched Woolen Shoulders",
            skillLine = 197, minSkill = 105,
            orange = 105, yellow = 125, green = 140, gray = 155,
            reagents = { [2997] = 3, [2321] = 2 },
            outputItemId = 4314, outputQty = 1, source = "Trainer",
        },
        [3839] = {
            name = "Bolt of Silk Cloth",
            skillLine = 197, minSkill = 125,
            orange = 125, yellow = 145, green = 155, gray = 165,
            reagents = { [4306] = 4 },
            outputItemId = 4305, outputQty = 1, source = "Trainer",
        },
        [8760] = {
            name = "Azure Silk Hood",
            skillLine = 197, minSkill = 145,
            orange = 145, yellow = 165, green = 180, gray = 195,
            reagents = { [4305] = 2, [6260] = 2, [2321] = 1 },
            outputItemId = 7048, outputQty = 1, source = "Trainer",
        },
        [3813] = {
            name = "Small Silk Pack",
            skillLine = 197, minSkill = 150,
            orange = 150, yellow = 170, green = 185, gray = 200,
            reagents = { [4305] = 3, [4234] = 2, [2321] = 3 },
            outputItemId = 4245, outputQty = 1, source = "Trainer",
        },
        [8762] = {
            name = "Silk Headband",
            skillLine = 197, minSkill = 160,
            orange = 160, yellow = 180, green = 195, gray = 210,
            reagents = { [4305] = 3, [2321] = 2 },
            outputItemId = 7050, outputQty = 1, source = "Trainer",
        },
        [3871] = {
            name = "Formal White Shirt",
            skillLine = 197, minSkill = 170,
            orange = 170, yellow = 190, green = 205, gray = 220,
            reagents = { [4305] = 3, [2324] = 2, [2321] = 1 },
            outputItemId = 4334, outputQty = 1, source = "Trainer",
        },
        [3865] = {
            name = "Bolt of Mageweave",
            skillLine = 197, minSkill = 175,
            orange = 175, yellow = 190, green = 200, gray = 210,
            reagents = { [4338] = 5 },
            outputItemId = 4339, outputQty = 1, source = "Trainer",
        },
        [8772] = {
            name = "Crimson Silk Vest",
            skillLine = 197, minSkill = 185,
            orange = 185, yellow = 205, green = 220, gray = 235,
            reagents = { [4305] = 4, [2321] = 2, [2604] = 2 },
            outputItemId = 7058, outputQty = 1, source = "Trainer",
        },
        [8782] = {
            name = "Crimson Silk Pantaloons",
            skillLine = 197, minSkill = 200,
            orange = 200, yellow = 220, green = 235, gray = 250,
            reagents = { [4305] = 4, [2604] = 2, [4291] = 2 },
            outputItemId = 7062, outputQty = 1, source = "Trainer",
        },
        [12066] = {
            name = "Black Mageweave Leggings",
            skillLine = 197, minSkill = 205,
            orange = 205, yellow = 225, green = 240, gray = 255,
            reagents = { [4339] = 2, [4291] = 3 },
            outputItemId = 9999, outputQty = 1, source = "Trainer",
        },
        [12072] = {
            name = "Black Mageweave Gloves",
            skillLine = 197, minSkill = 215,
            orange = 215, yellow = 235, green = 250, gray = 265,
            reagents = { [4339] = 2, [8343] = 2 },
            outputItemId = 10003, outputQty = 1, source = "Trainer",
        },
        [12078] = {
            name = "Black Mageweave Headband",
            skillLine = 197, minSkill = 230,
            orange = 230, yellow = 250, green = 265, gray = 280,
            reagents = { [4339] = 3, [8343] = 2 },
            outputItemId = 10024, outputQty = 1, source = "Trainer",
        },
        [18401] = {
            name = "Bolt of Runecloth",
            skillLine = 197, minSkill = 250,
            orange = 250, yellow = 265, green = 275, gray = 285,
            reagents = { [14047] = 5 },
            outputItemId = 14048, outputQty = 1, source = "Trainer",
        },
        [18402] = {
            name = "Runecloth Belt",
            skillLine = 197, minSkill = 255,
            orange = 255, yellow = 275, green = 290, gray = 305,
            reagents = { [14048] = 3, [14341] = 1 },
            outputItemId = 13856, outputQty = 1, source = "Trainer",
        },
        [18405] = {
            name = "Runecloth Bag",
            skillLine = 197, minSkill = 260,
            orange = 260, yellow = 280, green = 295, gray = 310,
            reagents = { [14048] = 5, [8170] = 2, [14341] = 1 },
            outputItemId = 14046, outputQty = 1, source = "Vendor",
        },
        [18409] = {
            name = "Runecloth Gloves",
            skillLine = 197, minSkill = 275,
            orange = 275, yellow = 295, green = 305, gray = 315,
            reagents = { [14048] = 4, [8170] = 4, [14341] = 1 },
            outputItemId = 13863, outputQty = 1, source = "Vendor",
        },
        [18414] = {
            name = "Runecloth Boots",
            skillLine = 197, minSkill = 280,
            orange = 280, yellow = 300, green = 310, gray = 320,
            reagents = { [14048] = 4, [8170] = 4, [14341] = 1 },
            outputItemId = 13864, outputQty = 1, source = "Trainer",
        },
        [18418] = {
            name = "Runecloth Headband",
            skillLine = 197, minSkill = 295,
            orange = 295, yellow = 310, green = 320, gray = 330,
            reagents = { [14048] = 4, [14227] = 2, [14341] = 1 },
            outputItemId = 13866, outputQty = 1, source = "Trainer",
        },
    },

    -- ========================================================================
    -- LEATHERWORKING (165)
    -- ========================================================================
    [165] = {
        [2881] = {
            name = "Light Leather",
            skillLine = 165, minSkill = 1,
            orange = 1, yellow = 20, green = 35, gray = 50,
            reagents = { [2934] = 3 },
            outputItemId = 2318, outputQty = 1, source = "Trainer",
        },
        [2152] = {
            name = "Light Armor Kit",
            skillLine = 165, minSkill = 1,
            orange = 1, yellow = 30, green = 45, gray = 60,
            reagents = { [2318] = 1 },
            outputItemId = 2304, outputQty = 1, source = "Trainer",
        },
        [9058] = {
            name = "Handstitched Leather Cloak",
            skillLine = 165, minSkill = 20,
            orange = 20, yellow = 45, green = 60, gray = 75,
            reagents = { [2318] = 2, [2320] = 1 },
            outputItemId = 7276, outputQty = 1, source = "Trainer",
        },
        [3816] = {
            name = "Cured Light Hide",
            skillLine = 165, minSkill = 35,
            orange = 35, yellow = 55, green = 70, gray = 85,
            reagents = { [783] = 1, [4289] = 1 },
            outputItemId = 4231, outputQty = 1, source = "Trainer",
        },
        [3756] = {
            name = "Embossed Leather Gloves",
            skillLine = 165, minSkill = 55,
            orange = 55, yellow = 80, green = 95, gray = 110,
            reagents = { [2318] = 3, [2320] = 2 },
            outputItemId = 4239, outputQty = 1, source = "Trainer",
        },
        [3763] = {
            name = "Fine Leather Belt",
            skillLine = 165, minSkill = 85,
            orange = 85, yellow = 110, green = 125, gray = 140,
            reagents = { [2318] = 6, [2320] = 2 },
            outputItemId = 4246, outputQty = 1, source = "Trainer",
        },
        [3817] = {
            name = "Cured Medium Hide",
            skillLine = 165, minSkill = 100,
            orange = 100, yellow = 120, green = 135, gray = 150,
            reagents = { [4232] = 1, [4289] = 1 },
            outputItemId = 4233, outputQty = 1, source = "Trainer",
        },
        [2167] = {
            name = "Medium Armor Kit",
            skillLine = 165, minSkill = 100,
            orange = 100, yellow = 125, green = 140, gray = 155,
            reagents = { [2319] = 4, [2320] = 1 },
            outputItemId = 2313, outputQty = 1, source = "Trainer",
        },
        [2168] = {
            name = "Dark Leather Boots",
            skillLine = 165, minSkill = 120,
            orange = 120, yellow = 145, green = 160, gray = 175,
            reagents = { [2319] = 4, [2321] = 2, [4340] = 1 },
            outputItemId = 2315, outputQty = 1, source = "Trainer",
        },
        [3768] = {
            name = "Hillman's Shoulders",
            skillLine = 165, minSkill = 130,
            orange = 130, yellow = 155, green = 170, gray = 185,
            reagents = { [2319] = 4, [4233] = 1, [2321] = 1 },
            outputItemId = 4251, outputQty = 1, source = "Trainer",
        },
        [20649] = {
            name = "Heavy Leather",
            skillLine = 165, minSkill = 150,
            orange = 150, yellow = 165, green = 175, gray = 185,
            reagents = { [2319] = 5 },
            outputItemId = 4234, outputQty = 1, source = "Trainer",
        },
        [3818] = {
            name = "Cured Heavy Hide",
            skillLine = 165, minSkill = 150,
            orange = 150, yellow = 170, green = 185, gray = 200,
            reagents = { [4235] = 1, [4289] = 3 },
            outputItemId = 4236, outputQty = 1, source = "Trainer",
        },
        [3779] = {
            name = "Heavy Armor Kit",
            skillLine = 165, minSkill = 150,
            orange = 150, yellow = 175, green = 190, gray = 205,
            reagents = { [4234] = 5, [2321] = 1 },
            outputItemId = 4265, outputQty = 1, source = "Trainer",
        },
        [3772] = {
            name = "Hillman's Cloak",
            skillLine = 165, minSkill = 155,
            orange = 155, yellow = 180, green = 195, gray = 210,
            reagents = { [4234] = 5, [2321] = 2 },
            outputItemId = 3719, outputQty = 1, source = "Trainer",
        },
        [7135] = {
            name = "Barbaric Shoulders",
            skillLine = 165, minSkill = 170,
            orange = 170, yellow = 195, green = 210, gray = 225,
            reagents = { [4234] = 8, [4236] = 1, [2321] = 2 },
            outputItemId = 5964, outputQty = 1, source = "Trainer",
        },
        [7147] = {
            name = "Guardian Gloves",
            skillLine = 165, minSkill = 180,
            orange = 180, yellow = 205, green = 220, gray = 235,
            reagents = { [4234] = 4, [4236] = 1, [4291] = 1 },
            outputItemId = 5966, outputQty = 1, source = "Trainer",
        },
        [9198] = {
            name = "Dusky Bracers",
            skillLine = 165, minSkill = 190,
            orange = 190, yellow = 215, green = 230, gray = 245,
            reagents = { [4234] = 16, [2325] = 1, [4291] = 2 },
            outputItemId = 7378, outputQty = 1, source = "Trainer",
        },
        [10482] = {
            name = "Thick Armor Kit",
            skillLine = 165, minSkill = 200,
            orange = 200, yellow = 225, green = 240, gray = 255,
            reagents = { [4304] = 5, [4291] = 1 },
            outputItemId = 8173, outputQty = 1, source = "Trainer",
        },
        [10487] = {
            name = "Cured Thick Hide",
            skillLine = 165, minSkill = 200,
            orange = 200, yellow = 220, green = 235, gray = 250,
            reagents = { [8169] = 1, [8150] = 1 },
            outputItemId = 8172, outputQty = 1, source = "Trainer",
        },
        [10499] = {
            name = "Nightscape Tunic",
            skillLine = 165, minSkill = 205,
            orange = 205, yellow = 225, green = 240, gray = 255,
            reagents = { [4304] = 7, [4291] = 2 },
            outputItemId = 8189, outputQty = 1, source = "Trainer",
        },
        [10507] = {
            name = "Nightscape Headband",
            skillLine = 165, minSkill = 205,
            orange = 205, yellow = 225, green = 240, gray = 255,
            reagents = { [4304] = 5, [4291] = 2 },
            outputItemId = 8191, outputQty = 1, source = "Trainer",
        },
        [10542] = {
            name = "Nightscape Pants",
            skillLine = 165, minSkill = 230,
            orange = 230, yellow = 250, green = 265, gray = 280,
            reagents = { [4304] = 14, [4291] = 4 },
            outputItemId = 8193, outputQty = 1, source = "Trainer",
        },
        [10548] = {
            name = "Nightscape Boots",
            skillLine = 165, minSkill = 235,
            orange = 235, yellow = 255, green = 270, gray = 285,
            reagents = { [4304] = 16, [8343] = 2 },
            outputItemId = 8197, outputQty = 1, source = "Trainer",
        },
        [19058] = {
            name = "Rugged Armor Kit",
            skillLine = 165, minSkill = 250,
            orange = 250, yellow = 270, green = 285, gray = 300,
            reagents = { [8170] = 5 },
            outputItemId = 15564, outputQty = 1, source = "Trainer",
        },
        [19071] = {
            name = "Wicked Leather Bracers",
            skillLine = 165, minSkill = 265,
            orange = 265, yellow = 285, green = 295, gray = 310,
            reagents = { [8170] = 8, [2325] = 1, [14341] = 1 },
            outputItemId = 15084, outputQty = 1, source = "Trainer",
        },
        [19082] = {
            name = "Wicked Leather Headband",
            skillLine = 165, minSkill = 280,
            orange = 280, yellow = 300, green = 310, gray = 320,
            reagents = { [8170] = 12, [2325] = 1, [14341] = 1 },
            outputItemId = 15086, outputQty = 1, source = "Trainer",
        },
        [19091] = {
            name = "Runic Leather Gauntlets",
            skillLine = 165, minSkill = 285,
            orange = 285, yellow = 305, green = 315, gray = 325,
            reagents = { [8170] = 10, [14047] = 6, [14341] = 1 },
            outputItemId = 15091, outputQty = 1, source = "Trainer",
        },
    },

    -- ========================================================================
    -- ALCHEMY (171)
    -- ========================================================================
    [171] = {
        [2330] = {
            name = "Minor Healing Potion",
            skillLine = 171, minSkill = 1,
            orange = 1, yellow = 55, green = 70, gray = 85,
            reagents = { [2447] = 1, [765] = 1, [3371] = 1 },
            outputItemId = 118, outputQty = 1, source = "Trainer",
        },
        [2329] = {
            name = "Elixir of Lion's Strength",
            skillLine = 171, minSkill = 50,
            orange = 50, yellow = 75, green = 90, gray = 105,
            reagents = { [2449] = 1, [765] = 1, [3371] = 1 },
            outputItemId = 2454, outputQty = 1, source = "Trainer",
        },
        [2337] = {
            name = "Lesser Healing Potion",
            skillLine = 171, minSkill = 55,
            orange = 55, yellow = 95, green = 110, gray = 125,
            reagents = { [118] = 1, [2450] = 1 },
            outputItemId = 858, outputQty = 1, source = "Trainer",
        },
        [3230] = {
            name = "Elixir of Minor Agility",
            skillLine = 171, minSkill = 60,
            orange = 60, yellow = 85, green = 100, gray = 115,
            reagents = { [765] = 1, [2452] = 1, [3371] = 1 },
            outputItemId = 2457, outputQty = 1, source = "Trainer",
        },
        [3173] = {
            name = "Elixir of Wisdom",
            skillLine = 171, minSkill = 90,
            orange = 90, yellow = 115, green = 130, gray = 145,
            reagents = { [785] = 1, [2450] = 2, [3371] = 1 },
            outputItemId = 3383, outputQty = 1, source = "Trainer",
        },
        [3447] = {
            name = "Healing Potion",
            skillLine = 171, minSkill = 110,
            orange = 110, yellow = 135, green = 150, gray = 165,
            reagents = { [2453] = 1, [2450] = 1, [3372] = 1 },
            outputItemId = 929, outputQty = 1, source = "Trainer",
        },
        [3176] = {
            name = "Lesser Mana Potion",
            skillLine = 171, minSkill = 120,
            orange = 120, yellow = 145, green = 160, gray = 175,
            reagents = { [785] = 1, [3820] = 1, [3371] = 1 },
            outputItemId = 3385, outputQty = 1, source = "Trainer",
        },
        [3188] = {
            name = "Elixir of Defense",
            skillLine = 171, minSkill = 140,
            orange = 140, yellow = 165, green = 180, gray = 195,
            reagents = { [3355] = 1, [3820] = 1, [3372] = 1 },
            outputItemId = 3389, outputQty = 1, source = "Trainer",
        },
        [7181] = {
            name = "Greater Healing Potion",
            skillLine = 171, minSkill = 155,
            orange = 155, yellow = 180, green = 195, gray = 210,
            reagents = { [3357] = 1, [3356] = 1, [3372] = 1 },
            outputItemId = 1710, outputQty = 1, source = "Trainer",
        },
        [3452] = {
            name = "Mana Potion",
            skillLine = 171, minSkill = 160,
            orange = 160, yellow = 185, green = 200, gray = 215,
            reagents = { [3820] = 1, [3356] = 1, [3372] = 1 },
            outputItemId = 3827, outputQty = 1, source = "Trainer",
        },
        [11449] = {
            name = "Elixir of Agility",
            skillLine = 171, minSkill = 185,
            orange = 185, yellow = 210, green = 225, gray = 240,
            reagents = { [3820] = 1, [3821] = 1, [3372] = 1 },
            outputItemId = 8949, outputQty = 1, source = "Trainer",
        },
        [11450] = {
            name = "Elixir of Greater Defense",
            skillLine = 171, minSkill = 195,
            orange = 195, yellow = 220, green = 235, gray = 250,
            reagents = { [3355] = 1, [3821] = 1, [3372] = 1 },
            outputItemId = 8951, outputQty = 1, source = "Trainer",
        },
        [7183] = {
            name = "Greater Mana Potion",
            skillLine = 171, minSkill = 205,
            orange = 205, yellow = 230, green = 245, gray = 260,
            reagents = { [3358] = 1, [3821] = 1, [3372] = 1 },
            outputItemId = 6149, outputQty = 1, source = "Trainer",
        },
        [11457] = {
            name = "Superior Healing Potion",
            skillLine = 171, minSkill = 215,
            orange = 215, yellow = 240, green = 255, gray = 270,
            reagents = { [8838] = 1, [3358] = 1, [8925] = 1 },
            outputItemId = 3928, outputQty = 1, source = "Trainer",
        },
        [11460] = {
            name = "Elixir of Detect Undead",
            skillLine = 171, minSkill = 230,
            orange = 230, yellow = 255, green = 270, gray = 285,
            reagents = { [8836] = 1, [8925] = 1 },
            outputItemId = 9154, outputQty = 1, source = "Trainer",
        },
        [11467] = {
            name = "Elixir of Greater Agility",
            skillLine = 171, minSkill = 240,
            orange = 240, yellow = 265, green = 280, gray = 295,
            reagents = { [8838] = 1, [3821] = 1, [8925] = 1 },
            outputItemId = 9187, outputQty = 1, source = "Trainer",
        },
        [11478] = {
            name = "Elixir of Detect Demon",
            skillLine = 171, minSkill = 250,
            orange = 250, yellow = 275, green = 290, gray = 305,
            reagents = { [8846] = 2, [8925] = 1 },
            outputItemId = 9233, outputQty = 1, source = "Trainer",
        },
        [17553] = {
            name = "Superior Mana Potion",
            skillLine = 171, minSkill = 260,
            orange = 260, yellow = 285, green = 300, gray = 315,
            reagents = { [8838] = 2, [8839] = 2, [8925] = 1 },
            outputItemId = 13443, outputQty = 1, source = "Vendor",
        },
        [17556] = {
            name = "Major Healing Potion",
            skillLine = 171, minSkill = 275,
            orange = 275, yellow = 295, green = 305, gray = 315,
            reagents = { [13464] = 2, [13465] = 1, [8925] = 1 },
            outputItemId = 13446, outputQty = 1, source = "Vendor",
        },
        [17580] = {
            name = "Major Mana Potion",
            skillLine = 171, minSkill = 285,
            orange = 285, yellow = 305, green = 315, gray = 325,
            reagents = { [13463] = 3, [13467] = 2, [8925] = 1 },
            outputItemId = 13444, outputQty = 1, source = "Vendor",
        },
    },

    -- ========================================================================
    -- ENGINEERING (202)
    -- ========================================================================
    [202] = {
        [3918] = {
            name = "Rough Blasting Powder",
            skillLine = 202, minSkill = 1,
            orange = 1, yellow = 20, green = 35, gray = 50,
            reagents = { [2835] = 1 },
            outputItemId = 4357, outputQty = 1, source = "Trainer",
        },
        [3919] = {
            name = "Rough Dynamite",
            skillLine = 202, minSkill = 30,
            orange = 30, yellow = 50, green = 65, gray = 80,
            reagents = { [4357] = 2, [2589] = 1 },
            outputItemId = 4358, outputQty = 1, source = "Trainer",
        },
        [3922] = {
            name = "Handful of Copper Bolts",
            skillLine = 202, minSkill = 50,
            orange = 50, yellow = 65, green = 75, gray = 90,
            reagents = { [2840] = 1 },
            outputItemId = 4359, outputQty = 1, source = "Trainer",
        },
        [3924] = {
            name = "Copper Tube",
            skillLine = 202, minSkill = 50,
            orange = 50, yellow = 70, green = 85, gray = 100,
            reagents = { [2840] = 2, [2880] = 1 },
            outputItemId = 4361, outputQty = 1, source = "Trainer",
        },
        [3929] = {
            name = "Coarse Blasting Powder",
            skillLine = 202, minSkill = 75,
            orange = 75, yellow = 95, green = 110, gray = 125,
            reagents = { [2836] = 1 },
            outputItemId = 4364, outputQty = 1, source = "Trainer",
        },
        [3931] = {
            name = "Coarse Dynamite",
            skillLine = 202, minSkill = 75,
            orange = 75, yellow = 95, green = 110, gray = 125,
            reagents = { [4364] = 3, [2589] = 1 },
            outputItemId = 4365, outputQty = 1, source = "Trainer",
        },
        [3973] = {
            name = "Silver Contact",
            skillLine = 202, minSkill = 90,
            orange = 90, yellow = 105, green = 120, gray = 135,
            reagents = { [2842] = 1 },
            outputItemId = 4404, outputQty = 5, source = "Trainer",
        },
        [3938] = {
            name = "Bronze Tube",
            skillLine = 202, minSkill = 105,
            orange = 105, yellow = 125, green = 140, gray = 155,
            reagents = { [2841] = 2, [2880] = 1 },
            outputItemId = 4371, outputQty = 1, source = "Trainer",
        },
        [3946] = {
            name = "Heavy Blasting Powder",
            skillLine = 202, minSkill = 125,
            orange = 125, yellow = 145, green = 160, gray = 175,
            reagents = { [2838] = 1 },
            outputItemId = 4377, outputQty = 1, source = "Trainer",
        },
        [3944] = {
            name = "Whirring Bronze Gizmo",
            skillLine = 202, minSkill = 125,
            orange = 125, yellow = 145, green = 160, gray = 175,
            reagents = { [2841] = 2, [2592] = 1 },
            outputItemId = 4375, outputQty = 1, source = "Trainer",
        },
        [3952] = {
            name = "Bronze Framework",
            skillLine = 202, minSkill = 145,
            orange = 145, yellow = 165, green = 180, gray = 195,
            reagents = { [2841] = 2, [2319] = 1, [2592] = 1 },
            outputItemId = 4382, outputQty = 1, source = "Trainer",
        },
        [12584] = {
            name = "Gold Power Core",
            skillLine = 202, minSkill = 150,
            orange = 150, yellow = 170, green = 185, gray = 200,
            reagents = { [3577] = 1 },
            outputItemId = 10558, outputQty = 3, source = "Trainer",
        },
        [12585] = {
            name = "Solid Blasting Powder",
            skillLine = 202, minSkill = 175,
            orange = 175, yellow = 190, green = 200, gray = 210,
            reagents = { [7912] = 2 },
            outputItemId = 10505, outputQty = 1, source = "Trainer",
        },
        [3957] = {
            name = "Iron Strut",
            skillLine = 202, minSkill = 175,
            orange = 175, yellow = 195, green = 210, gray = 225,
            reagents = { [3575] = 2 },
            outputItemId = 4387, outputQty = 1, source = "Trainer",
        },
        [12595] = {
            name = "Mithril Tube",
            skillLine = 202, minSkill = 195,
            orange = 195, yellow = 215, green = 230, gray = 245,
            reagents = { [3860] = 3 },
            outputItemId = 10559, outputQty = 1, source = "Trainer",
        },
        [12597] = {
            name = "Unstable Trigger",
            skillLine = 202, minSkill = 200,
            orange = 200, yellow = 220, green = 235, gray = 250,
            reagents = { [3860] = 1, [4338] = 1, [10505] = 1 },
            outputItemId = 10560, outputQty = 1, source = "Trainer",
        },
        [12603] = {
            name = "Mithril Casing",
            skillLine = 202, minSkill = 215,
            orange = 215, yellow = 235, green = 250, gray = 265,
            reagents = { [3860] = 3 },
            outputItemId = 10561, outputQty = 1, source = "Trainer",
        },
        [12607] = {
            name = "Hi-Explosive Bomb",
            skillLine = 202, minSkill = 235,
            orange = 235, yellow = 255, green = 270, gray = 285,
            reagents = { [10561] = 2, [10560] = 1, [10505] = 2 },
            outputItemId = 10562, outputQty = 1, source = "Trainer",
        },
        [19788] = {
            name = "Dense Blasting Powder",
            skillLine = 202, minSkill = 250,
            orange = 250, yellow = 265, green = 275, gray = 290,
            reagents = { [12365] = 2 },
            outputItemId = 15992, outputQty = 1, source = "Trainer",
        },
        [19790] = {
            name = "Thorium Widget",
            skillLine = 202, minSkill = 260,
            orange = 260, yellow = 280, green = 290, gray = 305,
            reagents = { [12359] = 3, [14047] = 1 },
            outputItemId = 15994, outputQty = 1, source = "Vendor",
        },
        [19795] = {
            name = "Thorium Tube",
            skillLine = 202, minSkill = 275,
            orange = 275, yellow = 295, green = 305, gray = 315,
            reagents = { [12359] = 6 },
            outputItemId = 16000, outputQty = 1, source = "Vendor",
        },
        [19800] = {
            name = "Thorium Shells",
            skillLine = 202, minSkill = 285,
            orange = 285, yellow = 305, green = 315, gray = 325,
            reagents = { [12359] = 2, [15992] = 1 },
            outputItemId = 15997, outputQty = 1, source = "Vendor",
        },
    },

    -- ========================================================================
    -- COOKING (185)
    -- ========================================================================
    [185] = {
        [2538] = {
            name = "Charred Wolf Meat",
            skillLine = 185, minSkill = 1,
            orange = 1, yellow = 40, green = 60, gray = 80,
            reagents = { [2672] = 1 },
            outputItemId = 2679, outputQty = 1, source = "Trainer",
        },
        [2540] = {
            name = "Roasted Boar Meat",
            skillLine = 185, minSkill = 1,
            orange = 1, yellow = 40, green = 60, gray = 80,
            reagents = { [769] = 1 },
            outputItemId = 2681, outputQty = 1, source = "Trainer",
        },
        [8604] = {
            name = "Herb Baked Egg",
            skillLine = 185, minSkill = 1,
            orange = 1, yellow = 40, green = 60, gray = 80,
            reagents = { [6889] = 1, [2678] = 1 },
            outputItemId = 6888, outputQty = 1, source = "Trainer",
        },
        [8607] = {
            name = "Smoked Bear Meat",
            skillLine = 185, minSkill = 40,
            orange = 40, yellow = 75, green = 90, gray = 105,
            reagents = { [3173] = 1 },
            outputItemId = 6890, outputQty = 1, source = "Vendor",
        },
        [6499] = {
            name = "Boiled Clams",
            skillLine = 185, minSkill = 50,
            orange = 50, yellow = 85, green = 100, gray = 115,
            reagents = { [5503] = 1, [159] = 1 },
            outputItemId = 5525, outputQty = 1, source = "Trainer",
        },
        [2544] = {
            name = "Crab Cake",
            skillLine = 185, minSkill = 75,
            orange = 75, yellow = 110, green = 125, gray = 140,
            reagents = { [2673] = 1, [2678] = 1 },
            outputItemId = 2683, outputQty = 1, source = "Trainer",
        },
        [7753] = {
            name = "Bristle Whisker Catfish",
            skillLine = 185, minSkill = 100,
            orange = 100, yellow = 140, green = 160, gray = 180,
            reagents = { [6308] = 1 },
            outputItemId = 4593, outputQty = 1, source = "Vendor",
        },
        [3413] = {
            name = "Curiously Tasty Omelet",
            skillLine = 185, minSkill = 125,
            orange = 125, yellow = 160, green = 175, gray = 190,
            reagents = { [3685] = 1, [2692] = 1 },
            outputItemId = 3665, outputQty = 1, source = "Vendor",
        },
        [15853] = {
            name = "Lean Wolf Steak",
            skillLine = 185, minSkill = 125,
            orange = 125, yellow = 160, green = 175, gray = 190,
            reagents = { [1015] = 1, [2678] = 1 },
            outputItemId = 12209, outputQty = 1, source = "Vendor",
        },
        [10593] = {
            name = "Mithril Head Trout",
            skillLine = 185, minSkill = 150,
            orange = 150, yellow = 185, green = 200, gray = 215,
            reagents = { [8365] = 1 },
            outputItemId = 8364, outputQty = 1, source = "Vendor",
        },
        [15855] = {
            name = "Roast Raptor",
            skillLine = 185, minSkill = 175,
            orange = 175, yellow = 210, green = 225, gray = 240,
            reagents = { [12184] = 1, [2692] = 1 },
            outputItemId = 12210, outputQty = 1, source = "Vendor",
        },
        [4094] = {
            name = "Soothing Turtle Bisque",
            skillLine = 185, minSkill = 175,
            orange = 175, yellow = 210, green = 225, gray = 240,
            reagents = { [3712] = 1, [3713] = 1 },
            outputItemId = 3729, outputQty = 1, source = "Vendor",
        },
        [21175] = {
            name = "Spider Sausage",
            skillLine = 185, minSkill = 200,
            orange = 200, yellow = 235, green = 250, gray = 265,
            reagents = { [12205] = 2 },
            outputItemId = 17222, outputQty = 1, source = "Trainer",
        },
        [15935] = {
            name = "Monster Omelet",
            skillLine = 185, minSkill = 225,
            orange = 225, yellow = 255, green = 270, gray = 285,
            reagents = { [12207] = 1, [3713] = 2 },
            outputItemId = 12218, outputQty = 1, source = "Vendor",
        },
        [22480] = {
            name = "Tender Wolf Steak",
            skillLine = 185, minSkill = 225,
            orange = 225, yellow = 255, green = 270, gray = 285,
            reagents = { [12208] = 1, [3713] = 1 },
            outputItemId = 18045, outputQty = 1, source = "Vendor",
        },
        [18244] = {
            name = "Poached Sunscale Salmon",
            skillLine = 185, minSkill = 250,
            orange = 250, yellow = 280, green = 295, gray = 310,
            reagents = { [13760] = 1 },
            outputItemId = 13932, outputQty = 1, source = "Vendor",
        },
        [24801] = {
            name = "Smoked Desert Dumplings",
            skillLine = 185, minSkill = 275,
            orange = 275, yellow = 295, green = 305, gray = 315,
            reagents = { [20424] = 1, [3713] = 1 },
            outputItemId = 20452, outputQty = 1, source = "Quest",
        },
        [18247] = {
            name = "Baked Salmon",
            skillLine = 185, minSkill = 275,
            orange = 275, yellow = 295, green = 305, gray = 315,
            reagents = { [13889] = 1 },
            outputItemId = 13935, outputQty = 1, source = "Vendor",
        },
    },

    -- ========================================================================
    -- ENCHANTING (333)
    -- ========================================================================
    [333] = {
        [7421] = {
            name = "Runed Copper Rod",
            skillLine = 333, minSkill = 1,
            orange = 1, yellow = 25, green = 40, gray = 55,
            reagents = { [6217] = 1, [10940] = 1, [10938] = 1 },
            outputItemId = 6218, outputQty = 1, source = "Trainer",
        },
        [7418] = {
            name = "Enchant Bracer - Minor Health",
            skillLine = 333, minSkill = 1,
            orange = 1, yellow = 50, green = 70, gray = 90,
            reagents = { [10940] = 1 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [14293] = {
            name = "Lesser Magic Wand",
            skillLine = 333, minSkill = 10,
            orange = 10, yellow = 30, green = 50, gray = 70,
            reagents = { [4470] = 1, [10938] = 1 },
            outputItemId = 11287, outputQty = 1, source = "Trainer",
        },
        [7457] = {
            name = "Enchant Bracer - Minor Stamina",
            skillLine = 333, minSkill = 50,
            orange = 50, yellow = 80, green = 95, gray = 110,
            reagents = { [10940] = 3 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [14807] = {
            name = "Greater Magic Wand",
            skillLine = 333, minSkill = 70,
            orange = 70, yellow = 90, green = 110, gray = 130,
            reagents = { [4470] = 1, [10939] = 1 },
            outputItemId = 11288, outputQty = 1, source = "Trainer",
        },
        [7779] = {
            name = "Enchant Bracer - Minor Agility",
            skillLine = 333, minSkill = 90,
            orange = 90, yellow = 115, green = 130, gray = 145,
            reagents = { [10940] = 2, [10939] = 1 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [7795] = {
            name = "Runed Silver Rod",
            skillLine = 333, minSkill = 100,
            orange = 100, yellow = 120, green = 135, gray = 150,
            reagents = { [6338] = 1, [10940] = 6, [10939] = 3, [1210] = 1 },
            outputItemId = 6339, outputQty = 1, source = "Trainer",
        },
        [13419] = {
            name = "Enchant Cloak - Minor Agility",
            skillLine = 333, minSkill = 110,
            orange = 110, yellow = 135, green = 150, gray = 165,
            reagents = { [10998] = 1 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [13501] = {
            name = "Enchant Bracer - Lesser Stamina",
            skillLine = 333, minSkill = 130,
            orange = 130, yellow = 155, green = 170, gray = 185,
            reagents = { [11083] = 2 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [13628] = {
            name = "Runed Golden Rod",
            skillLine = 333, minSkill = 150,
            orange = 150, yellow = 170, green = 185, gray = 200,
            reagents = { [11128] = 1, [5500] = 1, [11082] = 2, [11083] = 2 },
            outputItemId = 11130, outputQty = 1, source = "Trainer",
        },
        [14809] = {
            name = "Lesser Mystic Wand",
            skillLine = 333, minSkill = 155,
            orange = 155, yellow = 175, green = 190, gray = 205,
            reagents = { [11291] = 1, [11134] = 1 },
            outputItemId = 11289, outputQty = 1, source = "Trainer",
        },
        [13642] = {
            name = "Enchant Bracer - Spirit",
            skillLine = 333, minSkill = 165,
            orange = 165, yellow = 190, green = 205, gray = 220,
            reagents = { [11134] = 1 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [14810] = {
            name = "Greater Mystic Wand",
            skillLine = 333, minSkill = 175,
            orange = 175, yellow = 195, green = 210, gray = 225,
            reagents = { [11291] = 1, [11135] = 1 },
            outputItemId = 11290, outputQty = 1, source = "Trainer",
        },
        [13661] = {
            name = "Enchant Bracer - Strength",
            skillLine = 333, minSkill = 185,
            orange = 185, yellow = 210, green = 225, gray = 240,
            reagents = { [11137] = 1 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [13702] = {
            name = "Runed Truesilver Rod",
            skillLine = 333, minSkill = 200,
            orange = 200, yellow = 220, green = 235, gray = 250,
            reagents = { [11144] = 1, [7971] = 1, [11135] = 2, [11137] = 2 },
            outputItemId = 11145, outputQty = 1, source = "Trainer",
        },
        [13746] = {
            name = "Enchant Cloak - Greater Defense",
            skillLine = 333, minSkill = 205,
            orange = 205, yellow = 230, green = 245, gray = 260,
            reagents = { [11137] = 3 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [13815] = {
            name = "Enchant Gloves - Agility",
            skillLine = 333, minSkill = 225,
            orange = 225, yellow = 245, green = 260, gray = 275,
            reagents = { [11174] = 1, [11137] = 1 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [13945] = {
            name = "Enchant Bracer - Greater Stamina",
            skillLine = 333, minSkill = 245,
            orange = 245, yellow = 265, green = 280, gray = 295,
            reagents = { [11176] = 5 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Trainer",
        },
        [20017] = {
            name = "Enchant Shield - Greater Stamina",
            skillLine = 333, minSkill = 265,
            orange = 265, yellow = 285, green = 295, gray = 310,
            reagents = { [11176] = 10 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Vendor",
        },
        [20015] = {
            name = "Enchant Cloak - Superior Defense",
            skillLine = 333, minSkill = 285,
            orange = 285, yellow = 305, green = 315, gray = 325,
            reagents = { [16204] = 8 },
            outputItemId = nil, outputQty = 1, isEnchant = true, source = "Vendor",
        },
    },

    -- ========================================================================
    -- FIRST AID (129)
    -- ========================================================================
    [129] = {
        [3275] = {
            name = "Linen Bandage",
            skillLine = 129, minSkill = 1,
            orange = 1, yellow = 40, green = 55, gray = 70,
            reagents = { [2589] = 1 },
            outputItemId = 1251, outputQty = 1, source = "Trainer",
        },
        [3276] = {
            name = "Heavy Linen Bandage",
            skillLine = 129, minSkill = 40,
            orange = 40, yellow = 60, green = 75, gray = 90,
            reagents = { [2589] = 2 },
            outputItemId = 2581, outputQty = 1, source = "Trainer",
        },
        [3277] = {
            name = "Wool Bandage",
            skillLine = 129, minSkill = 80,
            orange = 80, yellow = 115, green = 130, gray = 145,
            reagents = { [2592] = 1 },
            outputItemId = 3530, outputQty = 1, source = "Trainer",
        },
        [3278] = {
            name = "Heavy Wool Bandage",
            skillLine = 129, minSkill = 115,
            orange = 115, yellow = 135, green = 150, gray = 165,
            reagents = { [2592] = 2 },
            outputItemId = 3531, outputQty = 1, source = "Trainer",
        },
        [7928] = {
            name = "Silk Bandage",
            skillLine = 129, minSkill = 150,
            orange = 150, yellow = 180, green = 195, gray = 210,
            reagents = { [4306] = 1 },
            outputItemId = 6450, outputQty = 1, source = "Trainer",
        },
        [7929] = {
            name = "Heavy Silk Bandage",
            skillLine = 129, minSkill = 180,
            orange = 180, yellow = 200, green = 215, gray = 230,
            reagents = { [4306] = 2 },
            outputItemId = 6451, outputQty = 1, source = "Vendor",
        },
        [10840] = {
            name = "Mageweave Bandage",
            skillLine = 129, minSkill = 210,
            orange = 210, yellow = 240, green = 255, gray = 270,
            reagents = { [4338] = 1 },
            outputItemId = 8544, outputQty = 1, source = "Vendor",
        },
        [10841] = {
            name = "Heavy Mageweave Bandage",
            skillLine = 129, minSkill = 240,
            orange = 240, yellow = 260, green = 275, gray = 290,
            reagents = { [4338] = 2 },
            outputItemId = 8545, outputQty = 1, source = "Trainer",
        },
        [18629] = {
            name = "Runecloth Bandage",
            skillLine = 129, minSkill = 260,
            orange = 260, yellow = 290, green = 300, gray = 315,
            reagents = { [14047] = 1 },
            outputItemId = 14529, outputQty = 1, source = "Trainer",
        },
        [18630] = {
            name = "Heavy Runecloth Bandage",
            skillLine = 129, minSkill = 290,
            orange = 290, yellow = 310, green = 320, gray = 330,
            reagents = { [14047] = 2 },
            outputItemId = 14530, outputQty = 1, source = "Trainer",
        },
    },

    -- ========================================================================
    -- MINING / SMELTING (186)
    -- ========================================================================
    [186] = {
        [2657] = {
            name = "Smelt Copper",
            skillLine = 186, minSkill = 1,
            orange = 1, yellow = 25, green = 47, gray = 70,
            reagents = { [2770] = 1 },
            outputItemId = 2840, outputQty = 1, source = "Trainer",
        },
        [3304] = {
            name = "Smelt Tin",
            skillLine = 186, minSkill = 65,
            orange = 65, yellow = 65, green = 70, gray = 75,
            reagents = { [2771] = 1 },
            outputItemId = 3576, outputQty = 1, source = "Trainer",
        },
        [2659] = {
            name = "Smelt Bronze",
            skillLine = 186, minSkill = 65,
            orange = 65, yellow = 65, green = 95, gray = 115,
            reagents = { [2840] = 1, [3576] = 1 },
            outputItemId = 2841, outputQty = 2, source = "Trainer",
        },
        [2658] = {
            name = "Smelt Silver",
            skillLine = 186, minSkill = 75,
            orange = 75, yellow = 115, green = 122, gray = 130,
            reagents = { [2775] = 1 },
            outputItemId = 2842, outputQty = 1, source = "Trainer",
        },
        [3307] = {
            name = "Smelt Iron",
            skillLine = 186, minSkill = 125,
            orange = 125, yellow = 130, green = 145, gray = 160,
            reagents = { [2772] = 1 },
            outputItemId = 3575, outputQty = 1, source = "Trainer",
        },
        [3308] = {
            name = "Smelt Gold",
            skillLine = 186, minSkill = 155,
            orange = 155, yellow = 170, green = 177, gray = 185,
            reagents = { [2776] = 1 },
            outputItemId = 3577, outputQty = 1, source = "Trainer",
        },
        [3569] = {
            name = "Smelt Steel",
            skillLine = 186, minSkill = 165,
            orange = 165, yellow = 165, green = 170, gray = 175,
            reagents = { [3575] = 1, [3857] = 1 },
            outputItemId = 3859, outputQty = 1, source = "Trainer",
        },
        [10097] = {
            name = "Smelt Mithril",
            skillLine = 186, minSkill = 175,
            orange = 175, yellow = 175, green = 202, gray = 230,
            reagents = { [3858] = 1 },
            outputItemId = 3860, outputQty = 1, source = "Trainer",
        },
        [10098] = {
            name = "Smelt Truesilver",
            skillLine = 186, minSkill = 230,
            orange = 230, yellow = 250, green = 270, gray = 290,
            reagents = { [7911] = 1 },
            outputItemId = 6037, outputQty = 1, source = "Trainer",
        },
        [16153] = {
            name = "Smelt Thorium",
            skillLine = 186, minSkill = 250,
            orange = 250, yellow = 250, green = 270, gray = 290,
            reagents = { [10620] = 1 },
            outputItemId = 12359, outputQty = 1, source = "Trainer",
        },
    },
}

-- Populate recipeId & canonical profession name on every static recipe entry
local RECIPE_BY_ID = {}
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

LL.RecipeDatabase.RECIPES = RECIPES

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

-- Queries the character's current learned crafting professions & skill ranks.
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

    -- 2. Legacy GetNumSkillLines / GetSkillLineInfo (Classic Era)
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

    -- 3. Currently open TradeSkill window (Legacy or Modern)
    if _G.C_TradeSkillUI and _G.C_TradeSkillUI.GetBaseProfessionInfo then
        local okB, info = pcall(_G.C_TradeSkillUI.GetBaseProfessionInfo)
        if okB and type(info) == "table" and (info.skillLevel or 0) > 0 then
            local pid = (type(info.parentProfessionID) == "number" and info.parentProfessionID > 0) and info.parentProfessionID or info.professionID
            local pname = info.parentProfessionName or info.professionName
            RecordSkill(pid, pname, info.skillLevel, info.maxSkillLevel)
        end
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
