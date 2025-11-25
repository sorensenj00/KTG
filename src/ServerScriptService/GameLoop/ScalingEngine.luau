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

	-- 2. Scale Humanoid (R15 Standard Method)
	-- We create the NumberValues if they are missing (fixing custom bot templates)
	local scaleValues = {
		"BodyHeightScale",
		"BodyWidthScale",
		"BodyDepthScale",
		"HeadScale",
	}

	for _, scaleName in ipairs(scaleValues) do
		local val = humanoid:FindFirstChild(scaleName)

		if not val then
			val = Instance.new("NumberValue")
			val.Name = scaleName
			val.Parent = humanoid
		end

		if val:IsA("NumberValue") then
			val.Value = sizeMultiplier
		end
	end

	-- 3. Apply scaled HipHeight using sanitized BaseHipHeight
	humanoid.HipHeight = baseHipHeight * sizeMultiplier

	-- 4. Stats Application
	humanoid.MaxHealth = finalMaxHealth
	-- Heal up if this is their first spawn/scale (Level 1 check heuristic)
	if humanoid.Health > finalMaxHealth or (humanoid.Health < finalMaxHealth and level <= 1) then
		humanoid.Health = finalMaxHealth
	end
	humanoid.WalkSpeed = finalWalkSpeed

	-- 5. Scale Tools (Visual Only)
	for _, tool in ipairs(character:GetChildren()) do
		if tool:IsA("Tool") then
			local handle = tool:FindFirstChild("Handle")
			if handle then
				if not tool:GetAttribute("BaseSize") then
					tool:SetAttribute("BaseSize", handle.Size)
				end
				handle.Size = tool:GetAttribute("BaseSize") * sizeMultiplier
			end
		end
	end

	-- 6. Star Mode Visuals (Titan Level)
	if level >= ScalingConfig.MAX_LEVEL then
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
