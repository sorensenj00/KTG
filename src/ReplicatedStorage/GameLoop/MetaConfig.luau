local MetaConfig = {}

-- -- Economy Constants --

-- Biomass (Size/XP) lost on death (Percentage)
MetaConfig.DEATH_BIOMASS_LOSS_PCT = 0.8 -- Loses 80%
MetaConfig.DEATH_BIOMASS_CONVERSION_PCT = 0.2 -- Converts 20% to DNA

-- DNA (Currency)
MetaConfig.DNA_PER_KILL = 5 -- Flat DNA bonus per kill (optional small drip)

-- Import Mutation data from MutationConfig (for backward compatibility)
-- These are defined in MutationConfig but referenced from MetaConfig in some scripts
local MutationConfig = require(script.Parent.MutationConfig)
MetaConfig.RarityWeights = MutationConfig.RarityWeights
MetaConfig.Mutations = MutationConfig.Mutations
MetaConfig.ROLL_COST = MutationConfig.ROLL_COST
MetaConfig.REROLL_COST = MutationConfig.REROLL_COST

-- Define Tiers for UI Grouping and Unlocks
-- Unlocks are based on TOTAL LIFETIME DNA EARNED (or Biomass Harvested),
-- but for now we track "Lifetime DNA" or "Highest DNA" for tiers?
-- The user request says "Biomass is converted into DNA".
-- Tiers are likely based on "Total DNA Spent" or "Total DNA Earned".
-- For simplicity, we will use CURRENT DNA (Wallet) or LIFETIME DNA.
-- Let's assume LIFETIME DNA for Tiers to prevent de-leveling when spending.
-- Current code used 'Biomass' as the lifetime stat. We will rename 'Biomass' to 'LifetimeDNA' in logic,
-- but the config can just say "UnlockAmount".

MetaConfig.Tiers = {
	[1] = { Name = "Survivor", UnlockAmount = 0, Color = Color3.fromRGB(255, 255, 255) },
	[2] = { Name = "Hunter", UnlockAmount = 5000, Color = Color3.fromRGB(0, 255, 100) },
	[3] = { Name = "Apex", UnlockAmount = 25000, Color = Color3.fromRGB(255, 50, 50) },
	[4] = { Name = "Titan", UnlockAmount = 100000, Color = Color3.fromRGB(255, 215, 0) },
}

-- Add "Tier" property to every upgrade
-- REBALANCED: Higher base costs & exponents to crush inflation
-- NOTE: Common upgrades (Damage, Health, Speed, etc.) moved to MutationConfig as Common mutations
MetaConfig.Upgrades = {
	-- TIER 2 (Hunter) - Steep ramp up
	Ammo = {
		Name = "Ammo Reserves",
		Description = "Increases weapon magazine capacity by 5% per level.",
		Tier = 2,
		BaseCost = 1000, -- Up from 600
		CostExponent = 2.0, -- Up from 1.7 (harder to max out)
		Increment = 0.05,
		MaxLevel = 10,
	},
	JumpBoost = {
		Name = "Jump Boost",
		Description = "Increases jump height by 5% per level.",
		Tier = 2,
		BaseCost = 800, -- Up from 500
		CostExponent = 1.8, -- Up from 1.6
		Increment = 0.05,
		MaxLevel = 10,
	},
	FireRate = {
		Name = "Rapid Fire",
		Description = "Increases fire rate by 2% per level.",
		Tier = 2,
		BaseCost = 1200, -- Up from 800
		CostExponent = 2.0, -- Up from 1.8
		Increment = 0.02,
		MaxLevel = 15,
	},

	Featherweight = {
		Name = "Featherweight",
		Description = "Reduces fall damage.",
		Tier = 2,
		BaseCost = 800, -- Up from 500
		CostExponent = 1.7, -- Up from 1.5
		Increment = 0.1, -- 10% reduction per level
		MaxLevel = 10,
	},

	-- TIER 3 (Apex) - Luxury Items
	StartLevel = {
		Name = "Born Big",
		Description = "Start every life at Level 2 instead of Level 1.",
		Tier = 3,
		BaseCost = 25000, -- Up from 10000
		CostExponent = 2.5, -- Up from 2.2
		Increment = 1,
		MaxLevel = 1,
	},
	CritChance = {
		Name = "Critical Strike",
		Description = "1% chance to deal double damage per level.",
		Tier = 3,
		BaseCost = 5000, -- Up from 3000
		CostExponent = 2.2, -- Up from 2.0
		Increment = 0.01,
		MaxLevel = 20,
	},
	BulletSpeed = {
		Name = "Velocity",
		Description = "Increases projectile speed by 5% per level.",
		Tier = 3,
		BaseCost = 4000, -- Up from 2500
		CostExponent = 2.0, -- Up from 1.9
		Increment = 0.05,
		MaxLevel = 10,
	},

	-- TIER 4 (Titan) - End-game aspirations
	ExplosiveDeath = {
		Name = "Explosive Demise",
		Description = "Explode on death, dealing 50% max health damage per level.",
		Tier = 4,
		BaseCost = 40000, -- Up from 25000
		CostExponent = 2.7, -- Up from 2.5
		Increment = 0.5,
		MaxLevel = 5,
	},
	Greed = {
		Name = "Greed",
		Description = "1% chance to gain double GXP from kills per level.",
		Tier = 4,
		BaseCost = 50000, -- Up from 30000
		CostExponent = 3.0, -- Up from 2.8
		Increment = 0.01,
		MaxLevel = 10,
	},
}

