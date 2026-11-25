local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

LL.VendorDatabase = {}

-- Master table of unlimited-stock NPC-sold crafting reagents in Classic Era / WoW: Forever.
-- Base prices in copper (before reputation discount; MERCHANT_SHOW updates exact discounted price).
-- Guarantees Leveling Lad never prices vendor reagents at inflated Auction House rates.
local STATIC_VENDOR_BUY_PRICES = {
    -- Threads, Salt & Tailoring/Leatherworking Supplies
    [2320]  = { price = 10,     name = "Coarse Thread",           vendor = "Tailoring / Trade Supplies Vendor" },
    [2321]  = { price = 100,    name = "Fine Thread",             vendor = "Tailoring / Trade Supplies Vendor" },
    [4291]  = { price = 500,    name = "Silken Thread",           vendor = "Tailoring / Trade Supplies Vendor" },
    [8343]  = { price = 2000,   name = "Heavy Silken Thread",     vendor = "Tailoring / Trade Supplies Vendor" },
    [14341] = { price = 5000,   name = "Rune Thread",             vendor = "Tailoring / Trade Supplies Vendor" },
    [4289]  = { price = 50,     name = "Salt",                    vendor = "Leatherworking / Trade Supplies Vendor" },

    -- Dyes & Bleach
    [2324]  = { price = 25,     name = "Bleach",                  vendor = "Tailoring Supplies Vendor" },
    [2604]  = { price = 50,     name = "Red Dye",                 vendor = "Tailoring Supplies Vendor" },
    [6260]  = { price = 50,     name = "Blue Dye",                vendor = "Tailoring Supplies Vendor" },
    [2605]  = { price = 100,    name = "Green Dye",               vendor = "Tailoring Supplies Vendor" },
    [4340]  = { price = 350,    name = "Gray Dye",                vendor = "Tailoring / Leatherworking Vendor" },
    [4341]  = { price = 500,    name = "Yellow Dye",              vendor = "Tailoring Supplies Vendor" },
    [6261]  = { price = 1000,   name = "Orange Dye",              vendor = "Tailoring Supplies Vendor" },
    [2325]  = { price = 1000,   name = "Black Dye",               vendor = "Tailoring / Leatherworking Vendor" },
    [4342]  = { price = 2500,   name = "Purple Dye",              vendor = "Tailoring Supplies Vendor" },
    [10290] = { price = 2500,   name = "Pink Dye",                vendor = "Tailoring Supplies Vendor" },

    -- Flux, Coal, Wood, Rods & Engineering/Blacksmithing/Enchanting Supplies
    [2880]  = { price = 100,    name = "Weak Flux",               vendor = "Blacksmithing / Engineering Vendor" },
    [3466]  = { price = 2000,   name = "Strong Flux",             vendor = "Blacksmithing Supplies Vendor" },
    [18567] = { price = 150000, name = "Elemental Flux",          vendor = "Blacksmithing Supplies Vendor" },
    [3857]  = { price = 500,    name = "Coal",                    vendor = "Blacksmithing / Mining Vendor" },
    [4470]  = { price = 38,     name = "Simple Wood",             vendor = "Enchanting / Trade Goods Vendor" },
    [11291] = { price = 4500,   name = "Star Wood",               vendor = "Enchanting Supplies Vendor" },
    [4399]  = { price = 2000,   name = "Wooden Stock",            vendor = "Engineering Supplies Vendor" },
    [4400]  = { price = 2000,   name = "Heavy Stock",             vendor = "Engineering Supplies Vendor" },
    [6217]  = { price = 124,    name = "Copper Rod",              vendor = "Enchanting Supplies Vendor" },
    [10647] = { price = 2000,   name = "Engineer's Ink",          vendor = "Engineering Supplies Vendor" },
    [10648] = { price = 15,     name = "Common Parchment",        vendor = "Trade / Engineering Supplies Vendor" },

    -- Vials (Alchemy - unit price per 1 vial)
    [3371]  = { price = 4,      name = "Empty Vial",              vendor = "Alchemy Supplies Vendor" },
    [3372]  = { price = 40,     name = "Leaded Vial",             vendor = "Alchemy Supplies Vendor" },
    [8925]  = { price = 500,    name = "Crystal Vial",            vendor = "Alchemy Supplies Vendor" },
    [18256] = { price = 3000,   name = "Imbued Vial",             vendor = "Alchemy Supplies Vendor" },

    -- Cooking Spices & Vendor Beverages
    [2678]  = { price = 10,     name = "Mild Spices",             vendor = "Cooking / General Goods Vendor" },
    [2692]  = { price = 40,     name = "Hot Spices",              vendor = "Cooking Supplies Vendor" },
    [3713]  = { price = 160,    name = "Soothing Spices",         vendor = "Cooking Supplies Vendor" },
    [2665]  = { price = 10,     name = "Stormwind Seasoning Herbs", vendor = "Cooking Supplies Vendor" },
    [159]   = { price = 5,      name = "Refreshing Spring Water", vendor = "Innkeeper / General Goods Vendor" },
    [1179]  = { price = 25,     name = "Ice Cold Milk",           vendor = "Innkeeper / General Goods Vendor" },
    [2894]  = { price = 50,     name = "Rhapsody Malt",           vendor = "Cooking / Innkeeper Vendor" },
    [2596]  = { price = 120,    name = "Skin of Dwarven Stout",   vendor = "Innkeeper Vendor" },
    [2593]  = { price = 150,    name = "Flask of Stormwind Tawny", vendor = "Innkeeper Vendor" },
    [2594]  = { price = 1500,   name = "Flagon of Dwarven Honeymead", vendor = "Innkeeper Vendor" },
}

