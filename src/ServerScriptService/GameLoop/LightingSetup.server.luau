--[[
    LightingSetup - Server Script
    Automatically initializes lighting effects for the game.
    Uses LightingService to ensure consistent lighting settings.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local LightingService = require(ServerScriptService.Services.World.LightingService)

LightingService.Start()
