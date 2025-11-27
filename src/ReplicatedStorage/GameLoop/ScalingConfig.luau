local ScalingConfig = {}

-- System Settings
ScalingConfig.UPDATE_INTERVAL = 5 -- Checks and updates size/speed every 5 seconds

-- Level Constants
ScalingConfig.MAX_LEVEL = 30
-- Renaming XP to Biomass for clarity in usage, though math is same
ScalingConfig.BIOMASS_BASE_REQ = 150
ScalingConfig.BIOMASS_EXPONENT = 2.2

-- Kill Rewards
ScalingConfig.KILL_BASE_REWARD = 50
ScalingConfig.KILL_REWARD_MULTIPLIER = 150

-- Health
ScalingConfig.HEALTH_BASE = 100
ScalingConfig.HEALTH_EXPONENT = 2.5

-- Size (0.75 to 12.0)
ScalingConfig.MIN_SIZE = 0.75
ScalingConfig.MAX_SIZE = 12.0
ScalingConfig.GROWTH_EXPONENT = 3.0

-- Speed Constants
-- Level 1: Very Fast (120) - Agile, hard to hit
-- Level 30: Heavy (50) - Slower relative to size, but still covers distance
ScalingConfig.SPEED_AT_LEVEL_1 = 120
ScalingConfig.SPEED_AT_LEVEL_30 = 50

-- Visuals
ScalingConfig.STAR_MODE_COLOR = Color3.fromRGB(255, 170, 0)
ScalingConfig.STAR_MODE_MATERIAL = Enum.Material.Neon

-- Zones
ScalingConfig.SAFE_ZONE_MAX_LEVEL = 5

-- Formulas

function ScalingConfig.GetXPRequired(level: number): number
	return math.floor(ScalingConfig.BIOMASS_BASE_REQ * math.pow(level, ScalingConfig.BIOMASS_EXPONENT))
end

function ScalingConfig.GetXPReward(victimLevel: number): number
	local levelBonus = (victimLevel * ScalingConfig.KILL_REWARD_MULTIPLIER)
	if victimLevel > 20 then
		levelBonus = levelBonus * 1.5
	end
	return math.floor(ScalingConfig.KILL_BASE_REWARD + levelBonus)
end

function ScalingConfig.GetSizeMultiplier(level: number): number
	local progress = math.clamp((level - 1) / (ScalingConfig.MAX_LEVEL - 1), 0, 1)
	-- EaseOutQuad: fast early growth, slower late growth
	local easedProgress = 1 - (1 - progress) * (1 - progress)
	return ScalingConfig.MIN_SIZE + (easedProgress * (ScalingConfig.MAX_SIZE - ScalingConfig.MIN_SIZE))
end

function ScalingConfig.GetWalkSpeed(level: number): number
	local progress = math.clamp((level - 1) / (ScalingConfig.MAX_LEVEL - 1), 0, 1)

	-- Linearly interpolate from 120 down to 85
	-- Level 1 = 120
	-- Level 30 = 85
	return ScalingConfig.SPEED_AT_LEVEL_1
		+ (progress * (ScalingConfig.SPEED_AT_LEVEL_30 - ScalingConfig.SPEED_AT_LEVEL_1))
end

function ScalingConfig.GetMaxHealth(level: number): number
	local growth = math.pow(level, ScalingConfig.HEALTH_EXPONENT)
	return math.floor(ScalingConfig.HEALTH_BASE + (growth * 10))
end

return ScalingConfig