-- Seed metadata for Classic / WoW: Forever trade goods & crafted outputs.
-- Provides immediate names and vendor sell recovery floors even before GetItemInfo caches them.
local SEED_ITEM_METADATA = {
    -- Ores, Bars & Stones
    [2770]  = { name = "Copper Ore",               quality = 1, itemLevel = 5,  classID = 7, vendorSell = 5 },
    [2840]  = { name = "Copper Bar",               quality = 1, itemLevel = 5,  classID = 7, vendorSell = 10 },
    [2771]  = { name = "Tin Ore",                  quality = 1, itemLevel = 15, classID = 7, vendorSell = 25 },
    [3576]  = { name = "Tin Bar",                  quality = 1, itemLevel = 15, classID = 7, vendorSell = 30 },
    [2841]  = { name = "Bronze Bar",               quality = 1, itemLevel = 15, classID = 7, vendorSell = 50 },
    [2775]  = { name = "Silver Ore",               quality = 2, itemLevel = 15, classID = 7, vendorSell = 50 },
    [2842]  = { name = "Silver Bar",               quality = 2, itemLevel = 15, classID = 7, vendorSell = 100 },
    [2772]  = { name = "Iron Ore",                 quality = 1, itemLevel = 25, classID = 7, vendorSell = 75 },
    [3575]  = { name = "Iron Bar",                 quality = 1, itemLevel = 25, classID = 7, vendorSell = 200 },
    [3859]  = { name = "Steel Bar",                quality = 1, itemLevel = 30, classID = 7, vendorSell = 250 },
    [2776]  = { name = "Gold Ore",                 quality = 2, itemLevel = 31, classID = 7, vendorSell = 400 },
    [3577]  = { name = "Gold Bar",                 quality = 2, itemLevel = 31, classID = 7, vendorSell = 600 },
    [3858]  = { name = "Mithril Ore",              quality = 1, itemLevel = 35, classID = 7, vendorSell = 250 },
    [3860]  = { name = "Mithril Bar",              quality = 1, itemLevel = 35, classID = 7, vendorSell = 400 },
    [7911]  = { name = "Truesilver Ore",           quality = 2, itemLevel = 45, classID = 7, vendorSell = 500 },
    [6037]  = { name = "Truesilver Bar",           quality = 2, itemLevel = 45, classID = 7, vendorSell = 500 },
    [10620] = { name = "Thorium Ore",              quality = 1, itemLevel = 45, classID = 7, vendorSell = 500 },
    [12359] = { name = "Thorium Bar",              quality = 1, itemLevel = 45, classID = 7, vendorSell = 600 },
    [2835]  = { name = "Rough Stone",              quality = 1, itemLevel = 5,  classID = 7, vendorSell = 2 },
    [2836]  = { name = "Coarse Stone",             quality = 1, itemLevel = 15, classID = 7, vendorSell = 15 },
    [2838]  = { name = "Heavy Stone",              quality = 1, itemLevel = 25, classID = 7, vendorSell = 60 },
    [7912]  = { name = "Solid Stone",              quality = 1, itemLevel = 35, classID = 7, vendorSell = 100 },
    [12365] = { name = "Dense Stone",              quality = 1, itemLevel = 45, classID = 7, vendorSell = 250 },
    [3470]  = { name = "Rough Grinding Stone",     quality = 1, itemLevel = 5,  classID = 7, vendorSell = 5 },
    [3478]  = { name = "Coarse Grinding Stone",    quality = 1, itemLevel = 15, classID = 7, vendorSell = 10 },
    [3486]  = { name = "Heavy Grinding Stone",     quality = 1, itemLevel = 25, classID = 7, vendorSell = 100 },
    [7966]  = { name = "Solid Grinding Stone",     quality = 1, itemLevel = 35, classID = 7, vendorSell = 200 },
    [12644] = { name = "Dense Grinding Stone",     quality = 1, itemLevel = 50, classID = 7, vendorSell = 500 },

    -- Blacksmithing Outputs
    [2862]  = { name = "Rough Sharpening Stone",   quality = 1, itemLevel = 5,  classID = 0, vendorSell = 2 },
    [3239]  = { name = "Rough Weightstone",        quality = 1, itemLevel = 5,  classID = 0, vendorSell = 2 },
    [2853]  = { name = "Copper Chain Belt",        quality = 1, itemLevel = 6,  classID = 4, vendorSell = 65 },
    [2846]  = { name = "Copper Chain Pants",       quality = 1, itemLevel = 9,  classID = 4, vendorSell = 107 },
    [2863]  = { name = "Coarse Sharpening Stone",  quality = 1, itemLevel = 15, classID = 0, vendorSell = 5 },
    [3240]  = { name = "Coarse Weightstone",       quality = 1, itemLevel = 15, classID = 0, vendorSell = 5 },
    [3472]  = { name = "Runed Copper Belt",        quality = 1, itemLevel = 14, classID = 4, vendorSell = 185 },
    [3473]  = { name = "Runed Copper Bracers",     quality = 1, itemLevel = 16, classID = 4, vendorSell = 240 },
    [6338]  = { name = "Silver Rod",               quality = 1, itemLevel = 20, classID = 7, vendorSell = 150 },
    [2866]  = { name = "Rough Bronze Leggings",    quality = 1, itemLevel = 21, classID = 4, vendorSell = 460 },
    [3481]  = { name = "Rough Bronze Shoulders",   quality = 2, itemLevel = 22, classID = 4, vendorSell = 720 },
    [2871]  = { name = "Heavy Sharpening Stone",   quality = 1, itemLevel = 25, classID = 0, vendorSell = 25 },
    [3241]  = { name = "Heavy Weightstone",        quality = 1, itemLevel = 25, classID = 0, vendorSell = 25 },
    [2868]  = { name = "Patterned Bronze Bracers", quality = 2, itemLevel = 25, classID = 4, vendorSell = 680 },
    [5540]  = { name = "Iridescent Hammer",        quality = 2, itemLevel = 26, classID = 2, vendorSell = 3194 },
    [11128] = { name = "Golden Rod",               quality = 1, itemLevel = 30, classID = 7, vendorSell = 600 },
    [3842]  = { name = "Green Iron Leggings",      quality = 2, itemLevel = 31, classID = 4, vendorSell = 2050 },
    [3835]  = { name = "Green Iron Bracers",       quality = 2, itemLevel = 33, classID = 4, vendorSell = 1245 },
    [6040]  = { name = "Golden Scale Bracers",     quality = 2, itemLevel = 35, classID = 4, vendorSell = 1410 },
    [3844]  = { name = "Golden Scale Coif",        quality = 2, itemLevel = 38, classID = 4, vendorSell = 2320 },
    [7964]  = { name = "Solid Sharpening Stone",   quality = 1, itemLevel = 35, classID = 0, vendorSell = 50 },
    [7965]  = { name = "Solid Weightstone",        quality = 1, itemLevel = 35, classID = 0, vendorSell = 50 },
    [11144] = { name = "Truesilver Rod",           quality = 1, itemLevel = 40, classID = 7, vendorSell = 600 },
    [7920]  = { name = "Heavy Mithril Gauntlets",  quality = 2, itemLevel = 40, classID = 4, vendorSell = 2490 },
    [7919]  = { name = "Heavy Mithril Shoulder",   quality = 2, itemLevel = 40, classID = 4, vendorSell = 2780 },
    [7924]  = { name = "Mithril Scale Bracers",    quality = 2, itemLevel = 43, classID = 4, vendorSell = 2950 },
    [7969]  = { name = "Mithril Spurs",            quality = 2, itemLevel = 45, classID = 0, vendorSell = 1250 },
    [7931]  = { name = "Mithril Coif",             quality = 2, itemLevel = 47, classID = 4, vendorSell = 4680 },
    [12404] = { name = "Dense Sharpening Stone",   quality = 1, itemLevel = 45, classID = 0, vendorSell = 100 },
    [12643] = { name = "Dense Weightstone",        quality = 1, itemLevel = 45, classID = 0, vendorSell = 100 },
    [12406] = { name = "Thorium Belt",             quality = 2, itemLevel = 50, classID = 4, vendorSell = 5100 },
    [12408] = { name = "Thorium Bracers",          quality = 2, itemLevel = 51, classID = 4, vendorSell = 4550 },
    [12424] = { name = "Imperial Plate Belt",      quality = 2, itemLevel = 52, classID = 4, vendorSell = 6200 },
    [12425] = { name = "Imperial Plate Bracers",   quality = 2, itemLevel = 54, classID = 4, vendorSell = 6850 },
    [12409] = { name = "Thorium Boots",            quality = 2, itemLevel = 56, classID = 4, vendorSell = 8750 },
    [12426] = { name = "Imperial Plate Boots",     quality = 2, itemLevel = 59, classID = 4, vendorSell = 11400 },

    -- Cloth, Bolts & Tailoring Outputs
    [2589]  = { name = "Linen Cloth",              quality = 1, itemLevel = 5,  classID = 7, vendorSell = 13 },
    [2996]  = { name = "Bolt of Linen Cloth",      quality = 1, itemLevel = 5,  classID = 7, vendorSell = 30 },
    [2592]  = { name = "Wool Cloth",               quality = 1, itemLevel = 15, classID = 7, vendorSell = 33 },
    [2997]  = { name = "Bolt of Woolen Cloth",     quality = 1, itemLevel = 15, classID = 7, vendorSell = 100 },
    [4306]  = { name = "Silk Cloth",               quality = 1, itemLevel = 30, classID = 7, vendorSell = 150 },
    [4305]  = { name = "Bolt of Silk Cloth",       quality = 1, itemLevel = 30, classID = 7, vendorSell = 600 },
    [4338]  = { name = "Mageweave Cloth",          quality = 1, itemLevel = 40, classID = 7, vendorSell = 250 },
    [4339]  = { name = "Bolt of Mageweave",        quality = 1, itemLevel = 40, classID = 7, vendorSell = 1000 },
    [14047] = { name = "Runecloth",                quality = 1, itemLevel = 50, classID = 7, vendorSell = 400 },
    [14048] = { name = "Bolt of Runecloth",        quality = 1, itemLevel = 50, classID = 7, vendorSell = 1600 },
    [14227] = { name = "Ironweb Spider Silk",      quality = 1, itemLevel = 55, classID = 7, vendorSell = 500 },
    [6238]  = { name = "Brown Linen Robe",         quality = 1, itemLevel = 10, classID = 4, vendorSell = 64 },
    [4307]  = { name = "Heavy Linen Gloves",       quality = 1, itemLevel = 11, classID = 4, vendorSell = 76 },
    [4238]  = { name = "Linen Bag",                quality = 1, itemLevel = 10, classID = 1, vendorSell = 200 },
    [2580]  = { name = "Reinforced Linen Cape",    quality = 1, itemLevel = 15, classID = 4, vendorSell = 110 },
    [4240]  = { name = "Woolen Bag",               quality = 1, itemLevel = 20, classID = 1, vendorSell = 400 },
    [10047] = { name = "Simple Kilt",              quality = 1, itemLevel = 22, classID = 4, vendorSell = 240 },
    [4314]  = { name = "Double-stitched Woolen Shoulders", quality = 2, itemLevel = 23, classID = 4, vendorSell = 520 },
    [7048]  = { name = "Azure Silk Hood",          quality = 2, itemLevel = 29, classID = 4, vendorSell = 1280 },
    [4245]  = { name = "Small Silk Pack",          quality = 1, itemLevel = 30, classID = 1, vendorSell = 1500 },
    [7050]  = { name = "Silk Headband",            quality = 2, itemLevel = 32, classID = 4, vendorSell = 1650 },
    [4334]  = { name = "Formal White Shirt",       quality = 1, itemLevel = 34, classID = 4, vendorSell = 1500 },
    [7058]  = { name = "Crimson Silk Vest",        quality = 2, itemLevel = 37, classID = 4, vendorSell = 2166 },
    [7062]  = { name = "Crimson Silk Pantaloons",  quality = 2, itemLevel = 40, classID = 4, vendorSell = 2640 },
    [9999]  = { name = "Black Mageweave Leggings", quality = 2, itemLevel = 41, classID = 4, vendorSell = 2390 },
    [10003] = { name = "Black Mageweave Gloves",   quality = 2, itemLevel = 43, classID = 4, vendorSell = 2150 },
    [10024] = { name = "Black Mageweave Headband", quality = 2, itemLevel = 46, classID = 4, vendorSell = 3100 },
    [13856] = { name = "Runecloth Belt",           quality = 2, itemLevel = 51, classID = 4, vendorSell = 4247 },
    [14046] = { name = "Runecloth Bag",            quality = 1, itemLevel = 52, classID = 1, vendorSell = 3000 },
    [13863] = { name = "Runecloth Gloves",         quality = 2, itemLevel = 55, classID = 4, vendorSell = 6400 },
    [13864] = { name = "Runecloth Boots",          quality = 2, itemLevel = 56, classID = 4, vendorSell = 10035 },
    [13866] = { name = "Runecloth Headband",       quality = 2, itemLevel = 57, classID = 4, vendorSell = 9188 },

    -- Leather, Hides & Leatherworking Outputs
    [2934]  = { name = "Ruined Leather Scraps",    quality = 1, itemLevel = 1,  classID = 7, vendorSell = 7 },
    [2318]  = { name = "Light Leather",            quality = 1, itemLevel = 10, classID = 7, vendorSell = 15 },
    [783]   = { name = "Light Hide",               quality = 1, itemLevel = 10, classID = 7, vendorSell = 50 },
    [4231]  = { name = "Cured Light Hide",         quality = 1, itemLevel = 15, classID = 7, vendorSell = 90 },
    [2319]  = { name = "Medium Leather",           quality = 1, itemLevel = 20, classID = 7, vendorSell = 50 },
    [4232]  = { name = "Medium Hide",              quality = 1, itemLevel = 20, classID = 7, vendorSell = 120 },
    [4233]  = { name = "Cured Medium Hide",        quality = 1, itemLevel = 25, classID = 7, vendorSell = 230 },
    [4234]  = { name = "Heavy Leather",            quality = 1, itemLevel = 30, classID = 7, vendorSell = 150 },
    [4235]  = { name = "Heavy Hide",               quality = 1, itemLevel = 30, classID = 7, vendorSell = 200 },
    [4236]  = { name = "Cured Heavy Hide",         quality = 1, itemLevel = 35, classID = 7, vendorSell = 500 },
    [4304]  = { name = "Thick Leather",            quality = 1, itemLevel = 40, classID = 7, vendorSell = 300 },
    [8169]  = { name = "Thick Hide",               quality = 1, itemLevel = 40, classID = 7, vendorSell = 500 },
    [8150]  = { name = "Deeprock Salt",            quality = 1, itemLevel = 40, classID = 7, vendorSell = 250 },
    [8172]  = { name = "Cured Thick Hide",         quality = 1, itemLevel = 45, classID = 7, vendorSell = 700 },
    [8170]  = { name = "Rugged Leather",           quality = 1, itemLevel = 50, classID = 7, vendorSell = 500 },
    [2304]  = { name = "Light Armor Kit",          quality = 1, itemLevel = 5,  classID = 0, vendorSell = 15 },
    [7276]  = { name = "Handstitched Leather Cloak", quality = 1, itemLevel = 8, classID = 4, vendorSell = 38 },
    [4239]  = { name = "Embossed Leather Gloves",  quality = 1, itemLevel = 14, classID = 4, vendorSell = 135 },
    [4246]  = { name = "Fine Leather Belt",        quality = 1, itemLevel = 18, classID = 4, vendorSell = 210 },
    [2313]  = { name = "Medium Armor Kit",         quality = 1, itemLevel = 20, classID = 0, vendorSell = 150 },
    [2315]  = { name = "Dark Leather Boots",       quality = 2, itemLevel = 24, classID = 4, vendorSell = 710 },
    [4251]  = { name = "Hillman's Shoulders",      quality = 2, itemLevel = 26, classID = 4, vendorSell = 850 },
    [4265]  = { name = "Heavy Armor Kit",          quality = 1, itemLevel = 30, classID = 0, vendorSell = 450 },
    [3719]  = { name = "Hillman's Cloak",          quality = 2, itemLevel = 31, classID = 4, vendorSell = 1120 },
    [5964]  = { name = "Barbaric Shoulders",       quality = 2, itemLevel = 34, classID = 4, vendorSell = 1850 },
    [5966]  = { name = "Guardian Gloves",          quality = 2, itemLevel = 36, classID = 4, vendorSell = 1560 },
    [7378]  = { name = "Dusky Bracers",            quality = 2, itemLevel = 38, classID = 4, vendorSell = 2240 },
    [8173]  = { name = "Thick Armor Kit",          quality = 1, itemLevel = 40, classID = 0, vendorSell = 1200 },
    [8189]  = { name = "Nightscape Tunic",         quality = 2, itemLevel = 42, classID = 4, vendorSell = 3893 },
    [8191]  = { name = "Nightscape Headband",      quality = 2, itemLevel = 43, classID = 4, vendorSell = 3370 },
    [8193]  = { name = "Nightscape Pants",         quality = 2, itemLevel = 46, classID = 4, vendorSell = 5640 },
    [8197]  = { name = "Nightscape Boots",         quality = 2, itemLevel = 47, classID = 4, vendorSell = 5280 },
    [15564] = { name = "Rugged Armor Kit",         quality = 1, itemLevel = 50, classID = 0, vendorSell = 2000 },
    [15083] = { name = "Wicked Leather Gauntlets", quality = 2, itemLevel = 53, classID = 4, vendorSell = 5200 },
    [15084] = { name = "Wicked Leather Bracers",   quality = 2, itemLevel = 53, classID = 4, vendorSell = 4831 },
    [15086] = { name = "Wicked Leather Headband",  quality = 2, itemLevel = 56, classID = 4, vendorSell = 9821 },
    [15091] = { name = "Runic Leather Gauntlets",  quality = 2, itemLevel = 57, classID = 4, vendorSell = 8650 },

    -- Herbs & Alchemy Outputs
    [2447]  = { name = "Peacebloom",               quality = 1, itemLevel = 1,  classID = 7, vendorSell = 10 },
    [765]   = { name = "Silverleaf",               quality = 1, itemLevel = 1,  classID = 7, vendorSell = 10 },
    [2449]  = { name = "Earthroot",                quality = 1, itemLevel = 5,  classID = 7, vendorSell = 20 },
    [785]   = { name = "Mageroyal",                quality = 1, itemLevel = 10, classID = 7, vendorSell = 20 },
    [2450]  = { name = "Briarthorn",               quality = 1, itemLevel = 15, classID = 7, vendorSell = 25 },
    [2452]  = { name = "Swiftthistle",             quality = 1, itemLevel = 15, classID = 7, vendorSell = 15 },
    [2453]  = { name = "Bruiseweed",               quality = 1, itemLevel = 20, classID = 7, vendorSell = 25 },
    [3820]  = { name = "Stranglekelp",             quality = 1, itemLevel = 20, classID = 7, vendorSell = 100 },
    [3355]  = { name = "Wild Steelbloom",          quality = 1, itemLevel = 25, classID = 7, vendorSell = 50 },
    [3356]  = { name = "Kingsblood",               quality = 1, itemLevel = 25, classID = 7, vendorSell = 30 },
    [3357]  = { name = "Liferoot",                 quality = 1, itemLevel = 30, classID = 7, vendorSell = 75 },
    [3821]  = { name = "Goldthorn",                quality = 1, itemLevel = 34, classID = 7, vendorSell = 150 },
    [3358]  = { name = "Khadgar's Whisker",        quality = 1, itemLevel = 36, classID = 7, vendorSell = 175 },
    [8836]  = { name = "Arthas' Tears",            quality = 1, itemLevel = 44, classID = 7, vendorSell = 190 },
    [8838]  = { name = "Sungrass",                 quality = 1, itemLevel = 46, classID = 7, vendorSell = 300 },
    [8839]  = { name = "Blindweed",                quality = 1, itemLevel = 47, classID = 7, vendorSell = 325 },
    [8846]  = { name = "Gromsblood",               quality = 1, itemLevel = 50, classID = 7, vendorSell = 375 },
    [13463] = { name = "Dreamfoil",                quality = 1, itemLevel = 54, classID = 7, vendorSell = 500 },
    [13464] = { name = "Golden Sansam",            quality = 1, itemLevel = 52, classID = 7, vendorSell = 400 },
    [13465] = { name = "Mountain Silversage",      quality = 1, itemLevel = 56, classID = 7, vendorSell = 600 },
    [13467] = { name = "Icecap",                   quality = 1, itemLevel = 58, classID = 7, vendorSell = 625 },
    [118]   = { name = "Minor Healing Potion",     quality = 1, itemLevel = 5,  classID = 0, vendorSell = 5 },
    [2454]  = { name = "Elixir of Lion's Strength", quality = 1, itemLevel = 12, classID = 0, vendorSell = 25 },
    [858]   = { name = "Lesser Healing Potion",    quality = 1, itemLevel = 13, classID = 0, vendorSell = 25 },
    [2457]  = { name = "Elixir of Minor Agility",  quality = 1, itemLevel = 12, classID = 0, vendorSell = 30 },
    [3383]  = { name = "Elixir of Wisdom",         quality = 1, itemLevel = 20, classID = 0, vendorSell = 50 },
    [929]   = { name = "Healing Potion",           quality = 1, itemLevel = 22, classID = 0, vendorSell = 75 },
    [3385]  = { name = "Lesser Mana Potion",       quality = 1, itemLevel = 24, classID = 0, vendorSell = 60 },
    [3389]  = { name = "Elixir of Defense",        quality = 1, itemLevel = 26, classID = 0, vendorSell = 100 },
    [1710]  = { name = "Greater Healing Potion",   quality = 1, itemLevel = 31, classID = 0, vendorSell = 125 },
    [3827]  = { name = "Mana Potion",              quality = 1, itemLevel = 32, classID = 0, vendorSell = 120 },
    [8949]  = { name = "Elixir of Agility",        quality = 1, itemLevel = 37, classID = 0, vendorSell = 225 },
    [8951]  = { name = "Elixir of Greater Defense", quality = 1, itemLevel = 39, classID = 0, vendorSell = 250 },
    [6149]  = { name = "Greater Mana Potion",      quality = 1, itemLevel = 41, classID = 0, vendorSell = 250 },
    [3928]  = { name = "Superior Healing Potion",  quality = 1, itemLevel = 45, classID = 0, vendorSell = 250 },
    [9154]  = { name = "Elixir of Detect Undead",  quality = 1, itemLevel = 46, classID = 0, vendorSell = 250 },
    [9187]  = { name = "Elixir of Greater Agility", quality = 1, itemLevel = 48, classID = 0, vendorSell = 350 },
    [9233]  = { name = "Elixir of Detect Demon",   quality = 1, itemLevel = 50, classID = 0, vendorSell = 400 },
    [13443] = { name = "Superior Mana Potion",     quality = 1, itemLevel = 51, classID = 0, vendorSell = 500 },
    [13446] = { name = "Major Healing Potion",     quality = 1, itemLevel = 55, classID = 0, vendorSell = 500 },
    [13444] = { name = "Major Mana Potion",        quality = 1, itemLevel = 59, classID = 0, vendorSell = 600 },

    -- Engineering Parts & Outputs
    [4357]  = { name = "Rough Blasting Powder",    quality = 1, itemLevel = 5,  classID = 7, vendorSell = 4 },
    [4358]  = { name = "Rough Dynamite",           quality = 1, itemLevel = 10, classID = 0, vendorSell = 10 },
    [4359]  = { name = "Handful of Copper Bolts",  quality = 1, itemLevel = 10, classID = 7, vendorSell = 10 },
    [4361]  = { name = "Copper Tube",              quality = 1, itemLevel = 12, classID = 7, vendorSell = 45 },
    [4364]  = { name = "Coarse Blasting Powder",   quality = 1, itemLevel = 15, classID = 7, vendorSell = 12 },
    [4365]  = { name = "Coarse Dynamite",          quality = 1, itemLevel = 15, classID = 0, vendorSell = 35 },
    [4404]  = { name = "Silver Contact",           quality = 1, itemLevel = 18, classID = 7, vendorSell = 25 },
    [4371]  = { name = "Bronze Tube",              quality = 1, itemLevel = 21, classID = 7, vendorSell = 100 },
    [4377]  = { name = "Heavy Blasting Powder",    quality = 1, itemLevel = 25, classID = 7, vendorSell = 40 },
    [4375]  = { name = "Whirring Bronze Gizmo",    quality = 1, itemLevel = 25, classID = 7, vendorSell = 100 },
    [4382]  = { name = "Bronze Framework",         quality = 1, itemLevel = 29, classID = 7, vendorSell = 250 },
    [10558] = { name = "Gold Power Core",          quality = 1, itemLevel = 30, classID = 7, vendorSell = 200 },
    [10505] = { name = "Solid Blasting Powder",    quality = 1, itemLevel = 35, classID = 7, vendorSell = 80 },
    [4387]  = { name = "Iron Strut",               quality = 1, itemLevel = 35, classID = 7, vendorSell = 200 },
    [10559] = { name = "Mithril Tube",             quality = 1, itemLevel = 39, classID = 7, vendorSell = 600 },
    [10560] = { name = "Unstable Trigger",         quality = 1, itemLevel = 40, classID = 7, vendorSell = 350 },
    [10561] = { name = "Mithril Casing",           quality = 1, itemLevel = 43, classID = 7, vendorSell = 750 },
    [10562] = { name = "Hi-Explosive Bomb",        quality = 1, itemLevel = 47, classID = 0, vendorSell = 500 },
    [15992] = { name = "Dense Blasting Powder",    quality = 1, itemLevel = 50, classID = 7, vendorSell = 200 },
    [15994] = { name = "Thorium Widget",           quality = 1, itemLevel = 52, classID = 7, vendorSell = 750 },
    [16000] = { name = "Thorium Tube",             quality = 1, itemLevel = 55, classID = 7, vendorSell = 1500 },
    [15997] = { name = "Thorium Shells",           quality = 1, itemLevel = 57, classID = 6, vendorSell = 400 },

    -- Cooking Reagents & Outputs
    [2672]  = { name = "Stringy Wolf Meat",        quality = 1, itemLevel = 5,  classID = 7, vendorSell = 4 },
    [769]   = { name = "Chunk of Boar Meat",       quality = 1, itemLevel = 5,  classID = 7, vendorSell = 4 },
    [6889]  = { name = "Small Egg",                quality = 1, itemLevel = 5,  classID = 7, vendorSell = 4 },
    [3173]  = { name = "Bear Meat",                quality = 1, itemLevel = 12, classID = 7, vendorSell = 15 },
    [5503]  = { name = "Clam Meat",                quality = 1, itemLevel = 14, classID = 7, vendorSell = 12 },
    [2673]  = { name = "Crawler Meat",             quality = 1, itemLevel = 18, classID = 7, vendorSell = 25 },
    [6308]  = { name = "Raw Bristle Whisker Catfish", quality = 1, itemLevel = 20, classID = 7, vendorSell = 15 },
    [3685]  = { name = "Raptor Egg",               quality = 1, itemLevel = 25, classID = 7, vendorSell = 35 },
    [1015]  = { name = "Lean Wolf Flank",          quality = 1, itemLevel = 25, classID = 7, vendorSell = 35 },
    [8365]  = { name = "Raw Mithril Head Trout",   quality = 1, itemLevel = 30, classID = 7, vendorSell = 25 },
    [12184] = { name = "Raptor Flesh",             quality = 1, itemLevel = 35, classID = 7, vendorSell = 50 },
    [3712]  = { name = "Turtle Meat",              quality = 1, itemLevel = 35, classID = 7, vendorSell = 50 },
    [12205] = { name = "White Spider Meat",        quality = 1, itemLevel = 40, classID = 7, vendorSell = 75 },
    [12207] = { name = "Giant Egg",                quality = 1, itemLevel = 45, classID = 7, vendorSell = 100 },
    [12208] = { name = "Tender Wolf Meat",         quality = 1, itemLevel = 45, classID = 7, vendorSell = 100 },
    [13760] = { name = "Raw Sunscale Salmon",      quality = 1, itemLevel = 50, classID = 7, vendorSell = 100 },
    [20424] = { name = "Sandworm Meat",            quality = 1, itemLevel = 55, classID = 7, vendorSell = 125 },
    [13889] = { name = "Raw Whitescale Salmon",    quality = 1, itemLevel = 55, classID = 7, vendorSell = 150 },
    [2679]  = { name = "Charred Wolf Meat",        quality = 1, itemLevel = 5,  classID = 0, vendorSell = 5 },
    [2681]  = { name = "Roasted Boar Meat",        quality = 1, itemLevel = 5,  classID = 0, vendorSell = 5 },
    [6888]  = { name = "Herb Baked Egg",           quality = 1, itemLevel = 5,  classID = 0, vendorSell = 10 },
    [6890]  = { name = "Smoked Bear Meat",         quality = 1, itemLevel = 12, classID = 0, vendorSell = 25 },
    [5525]  = { name = "Boiled Clams",             quality = 1, itemLevel = 14, classID = 0, vendorSell = 25 },
    [2683]  = { name = "Crab Cake",                quality = 1, itemLevel = 18, classID = 0, vendorSell = 40 },
    [4593]  = { name = "Bristle Whisker Catfish",  quality = 1, itemLevel = 20, classID = 0, vendorSell = 40 },
    [3665]  = { name = "Curiously Tasty Omelet",   quality = 1, itemLevel = 25, classID = 0, vendorSell = 100 },
    [12209] = { name = "Lean Wolf Steak",          quality = 1, itemLevel = 25, classID = 0, vendorSell = 100 },
    [8364]  = { name = "Mithril Head Trout",       quality = 1, itemLevel = 30, classID = 0, vendorSell = 100 },
    [12210] = { name = "Roast Raptor",             quality = 1, itemLevel = 35, classID = 0, vendorSell = 200 },
    [3729]  = { name = "Soothing Turtle Bisque",   quality = 1, itemLevel = 35, classID = 0, vendorSell = 250 },
    [17222] = { name = "Spider Sausage",           quality = 1, itemLevel = 40, classID = 0, vendorSell = 300 },
    [12218] = { name = "Monster Omelet",           quality = 1, itemLevel = 45, classID = 0, vendorSell = 400 },
    [18045] = { name = "Tender Wolf Steak",        quality = 1, itemLevel = 45, classID = 0, vendorSell = 400 },
    [13932] = { name = "Poached Sunscale Salmon",  quality = 1, itemLevel = 50, classID = 0, vendorSell = 400 },
    [20452] = { name = "Smoked Desert Dumplings",  quality = 1, itemLevel = 55, classID = 0, vendorSell = 500 },
    [13935] = { name = "Baked Salmon",             quality = 1, itemLevel = 55, classID = 0, vendorSell = 500 },

    -- Gems, Pearls & Enchanting Materials / Outputs
    [1210]  = { name = "Shadowgem",                quality = 2, itemLevel = 20, classID = 7, vendorSell = 250 },
    [5500]  = { name = "Iridescent Pearl",         quality = 2, itemLevel = 25, classID = 7, vendorSell = 250 },
    [7971]  = { name = "Black Pearl",              quality = 2, itemLevel = 35, classID = 7, vendorSell = 1000 },
    [10940] = { name = "Strange Dust",             quality = 1, itemLevel = 5,  classID = 7, vendorSell = 0 },
    [11083] = { name = "Soul Dust",                quality = 1, itemLevel = 20, classID = 7, vendorSell = 0 },
    [11137] = { name = "Vision Dust",              quality = 1, itemLevel = 30, classID = 7, vendorSell = 0 },
    [11176] = { name = "Dream Dust",               quality = 1, itemLevel = 40, classID = 7, vendorSell = 0 },
    [16204] = { name = "Illusion Dust",            quality = 1, itemLevel = 50, classID = 7, vendorSell = 0 },
    [10938] = { name = "Lesser Magic Essence",     quality = 2, itemLevel = 10, classID = 7, vendorSell = 0 },
    [10939] = { name = "Greater Magic Essence",    quality = 2, itemLevel = 15, classID = 7, vendorSell = 0 },
    [10998] = { name = "Lesser Astral Essence",    quality = 2, itemLevel = 20, classID = 7, vendorSell = 0 },
    [11082] = { name = "Greater Astral Essence",   quality = 2, itemLevel = 25, classID = 7, vendorSell = 0 },
    [11134] = { name = "Lesser Mystic Essence",    quality = 2, itemLevel = 30, classID = 7, vendorSell = 0 },
    [11135] = { name = "Greater Mystic Essence",   quality = 2, itemLevel = 35, classID = 7, vendorSell = 0 },
    [11174] = { name = "Lesser Nether Essence",    quality = 2, itemLevel = 40, classID = 7, vendorSell = 0 },
    [11175] = { name = "Greater Nether Essence",   quality = 2, itemLevel = 45, classID = 7, vendorSell = 0 },
    [6218]  = { name = "Runed Copper Rod",         quality = 1, itemLevel = 5,  classID = 7, vendorSell = 0 },
    [6339]  = { name = "Runed Silver Rod",         quality = 1, itemLevel = 20, classID = 7, vendorSell = 0 },
    [11130] = { name = "Runed Golden Rod",         quality = 1, itemLevel = 30, classID = 7, vendorSell = 0 },
    [11145] = { name = "Runed Truesilver Rod",     quality = 1, itemLevel = 40, classID = 7, vendorSell = 0 },
    [11287] = { name = "Lesser Magic Wand",        quality = 2, itemLevel = 13, classID = 2, vendorSell = 519 },
    [11288] = { name = "Greater Magic Wand",       quality = 2, itemLevel = 18, classID = 2, vendorSell = 1546 },
    [11289] = { name = "Lesser Mystic Wand",       quality = 2, itemLevel = 30, classID = 2, vendorSell = 4159 },
    [11290] = { name = "Greater Mystic Wand",      quality = 2, itemLevel = 35, classID = 2, vendorSell = 8656 },

    -- First Aid Bandages
    [1251]  = { name = "Linen Bandage",            quality = 1, itemLevel = 5,  classID = 0, vendorSell = 10 },
    [2581]  = { name = "Heavy Linen Bandage",      quality = 1, itemLevel = 10, classID = 0, vendorSell = 20 },
    [3530]  = { name = "Wool Bandage",             quality = 1, itemLevel = 18, classID = 0, vendorSell = 28 },
    [3531]  = { name = "Heavy Wool Bandage",       quality = 1, itemLevel = 23, classID = 0, vendorSell = 57 },
    [6450]  = { name = "Silk Bandage",             quality = 1, itemLevel = 30, classID = 0, vendorSell = 100 },
    [6451]  = { name = "Heavy Silk Bandage",       quality = 1, itemLevel = 35, classID = 0, vendorSell = 200 },
    [8544]  = { name = "Mageweave Bandage",        quality = 1, itemLevel = 40, classID = 0, vendorSell = 200 },
    [8545]  = { name = "Heavy Mageweave Bandage",  quality = 1, itemLevel = 45, classID = 0, vendorSell = 400 },
    [14529] = { name = "Runecloth Bandage",        quality = 1, itemLevel = 50, classID = 0, vendorSell = 300 },
    [14530] = { name = "Heavy Runecloth Bandage",  quality = 1, itemLevel = 55, classID = 0, vendorSell = 600 },
}

