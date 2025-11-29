--[[
    Module: ScalingEngine
    Description: Handles resizing of character models (Players and Bots) based on Biomass/Scale.
    
    Dependencies:
    - ReplicatedStorage.GameLoop.ScalingConfig
    - ServerScriptService.Services.Progression.MetaProgressionService
    
    Author: System
    Last Updated: 2025-01-20
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local ScalingEngine = {}

-- Lazy load MetaProgressionManager to avoid circular dependency
local MetaManager = nil
local function getMeta()
	if not MetaManager then
		pcall(function()
			MetaManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
		end)
	end
	return MetaManager
end

function ScalingEngine.UpdateCharacter(character: Model, biomass: number)
	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart then
		return
	end

	-- 0. Ensure AutomaticScaling
	humanoid.AutomaticScalingEnabled = true

	-- 0.5. Sanitize HipHeight
	local baseHipHeight = character:GetAttribute("BaseHipHeight")
	if not baseHipHeight or baseHipHeight > 5 or baseHipHeight < 0.1 then
		baseHipHeight = 2.0
		character:SetAttribute("BaseHipHeight", baseHipHeight)
	end

	-- 1. Calculate Core Stats from Biomass
	-- First get level for stat calculations
	local level = 1
	if biomass > 0 then
		level = math.pow(biomass / ScalingConfig.BIOMASS_BASE_REQ, 1 / ScalingConfig.BIOMASS_EXPONENT)
		level = math.max(1, math.min(level, ScalingConfig.MAX_LEVEL))
	end
	
	-- Then get scale multiplier for visual scaling
	local scale = ScalingConfig.GetSizeMultiplier(level)
	
	-- print(string.format("[ScalingDebug] Char: %s, Biomass: %d, Level: %.2f, Scale: %.2f", character.Name, biomass, level, scale))
	
	local baseMaxHealth = ScalingConfig.GetMaxHealth(math.floor(level)) -- Use INTEGER LEVEL for health (step scaling)
	local baseWalkSpeed = ScalingConfig.GetWalkSpeed(level) -- Keep speed smooth or step? User said HP. Keeping speed smooth for now.

	-- 2. Apply Mutation Modifiers
	local healthMult = 1
	local speedFlatBonus = 0
	local speedPenaltyReduction = 0

	local player = Players:GetPlayerFromCharacter(character)
	if player and getMeta() then
		-- Dense Muscle: +5% Health per 100 Biomass
		local denseMuscleLevel = getMeta().GetStatValue(player, "Dense Muscle") -- Returns % per 100 biomass e.g. 0.05
		if denseMuscleLevel > 0 then
			local biomassChunks = math.floor(biomass / 100)
			healthMult = healthMult + (biomassChunks * denseMuscleLevel) -- e.g. 2 chunks * 0.05 = +10%
		end

		-- Quick Step: +% Base Speed
		local quickStepBonus = getMeta().GetStatValue(player, "Quick Step") -- Returns % e.g. 0.03
		if quickStepBonus > 0 then
			-- Apply to base 16 speed? Or final? Usually base.
			speedFlatBonus = ScalingConfig.BASE_WALKSPEED * quickStepBonus
		end

		-- Aerodynamics: Reduces speed penalty
		local aeroReduction = getMeta().GetStatValue(player, "Aerodynamics") -- Returns % e.g. 0.10
		if aeroReduction > 0 then
			speedPenaltyReduction = aeroReduction
		end
	end

	local finalMaxHealth = math.floor(baseMaxHealth * healthMult)

	-- Calculate Speed with Penalty Reduction
	-- Formula: Base / (Scale ^ 0.7)
	-- The penalty is (Base - ScaledBase). We reduce that difference.
	local rawScaledSpeed = ScalingConfig.GetWalkSpeed(level) -- This includes the floor
	local speedPenalty = ScalingConfig.BASE_WALKSPEED - rawScaledSpeed

	if speedPenaltyReduction > 0 then
		speedPenalty = speedPenalty * (1 - speedPenaltyReduction)
	end

	local finalWalkSpeed = ScalingConfig.BASE_WALKSPEED - speedPenalty + speedFlatBonus

	-- 3. Apply Visual Scale
	character:ScaleTo(scale)

	-- Store Scale Attribute for other scripts (e.g. Weapon Impact)
	character:SetAttribute("Scale", scale)

	-- 4. Apply Stats
	local oldMaxHealth = humanoid.MaxHealth
	humanoid.MaxHealth = finalMaxHealth
	
	-- Proportional Health Scaling
	if oldMaxHealth > 0 and oldMaxHealth ~= finalMaxHealth then
		local healthRatio = humanoid.Health / oldMaxHealth
		humanoid.Health = finalMaxHealth * healthRatio
	else
		humanoid.Health = finalMaxHealth
	end
	
	humanoid.WalkSpeed = finalWalkSpeed

	-- Jump Height Scaling (Linear with Scale to look normal)
	local baseJumpHeight = 7.2
	humanoid.UseJumpPower = false
	humanoid.JumpHeight = baseJumpHeight * scale

	-- 5. Star Mode Visuals (Max Scale)
	if scale >= ScalingConfig.MAX_SIZE_CAP then
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
			aura.Size = NumberSequence.new(0.5 * scale)
			aura.Texture = "rbxassetid://243098098"
			aura.EmissionDirection = Enum.NormalId.Top
			aura.Lifetime = NumberRange.new(0.5, 1)
			aura.Rate = 20
			aura.Speed = NumberRange.new(2, 5)
			aura.Parent = rootPart
		end
	end
end

-- Alias for compatibility if needed (but we should call UpdateCharacter)
function ScalingEngine.ResizeCharacter(character, level)
	-- Deprecated: Use UpdateCharacter with Biomass
	-- Try to fetch biomass from character
	local biomass = character:GetAttribute("Biomass") or 0
	ScalingEngine.UpdateCharacter(character, biomass)
end

return ScalingEngine
