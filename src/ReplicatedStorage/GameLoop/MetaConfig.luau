local MetaConfig = {}

-- Global XP earned per kill when player dies
MetaConfig.GXP_PER_KILL = 10

-- Session XP to Global XP conversion ratio (e.g., 100 Session XP = 50 GXP)
-- User Requirement: 20% conversion ratio.
MetaConfig.SESSION_XP_TO_GXP_RATIO = 0.2

-- Define Tiers for UI Grouping and Unlocks
MetaConfig.Tiers = {
	[1] = { Name = "Survivor", UnlockBiomass = 0, Color = Color3.fromRGB(255, 255, 255) },
	[2] = { Name = "Hunter", UnlockBiomass = 5000, Color = Color3.fromRGB(0, 255, 100) },
	[3] = { Name = "Apex", UnlockBiomass = 25000, Color = Color3.fromRGB(255, 50, 50) },
	[4] = { Name = "Titan", UnlockBiomass = 100000, Color = Color3.fromRGB(255, 215, 0) },
}

-- Add "Tier" property to every upgrade
MetaConfig.Upgrades = {
	-- TIER 1 (Survivor)
	Damage = {
		Name = "Sharp Claws",
		Description = "Increases damage dealt by 1% per level.",
		Tier = 1,
		BaseCost = 100,
		CostExponent = 1.5,
		Increment = 0.01,
		MaxLevel = 50,
	},
	Health = {
		Name = "Thick Skin",
		Description = "Increases max health by 1% per level.",
		Tier = 1,
		BaseCost = 100,
		CostExponent = 1.5,
		Increment = 0.01,
		MaxLevel = 50,
	},
	Speed = {
		Name = "Adrenaline",
		Description = "Increases movement speed by 0.5% per level.",
		Tier = 1,
		BaseCost = 200,
		CostExponent = 1.6,
		Increment = 0.005,
		MaxLevel = 20,
	},

	-- TIER 2 (Hunter)
	Ammo = {
		Name = "Ammo Reserves",
		Description = "Increases weapon magazine capacity by 5% per level.",
		Tier = 2,
		BaseCost = 600,
		CostExponent = 1.7,
		Increment = 0.05,
		MaxLevel = 10,
	},

	-- TIER 3 (Apex)
	Vampirism = {
		Name = "Vampirism",
		Description = "Heal for 5% of damage dealt per level.",
		Tier = 3,
		BaseCost = 2000,
		CostExponent = 2.0,
		Increment = 0.05,
		MaxLevel = 5,
	},
	StartLevel = {
		Name = "Born Big",
		Description = "Start every life at Level 2 instead of Level 1.",
		Tier = 3,
		BaseCost = 5000,
		CostExponent = 2.0,
		Increment = 1,
		MaxLevel = 1,
	},

	-- TIER 4 (Titan)
	ExplosiveDeath = {
		Name = "Explosive Demise",
		Description = "Explode on death, dealing 50% max health damage per level.",
		Tier = 4,
		BaseCost = 10000,
		CostExponent = 2.2,
		Increment = 0.5,
		MaxLevel = 5,
	},
}

-- Helper to check if player unlocks a specific upgrade
function MetaConfig.IsUnlocked(playerBiomass, upgradeKey)
	local upgrade = MetaConfig.Upgrades[upgradeKey]
	if not upgrade then
		return false
	end

	local tierData = MetaConfig.Tiers[upgrade.Tier]
	return playerBiomass >= tierData.UnlockBiomass
end

-- Calculate the cost for a specific upgrade at a given level
function MetaConfig.GetCost(stat: string, level: number): number
	local upgrade = MetaConfig.Upgrades[stat]
	if not upgrade then
		warn("MetaConfig: Invalid stat name:", stat)
		return math.huge
	end

	-- Check if at max level
	if level >= upgrade.MaxLevel then
		return math.huge
	end

	-- Polynomial cost: BaseCost * (level ^ CostExponent)
	-- Note: level 0 -> cost 0 (technically), but we usually buy level 1.
	-- If level is 0 (first purchase), we treat it as buying level 1.
	local targetLevel = level + 1
	return math.floor(upgrade.BaseCost * (targetLevel ^ upgrade.CostExponent))
end

-- Calculate the multiplier for a specific upgrade at a given level
function MetaConfig.GetMultiplier(stat: string, level: number): number
	local upgrade = MetaConfig.Upgrades[stat]
	if not upgrade then
		warn("MetaConfig: Invalid stat name:", stat)
		return 1
	end

	-- Linear multiplier: 1 + (level * Increment)
	-- Example: Level 10 with Increment 0.01 = 1 + (10 * 0.01) = 1.1 = 10% boost
	return 1 + (level * upgrade.Increment)
end

-- Get the full upgrade config (for validation purposes)
function MetaConfig.GetUpgradeConfig(statName: string)
	local upgrade = MetaConfig.Upgrades[statName]
	if not upgrade then
		return nil, nil
	end
	return upgrade, upgrade.Tier
end

return MetaConfig