for id, entry in pairs(STATIC_VENDOR_BUY_PRICES) do
    if not SEED_ITEM_METADATA[id] then
        SEED_ITEM_METADATA[id] = {
            name = entry.name,
            quality = 1,
            itemLevel = 1,
            classID = 7,
            vendorSell = math.floor(entry.price / 4),
        }
    end
end

LL.VendorDatabase.STATIC_VENDOR_BUY_PRICES = STATIC_VENDOR_BUY_PRICES

function LL.VendorDatabase.GetVendorBuyPrice(itemId)
    if not itemId or itemId <= 0 then return nil end
    if LevelingLad_DB and LevelingLad_DB.vendorBuyPrices and LevelingLad_DB.vendorBuyPrices[itemId] then
        local dynamicPrice = LevelingLad_DB.vendorBuyPrices[itemId]
        if type(dynamicPrice) == "number" and dynamicPrice > 0 then
            return dynamicPrice
        end
    end
    local staticEntry = STATIC_VENDOR_BUY_PRICES[itemId]
    if staticEntry and staticEntry.price and staticEntry.price > 0 then
        return staticEntry.price
    end
    return nil
end

function LL.VendorDatabase.GetVendorInfo(itemId)
    if not itemId or itemId <= 0 then return nil end
    local price = LL.VendorDatabase.GetVendorBuyPrice(itemId)
    if not price then return nil end
    local staticEntry = STATIC_VENDOR_BUY_PRICES[itemId]
    return {
        itemId = itemId,
        price = price,
        name = (staticEntry and staticEntry.name) or string.format("Item #%d", itemId),
        vendor = (staticEntry and staticEntry.vendor) or "NPC Trade Supplies Vendor",
    }
