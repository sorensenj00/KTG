--[[
    Server Entry Point
    Description: Automatically discovers and initializes all services using a two-phase pattern.
    Phase 1 (Init): Internal setup without dependencies
    Phase 2 (Start): Event listening and inter-service communication
    
    Author: Refactored
    Last Updated: 2025-11-29
]]

local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- Disable automatic character loading
Players.CharacterAutoLoads = false

print("-----------------------------------------")
print("       INITIALIZING KILL TO GROW         ")
print("-----------------------------------------")

-- Helper function to safely initialize a system
local function initializeSystem(name: string, initFunc: () -> ())
	local success, err = pcall(initFunc)
	if not success then
		warn("❌ GameServer: Failed to initialize " .. name .. ":", err)
		return false
	else
		print("✅ GameServer: " .. name .. " initialized")
		return true
	end
end

-- Recursively discover all ModuleScripts in a folder
local function discoverModules(folder: Instance, discovered: {ModuleScript})
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			table.insert(discovered, child)
		elseif child:IsA("Folder") then
			discoverModules(child, discovered)
		end
	end
end

-- Initialize Blaster System (Runs first, required for weapon infrastructure)
print(">> Initializing Blaster System...")
initializeSystem("BlasterSetup", function()
	local BlasterSetup = require(ServerScriptService.Blaster.setup)
	BlasterSetup.Initialize()
end)

-- Note: LightingSetup needs direct script permissions, so it must remain in GameLoop/
-- Discover all services
print(">> Discovering Services...")
local Services = ServerScriptService:WaitForChild("Services")
local serviceModules = {}
discoverModules(Services, serviceModules)

print(string.format(">> Found %d services", #serviceModules))

-- Load all services
print(">> Loading Services...")
local services = {}
for _, moduleScript in ipairs(serviceModules) do
	local success, service = pcall(function()
		return require(moduleScript)
	end)
	
	if success then
		table.insert(services, {
			name = moduleScript.Name,
			module = service,
			moduleScript = moduleScript
		})
		print("   Loaded: " .. moduleScript.Name)
	else
		warn("   Failed to load: " .. moduleScript.Name, service)
	end
end

-- Phase 1: Initialize (Init)
print(">> Phase 1: Initializing Services (Init)...") 
for _, serviceData in ipairs(services) do
	if serviceData.module.Init then
		initializeSystem(serviceData.name .. ".Init", function()
			serviceData.module.Init()
		end)
	end
end

-- Phase 2: Start
print(">> Phase 2: Starting Services (Start)...")
for _, serviceData in ipairs(services) do
	if serviceData.module.Start then
		-- Run in parallel so one service yielding doesn't block others
		task.spawn(function()
			initializeSystem(serviceData.name .. ".Start", function()
				serviceData.module.Start()
			end)
		end)
	end
end

print("-----------------------------------------")
print("       GAME LOOP FULLY STARTED           ")
print("-----------------------------------------")
