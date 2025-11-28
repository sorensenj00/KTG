--[[
    Bootstrapper: Main (GameServer)
    Description: Central bootstrapper that initializes all server-side systems in the proper order.
    Handles initialization errors gracefully and prints status for debugging.
    
    Initialization Order:
    1. Lighting & Atmosphere (environment setup)
    2. Blaster System (weapon infrastructure)
    3. Core Systems (data & progression)
    4. World Logic (orbs)
    5. Controllers (entity logic)
    6. Spawners (entity spawning)
    
    Dependencies:
    - ServerScriptService.GameLoop.LightingSetup
    - ServerScriptService.Blaster.setup
    - ServerScriptService.GameLoop.ProgressionManager
    - ServerScriptService.GameLoop.MetaProgressionManager
    - ServerScriptService.GameLoop.WinnerManager
    - ServerScriptService.GameLoop.XPOrbManager
    - ServerScriptService.GameLoop.KillfeedManager
    - ServerScriptService.GameLoop.KillstreakManager
    - ServerScriptService.GameLoop.KillEffectsManager
    - ServerScriptService.GameLoop.BotController
    - ServerScriptService.GameLoop.PlayerSpawner
    - ServerScriptService.GameLoop.BotSpawner
    - ServerScriptService.GameLoop.VehicleSpawner
    
    Author: System
    Last Updated: 2025-01-20
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local GameLoop = ServerScriptService.GameLoop

-- Disable automatic character loading
Players.CharacterAutoLoads = false

print("-----------------------------------------")
print("       INITIALIZING KILL TO GROW         ")
print("-----------------------------------------")

-- Helper function to safely initialize a system
local function initializeSystem(name, initFunc)
	local success, err = pcall(initFunc)
	if not success then
		warn("❌ GameServer: Failed to initialize " .. name .. ":", err)
		return false
	else
		print("✅ GameServer: " .. name .. " initialized")
		return true
	end
end

-- 1. Initialize Blaster System
print(">> Initializing Blaster System...")
initializeSystem("BlasterSetup", function()
	local BlasterSetup = require(ServerScriptService.Blaster.setup)
	BlasterSetup.Initialize()
end)

-- 2. Load Modules (Definitions)
print(">> Loading Modules...")
local ProgressionManager = require(GameLoop.ProgressionManager)
local MetaProgressionManager = require(GameLoop.MetaProgressionManager)
local XPOrbManager = require(GameLoop.XPOrbManager)
local WinnerManager = require(GameLoop.WinnerManager)
local BotController = require(GameLoop.BotController)
local BotSpawner = require(GameLoop.BotSpawner)
local PlayerSpawner = require(GameLoop.PlayerSpawner)
local VehicleSpawner = require(GameLoop.VehicleSpawner)
local YeetCannonManager = require(GameLoop.YeetCannonManager)
local KillfeedManager = require(GameLoop.KillfeedManager)
local KillstreakManager = require(GameLoop.KillstreakManager)
local KillEffectsManager = require(GameLoop.KillEffectsManager)
local PassiveManager = require(GameLoop.PassiveManager)
local SafeZoneManager = require(GameLoop.SafeZoneManager)
local CombatLogManager = require(GameLoop.CombatLogManager)

-- 3. Start Core Systems (Data & Progression)
print(">> Starting Core Systems...")
initializeSystem("ProgressionManager", function()
	ProgressionManager.Start()
end)
initializeSystem("CombatLogManager", function()
	CombatLogManager.Start()
end)
initializeSystem("MetaProgressionManager", function()
	MetaProgressionManager.Start()
end)
initializeSystem("WinnerManager", function()
	WinnerManager.Start()
end)
initializeSystem("PassiveManager", function()
	PassiveManager.Start()
end)
initializeSystem("SafeZoneManager", function()
	SafeZoneManager.Start()
end)

-- 4. Start World Logic (Orbs)
print(">> Starting World Logic...")
initializeSystem("XPOrbManager", function()
	XPOrbManager.Start()
end)

-- 5. Start Controllers (Logic for entities)
print(">> Starting Controllers...")
initializeSystem("KillfeedManager", function()
	KillfeedManager.Start()
end)
initializeSystem("KillstreakManager", function()
	KillstreakManager.Start()
end)
initializeSystem("KillEffectsManager", function()
	KillEffectsManager.Start()
end)
initializeSystem("BotController", function()
	BotController.Start()
end)
initializeSystem("YeetCannonManager", function()
	YeetCannonManager.Start()
end)

-- 6. Start Spawners (Spawn entities)
-- Stagger slightly to ensure logic listeners are fully registered
print(">> Starting Spawners...")
task.wait(0.1)
initializeSystem("PlayerSpawner", function()
	PlayerSpawner.Start()
end)
initializeSystem("BotSpawner", function()
	BotSpawner.Start()
end)
initializeSystem("VehicleSpawner", function()
	VehicleSpawner.Start()
end)

print("-----------------------------------------")
print("       GAME LOOP FULLY STARTED           ")
print("-----------------------------------------")