end

function LL.VendorDatabase.IsVendorReagent(itemId)
    return LL.VendorDatabase.GetVendorBuyPrice(itemId) ~= nil
end

local requestedItemDataLoads = {}

local function QueryGameItemInfo(target, skipServerRequest)
    if not target then return nil end
    local getInfo = (_G.C_Item and _G.C_Item.GetItemInfo) or _G.GetItemInfo
    if type(getInfo) ~= "function" then
        return nil
    end

    local ok, itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType,
        itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID = pcall(getInfo, target)
    if not ok or not itemName then
        if not skipServerRequest and type(target) == "number" and not requestedItemDataLoads[target]
            and _G.C_Item and type(_G.C_Item.RequestLoadItemDataByID) == "function" then
            requestedItemDataLoads[target] = true
            pcall(_G.C_Item.RequestLoadItemDataByID, target)
        end
        return nil
    end

    return {
        name = itemName,
        link = itemLink,
        quality = itemQuality or 1,
        itemLevel = itemLevel or 1,
        minLevel = itemMinLevel or 1,
        itemType = itemType,
        itemSubType = itemSubType,
        stackCount = itemStackCount or 1,
        invType = itemEquipLoc or "",
        texture = itemTexture,
        vendorSell = sellPrice or 0,
        classID = classID,
        subClassID = subclassID,
    }
