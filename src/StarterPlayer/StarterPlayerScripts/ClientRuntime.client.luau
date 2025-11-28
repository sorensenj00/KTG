local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")
local Controllers = StarterPlayerScripts:WaitForChild("Controllers")

local BlasterController = require(Controllers:WaitForChild("BlasterController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))

-- Initialize Controllers
print("🚀 ClientRuntime: Starting Controllers...")

task.spawn(function()
	CameraController.Start()
end)

task.spawn(function()
	BlasterController.Start()
end)

print("✅ ClientRuntime: Controllers Started")
