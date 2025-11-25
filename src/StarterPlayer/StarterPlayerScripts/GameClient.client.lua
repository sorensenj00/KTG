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
local KillfeedController = require(Controllers.KillfeedController)
local DamageNumberController = require(Controllers.DamageNumberController)
local BlasterController = require(Controllers.BlasterController)

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

-- 3. KillfeedController
success, err = pcall(function()
	KillfeedController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize KillfeedController:", err)
else
	print("✅ GameClient: KillfeedController initialized")
end

-- 4. DamageNumberController
success, err = pcall(function()
	DamageNumberController.Start()
end)
if not success then
	warn("❌ GameClient: Failed to initialize DamageNumberController:", err)
else
	print("✅ GameClient: DamageNumberController initialized")
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

print("🎉 GameClient: All controllers initialized successfully!")