end

function LL.VendorDatabase.GetItemMetadata(itemId, itemLink, skipServerRequest)
    if not itemId and type(itemLink) == "string" then
        itemId = tonumber(itemLink:match("item:(%d+)"))
    end
    if not itemId or itemId <= 0 then
        return nil
    end

    local cached = LevelingLad_DB and LevelingLad_DB.itemCache and LevelingLad_DB.itemCache[itemId]
    if cached and cached.name and cached.vendorSell ~= nil then
        if itemLink and not cached.link then
            cached.link = itemLink
        end
        return cached
    end

    local live = QueryGameItemInfo(itemLink or itemId, skipServerRequest)
    if live then
        if LevelingLad_DB and LevelingLad_DB.itemCache then
            LevelingLad_DB.itemCache[itemId] = live
        end
        return live
    end

    if cached then
        return cached
    end

    return SEED_ITEM_METADATA[itemId]
end

function LL.VendorDatabase.GetVendorSellPrice(itemId, itemLink)
    if not itemId or itemId <= 0 then return 0 end
    local meta = LL.VendorDatabase.GetItemMetadata(itemId, itemLink, true)
    if meta and type(meta.vendorSell) == "number" and meta.vendorSell > 0 then
        return meta.vendorSell
    end
    if _G.PCF and _G.PCF.ProviderRegistry and _G.PCF.ProviderRegistry.GetVendorPrice then
        local ok, vp = pcall(_G.PCF.ProviderRegistry.GetVendorPrice, itemLink, itemId)
        if ok and type(vp) == "number" and vp > 0 then
            return vp
        end
    end
    return 0
