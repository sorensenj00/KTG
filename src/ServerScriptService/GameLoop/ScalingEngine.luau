--[[
    Module: ScalingEngine
    Description: Handles resizing of character models (Players and Bots) based on level.
    
    Dependencies:
    - ReplicatedStorage.GameLoop.ScalingConfig
    - ServerScriptService.GameLoop.MetaProgressionManager
    
    Author: System
    Last Updated: 2025-01-20
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local ScalingEngine = {}

-- Lazy load MetaProgressionManager
local MetaManager = nil
local function getMeta()
	if not MetaManager then
		pcall(function()
			MetaManager = require(ServerScriptService.GameLoop.MetaProgressionManager)
		end)
	end
	return MetaManager
end

function ScalingEngine.ResizeCharacter(character: Model, level: number)
	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return
	end

	-- 0. CRITICAL FIX: Ensure AutomaticScaling is enabled
	-- This forces Roblox to handle the joint offsets and physics when we change the scale values
	humanoid.AutomaticScalingEnabled = true

	-- 0.5. Sanitize BaseHipHeight Attribute
	-- Fix corrupted BaseHipHeight values from previous sessions (e.g., ~1050)
	local baseHipHeight = character:GetAttribute("BaseHipHeight")
	local isCorrupted = false

	if baseHipHeight then
		-- Check if value is corrupted (>5 or <0.1)
		if baseHipHeight > 5 or baseHipHeight < 0.1 then
			isCorrupted = true
		end
	else
		-- Attribute doesn't exist, use current HipHeight if valid
		local currentHip = humanoid.HipHeight
		if currentHip > 0.1 and currentHip <= 5 then
			baseHipHeight = currentHip
		else
			isCorrupted = true
		end
	end

	-- Reset to standard R15 value if corrupted or missing
	if isCorrupted or not baseHipHeight then
		baseHipHeight = 2.0 -- Standard R15 height
	end

	-- Always update the attribute with the sanitized value
	character:SetAttribute("BaseHipHeight", baseHipHeight)

	-- 1. Calculate Stats
	local sizeMultiplier = ScalingConfig.GetSizeMultiplier(level)
	local baseMaxHealth = ScalingConfig.GetMaxHealth(level)
	local baseWalkSpeed = ScalingConfig.GetWalkSpeed(level)

	-- Apply Meta Multipliers
	local healthMult = 1
	local speedMult = 1

	local player = Players:GetPlayerFromCharacter(character)
	if player and getMeta() then
		healthMult = MetaManager.GetStatMultiplier(player, "Health")
		speedMult = MetaManager.GetStatMultiplier(player, "Speed")
	end

	local finalMaxHealth = baseMaxHealth * healthMult
	local finalWalkSpeed = baseWalkSpeed * speedMult

	-- [FIX] Scale JumpPower/JumpHeight proportional to size
	-- Default JumpPower is 50, JumpHeight is 7.2.
	-- We scale it by sqrt(size) to make it feel weighty but functional, or linear?
	-- Physics: To jump X times higher (relative to body), we need linear scaling if gravity is constant.
	-- Since sizeMultiplier affects leg length, we want to jump relative to that.
	-- Let's use linear scaling for now so a 10x giant jumps 10x high (which looks "normal" for their size).
	local baseJumpHeight = 7.2
	local finalJumpHeight = baseJumpHeight * sizeMultiplier

	-- 2. Scale Character Uniformly
	-- We use ScaleTo which handles all parts, attachments, joints, and Humanoid properties (HipHeight) automatically.
	-- This ensures the model is scaled uniformly without distortion.
	character:ScaleTo(sizeMultiplier)

	-- 3. Stats Application
	-- 3. Stats Application
	local oldMaxHealth = humanoid.MaxHealth
	humanoid.MaxHealth = finalMaxHealth
	
	-- Proportional Health Scaling
	if oldMaxHealth > 0 and oldMaxHealth ~= finalMaxHealth then
		local healthRatio = humanoid.Health / oldMaxHealth
		humanoid.Health = finalMaxHealth * healthRatio
	else
		-- Initial spawn or invalid state, heal to full
		humanoid.Health = finalMaxHealth
	end
	
	humanoid.WalkSpeed = finalWalkSpeed

	-- Use JumpHeight if available (newer Roblox standard), falling back to Power if needed.
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = finalJumpHeight

	-- 6. Star Mode Visuals (Titan Level)
	if math.floor(level) >= ScalingConfig.MAX_LEVEL then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("BasePart") and child.Name ~= "HumanoidRootPart" then
				child.Color = ScalingConfig.STAR_MODE_COLOR
				child.Material = ScalingConfig.STAR_MODE_MATERIAL
				child.Transparency = 0
			end
		end

		if not rootPart:FindFirstChild("TitanAura") then
			local aura = Instance.new("ParticleEmitter")
			aura.Name = "TitanAura"
			aura.Color = ColorSequence.new(ScalingConfig.STAR_MODE_COLOR)
			aura.Size = NumberSequence.new(0.5 * sizeMultiplier)
			aura.Texture = "rbxassetid://243098098"
			aura.EmissionDirection = Enum.NormalId.Top
			aura.Lifetime = NumberRange.new(0.5, 1)
			aura.Rate = 20
			aura.Speed = NumberRange.new(2, 5)
			aura.Parent = rootPart
		end
	end
end

return ScalingEngine