-- Rarity-based mutation costs
local MutationCostByRarity = {
	[1] = { BaseCost = 100, CostExponent = 1.4 }, -- Common: 100, 264, 482, 741...
	[2] = { BaseCost = 250, CostExponent = 1.5 }, -- Uncommon: 250, 707, 1299...
	[3] = { BaseCost = 500, CostExponent = 1.6 }, -- Rare: 500, 1516, 2930...
	[4] = { BaseCost = 1000, CostExponent = 1.8 }, -- Legendary: 1000, 3482, 7225...
}

-- Merge Mutations into Upgrades with rarity-based pricing
for name, mutation in pairs(MutationConfig.Mutations) do
	local costConfig = MutationCostByRarity[mutation.Rarity] or MutationCostByRarity[1]
	MetaConfig.Upgrades[name] = {
		Name = name,
		Description = mutation.Description,
		Tier = mutation.Rarity,
		BaseCost = costConfig.BaseCost,
		CostExponent = costConfig.CostExponent,
		MaxLevel = mutation.MaxLevel,
		Increment = 0, -- Handled by GetStat
		IsMutation = true,
		GetStat = mutation.GetStat,
		ImageId = mutation.ImageId,
		Rarity = mutation.Rarity,
	}
end

-- Helper to check if player unlocks a specific upgrade
function MetaConfig.IsUnlocked(playerLifetimeDNA, upgradeKey)
	local upgrade = MetaConfig.Upgrades[upgradeKey]
	if not upgrade then
		return false
	end

	local tierData = MetaConfig.Tiers[upgrade.Tier]
	return playerLifetimeDNA >= tierData.UnlockAmount
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

	-- Target level is current + 1 (buying next level)
	local targetLevel = level + 1

	-- All upgrades/mutations use: BaseCost * (targetLevel ^ CostExponent)
	-- Rarity affects BaseCost and CostExponent for mutations
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
-- Specific Getter for Non-Multiplier stats (Flat values like Regen, Thorns)
function MetaConfig.GetValue(stat: string, level: number): number
	local upgrade = MetaConfig.Upgrades[stat]
	if not upgrade then
		return 0
	end

	if upgrade.GetStat then
		return upgrade.GetStat(level)
	end

	-- For flat values, it's usually Base + (Level * Increment) or just Level * Increment
	-- Based on the Increment logic above:
	return level * upgrade.Increment
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
