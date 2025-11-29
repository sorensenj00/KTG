--[[
    Client Entry Point
    Description: Automatically discovers and initializes all controllers using a two-phase pattern.
    Phase 1 (Init): Internal setup without dependencies
    Phase 2 (Start): Event listening and inter-controller communication
    
    Author: Refactored
    Last Updated: 2025-11-29
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local Controllers = script.Parent:WaitForChild("Controllers")

print("-----------------------------------------")
print("    INITIALIZING CLIENT CONTROLLERS      ")
print("-----------------------------------------")

-- Helper function to safely initialize a controller
local function initializeController(name: string, initFunc: () -> ())
	local success, err = pcall(initFunc)
	if not success then
		warn("❌ GameClient: Failed to initialize " .. name .. ":", err)
		return false
	else
		print("✅ GameClient: " .. name .. " initialized")
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

-- Discover all ModuleScripts in Controllers folder
print(">> Discovering Controllers...")
local controllerModules = {}
discoverModules(Controllers, controllerModules)

print(string.format(">> Found %d controllers", #controllerModules))

-- Load all controllers
print(">> Loading Controllers...")
local controllers = {}
for _, moduleScript in ipairs(controllerModules) do
	local success, controller = pcall(function()
		return require(moduleScript)
	end)
	
	if success then
		table.insert(controllers, {
			name = moduleScript.Name,
			module = controller,
			moduleScript = moduleScript
		})
		print("   Loaded: " .. moduleScript.Name)
	else
		warn("   Failed to load: " .. moduleScript.Name, controller)
	end
end

-- Phase 1: Initialize (Init)
print(">> Phase 1: Initializing Controllers (Init)...")
for _, controllerData in ipairs(controllers) do
	if controllerData.module.Init then
		initializeController(controllerData.name .. ".Init", function()
			controllerData.module.Init()
		end)
	end
end

-- Phase 2: Start
print(">> Phase 2: Starting Controllers (Start)...")
for _, controllerData in ipairs(controllers) do
	if controllerData.module.Start then
		-- Run in parallel so one controller yielding doesn't block others
		task.spawn(function()
			initializeController(controllerData.name .. ".Start", function()
				controllerData.module.Start()
			end)
		end)
	end
end

print("-----------------------------------------")
print("    CLIENT CONTROLLERS FULLY STARTED     ")
print("-----------------------------------------")

-- Signal Loading Screen to fade out
player:SetAttribute("GameLoaded", true)
