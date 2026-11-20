-- Isolates standalone PriceCheckerForever state before Leveling Lad loads Libs/PriceCheckerForever/Embed.xml
local LL = _G.LL or {}
_G.LL = LL
_G.LevelingLad = LL

if _G.PCF_INITIALIZED and type(_G.PCF) == "table" then
    LL._standalonePCFActive = true
    LL._savedStandalonePCF = _G.PCF
    LL._savedStandalonePCFDB = _G.PCF_DB
    LL._savedStandalonePCFAPI = _G.PCF_API

    -- Redirect embedded script file-load writes away from standalone PCF globals
    _G.PCF = {}
    _G.GPC = _G.PCF
    _G.PCF_API = {}
else
    LL._standalonePCFActive = false
    LL._savedStandalonePCF = nil
    LL._savedStandalonePCFDB = nil
    LL._savedStandalonePCFAPI = nil
end
