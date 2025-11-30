local ScalingConfig = {}

-- System Settings
ScalingConfig.UPDATE_INTERVAL = 2 -- Update more frequently to catch stage transitions

-- Level Constants
ScalingConfig.MAX_LEVEL = 50
ScalingConfig.XP_BASE_REQ = 100
ScalingConfig.XP_EXPONENT = 2.1 -- Slightly easier leveling to reach mid-game
-- Renaming XP to Biomass for clarity in usage, though math is same
ScalingConfig.BIOMASS_BASE_REQ = 150
ScalingConfig.BIOMASS_EXPONENT = 2.2

-- Kill Rewards
ScalingConfig.KILL_BASE_REWARD = 50
ScalingConfig.KILL_REWARD_MULTIPLIER = 50

-- Health Constants (Geometric Progression)
-- Goal: Lvl 1 = 50, Lvl 15 = ~250, Lvl 30 = 1500
ScalingConfig.HEALTH_BASE = 45
ScalingConfig.HEALTH_GROWTH_FACTOR = 1.125 

-- Speed Constants
ScalingConfig.SPEED_AT_LEVEL_1 = 120 -- Very Fast (Mouse) - Updated to 100 per request
ScalingConfig.SPEED_AT_LEVEL_30 = 40 -- Very Slow (Titan)
ScalingConfig.BASE_WALKSPEED = 16 -- Base Roblox humanoid walk speed
-- Health
ScalingConfig.HEALTH_BASE = 100
ScalingConfig.HEALTH_EXPONENT = 2.5

-- Size (0.75 to 12.0)
-- Visuals
ScalingConfig.STAR_MODE_COLOR = Color3.fromRGB(255, 50, 50) -- Red for Titan Boss
ScalingConfig.STAR_MODE_MATERIAL = Enum.Material.Neon

-- Zones
ScalingConfig.SAFE_ZONE_MAX_LEVEL = 5

-- Size Limits (Used by Camera Controllers)
ScalingConfig.MIN_SIZE = 0.75
ScalingConfig.MAX_SIZE = 50.0
ScalingConfig.MAX_SIZE_CAP = 50.0 -- Threshold for "Star Mode" / Titan visuals



-- Formulas

function ScalingConfig.GetXPRequired(level: number): number
	return math.floor(ScalingConfig.BIOMASS_BASE_REQ * math.pow(level, ScalingConfig.BIOMASS_EXPONENT))
end

function ScalingConfig.GetXPReward(victimLevel: number): number
	local levelBonus = (victimLevel * ScalingConfig.KILL_REWARD_MULTIPLIER)
	if victimLevel >= 20 then
		levelBonus = levelBonus * 2.0 -- Big reward for killing bosses
	end
	return math.floor(ScalingConfig.KILL_BASE_REWARD + levelBonus)
end

function ScalingConfig.GetSizeMultiplier(level: number): number
	-- Continuous Scaling: Linear from 0.75 (Lvl 1) to 50.0 (Lvl 30)
	-- Range: 49.25 spread over 29 levels
	-- Increment: ~1.7 per level
	
	local t = math.clamp((level - 1) / (ScalingConfig.MAX_LEVEL - 1), 0, 1)
	return ScalingConfig.MIN_SIZE + t * (ScalingConfig.MAX_SIZE - ScalingConfig.MIN_SIZE)
end

function ScalingConfig.GetWalkSpeed(level: number): number
	-- Continuous Scaling: Inverse Decay
	-- Level 1: 100 * (10/10) = 100
	-- Level 10: 100 * (10/19) = ~52
	-- Level 30: 100 * (10/39) = ~25
	return 100 * (10 / (9 + level))
end

function ScalingConfig.GetMaxHealth(level: number): number
	-- Continuous Scaling: High Exponential
	-- Level 1: 50
	-- Level 30: 50 * (1.33 ^ 29) = ~196,000
	local health = 50 * math.pow(1.33, level - 1)
	
	-- Round to nearest 10
	return math.floor(health / 10 + 0.5) * 10
end

function ScalingConfig.GetDamageMultiplier(level: number): number
	-- Continuous Scaling: Linear Aggression
	-- Level 1: 1.0x
	-- Level 30: 1.0 + (29 * 0.83) = ~25.07x
	return 1.0 + (level - 1) * 0.83
end

function ScalingConfig.GetScale(biomass: number): number
	-- Convert Biomass to Scale/Level
	-- This is the inverse of GetXPRequired
	-- We need to solve: biomass = BIOMASS_BASE_REQ * (level ^ BIOMASS_EXPONENT)
	-- Therefore: level = (biomass / BIOMASS_BASE_REQ) ^ (1 / BIOMASS_EXPONENT)
	
	if biomass <= 0 then
		return ScalingConfig.GetSizeMultiplier(1)
	end
	
	local level = math.pow(biomass / ScalingConfig.BIOMASS_BASE_REQ, 1 / ScalingConfig.BIOMASS_EXPONENT)
	level = math.max(1, math.min(level, ScalingConfig.MAX_LEVEL))
	
	-- Return the size multiplier for this level
	return ScalingConfig.GetSizeMultiplier(level)
end

return ScalingConfig