end

function LL.VendorDatabase.ScanOpenMerchant()
    if not _G.GetMerchantNumItems or not _G.GetMerchantItemInfo then
        return 0
    end
    local okNum, numItems = pcall(_G.GetMerchantNumItems)
    if not okNum or type(numItems) ~= "number" or numItems <= 0 then
        return 0
    end

    LevelingLad_DB = LevelingLad_DB or {}
    LevelingLad_DB.vendorBuyPrices = LevelingLad_DB.vendorBuyPrices or {}

    local learned = 0
    for i = 1, numItems do
        local okInfo, _, _, price, quantity, numAvailable = pcall(_G.GetMerchantItemInfo, i)
        if okInfo and price and price > 0 then
            local link = _G.GetMerchantItemLink and _G.GetMerchantItemLink(i)
            local itemId = link and tonumber(link:match("item:(%d+)"))
            if itemId and itemId > 0 then
                local qty = (quantity and quantity > 0) and quantity or 1
                local unitPrice = math.max(1, math.floor((price / qty) + 0.5))
                LL.VendorDatabase.GetItemMetadata(itemId, link)
                -- Unlimited stock (numAvailable == -1 or nil) is recorded as a reliable NPC vendor price
                if numAvailable == nil or numAvailable == -1 then
                    LevelingLad_DB.vendorBuyPrices[itemId] = unitPrice
                    learned = learned + 1
                end
            end
        end
    end
    return learned
end

function LL.VendorDatabase.Init()
    if LL.VendorDatabase._initialized then return end
    LL.VendorDatabase._initialized = true

    local frame = CreateFrame("Frame")
    if frame and frame.RegisterEvent then
        pcall(frame.RegisterEvent, frame, "MERCHANT_SHOW")
        pcall(frame.RegisterEvent, frame, "MERCHANT_UPDATE")
        frame:SetScript("OnEvent", function()
            LL.VendorDatabase.ScanOpenMerchant()
        end)
    end
    LL.VendorDatabase.frame = frame
end
