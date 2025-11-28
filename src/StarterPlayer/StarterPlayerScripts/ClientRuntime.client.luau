local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local Controllers = StarterPlayerScripts:WaitForChild("Controllers")

local BlasterController = require(Controllers:WaitForChild("BlasterController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local MutationHUDController = require(Controllers:WaitForChild("MutationHUDController"))
local MutationShopController = require(Controllers:WaitForChild("MutationShopController"))

-- Initialize Controllers
print("🚀 ClientRuntime: Starting Controllers...")

task.spawn(function()
	CameraController.Start()
end)

task.spawn(function()
	BlasterController.Start()
end)

task.spawn(function()
	MutationHUDController.Start()
end)

task.spawn(function()
	MutationShopController.Start()
end)

print("✅ ClientRuntime: Controllers Started")
