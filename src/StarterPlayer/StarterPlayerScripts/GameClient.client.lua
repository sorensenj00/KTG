--[[
    Bootstrapper: GameClient
    Description: Central bootstrapper that initializes all client-side controllers in the proper order.
    Handles initialization errors gracefully and prints status for debugging.
    
    Dependencies:
    - Controllers.CameraController
    - Controllers.UIController
    - Controllers.KillfeedController
    - Controllers.DamageNumberController
    - Controllers.BlasterController
    
    Author: System
    Last Updated: 2025-01-20
]]

local Controllers = script.Parent:WaitForChild("Controllers")

local CameraController = require(Controllers.CameraController)
local UIController = require(Controllers.UIController)
-- local KillfeedController = require(Controllers.KillfeedController)
local DamageNumberController = require(Controllers.DamageNumberController)
local DamageEffectController = require(Controllers.DamageEffectController)
local BlasterController = require(Controllers.BlasterController)
local BeaconController = require(Controllers.BeaconController)
local LeaderboardController = require(Controllers.LeaderboardController)
local IKController = require(Controllers.IKController)

-- Initialize controllers in proper order
print("🚀 GameClient: Starting initialization...")

-- 1. CameraController (needed by BlasterController)
local success, err = pcall(function()
	CameraController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize CameraController:", err)
else
	print("✅ GameClient: CameraController initialized")
end

-- 2. UIController
success, err = pcall(function()
	UIController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize UIController:", err)
else
	print("✅ GameClient: UIController initialized")
end

-- 3. KillfeedController (Removed - using StarterGui version)
-- success, err = pcall(function()
-- 	KillfeedController.Start()
-- end)
-- if not success then
-- 	warn("❌ GameClient: Failed to initialize KillfeedController:", err)
-- else
-- 	print("✅ GameClient: KillfeedController initialized")
-- end

-- 4. DamageNumberController
success, err = pcall(function()
	DamageNumberController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize DamageNumberController:", err)
else
	print("✅ GameClient: DamageNumberController initialized")
end

-- 4.5. DamageEffectController
success, err = pcall(function()
	DamageEffectController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize DamageEffectController:", err)
else
	print("✅ GameClient: DamageEffectController initialized")
end

-- 5. BlasterController (depends on CameraController)
success, err = pcall(function()
	BlasterController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize BlasterController:", err)
else
	print("✅ GameClient: BlasterController initialized")
end

-- 6. BeaconController
success, err = pcall(function()
	BeaconController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize BeaconController:", err)
else
	print("✅ GameClient: BeaconController initialized")
end

-- 7. LeaderboardController
success, err = pcall(function()
	LeaderboardController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize LeaderboardController:", err)
else
	print("✅ GameClient: LeaderboardController initialized")
end

-- 8. IKController
success, err = pcall(function()
	IKController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize IKController:", err)
else
	print("✅ GameClient: IKController initialized")
end

print("🎉 GameClient: All controllers initialized successfully!")

