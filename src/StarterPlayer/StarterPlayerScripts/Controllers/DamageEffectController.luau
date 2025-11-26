--[[
    Controller: DamageEffectController
    Description: Handles visual feedback when the player takes damage (red vignette flash).
    
    Dependencies:
    - Players (Roblox Service)
    - TweenService (Roblox Service)
    
    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DamageEffectController = {}

-- Constants
local VIGNETTE_IMAGE = "rbxassetid://6035286767" -- Generic vignette texture
local FLASH_DURATION = 0.5
local MAX_TRANSPARENCY = 0.5 -- How visible the red vignette gets (0 = solid, 1 = invisible)

-- State
local vignetteFrame = nil
local lastHealth = 100

local function createVignette()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DamageEffectGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 0 -- Behind HUD
	screenGui.Parent = playerGui

	local frame = Instance.new("ImageLabel")
	frame.Name = "Vignette"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Image = VIGNETTE_IMAGE
	frame.ImageColor3 = Color3.fromRGB(255, 0, 0)
	frame.ImageTransparency = 1 -- Start invisible
	frame.Parent = screenGui
	
	return frame
end

local function onHealthChanged(health)
	if not vignetteFrame then return end
	
	-- Only flash on damage (health decrease)
	if health < lastHealth then
		local damage = lastHealth - health
		
		-- Calculate intensity based on damage amount (clamped)
		local intensity = math.clamp(damage / 50, 0.2, 0.8)
		local targetTransparency = 1 - (intensity * (1 - MAX_TRANSPARENCY))
		
		-- Flash red
		vignetteFrame.ImageTransparency = targetTransparency
		
		-- Tween back to invisible
		local tweenInfo = TweenInfo.new(FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(vignetteFrame, tweenInfo, { ImageTransparency = 1 })
		tween:Play()
	end
	
	lastHealth = health
end

function DamageEffectController.Start()
	print("🩸 DamageEffectController: Starting...")
	
	vignetteFrame = createVignette()
	
	local function connectCharacter(char)
		local humanoid = char:WaitForChild("Humanoid", 10)
		if humanoid then
			lastHealth = humanoid.Health
			humanoid.HealthChanged:Connect(onHealthChanged)
		end
	end
	
	if player.Character then
		connectCharacter(player.Character)
	end
	
	player.CharacterAdded:Connect(connectCharacter)
	
	print("✅ DamageEffectController: Initialized")
end

return DamageEffectController
