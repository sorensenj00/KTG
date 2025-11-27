local MetaConfig = {}

-- -- Economy Constants --

-- Biomass (Size/XP) lost on death (Percentage)
MetaConfig.DEATH_BIOMASS_LOSS_PCT = 0.8 -- Loses 80%
MetaConfig.DEATH_BIOMASS_CONVERSION_PCT = 0.2 -- Converts 20% to DNA

-- DNA (Currency)
MetaConfig.DNA_PER_KILL = 5 -- Flat DNA bonus per kill (optional small drip)

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

	-- New Idle/Passive Skills (Tier 1/2)
	Regeneration = {
		Name = "Regeneration",
		Description = "Heals X Health per second.",
		Tier = 1,
		BaseCost = 150,
		CostExponent = 1.5,
		Increment = 1, -- +1 HP/sec per level
		MaxLevel = 20,
	},
	Photosynthesis = {
		Name = "Photosynthesis",
		Description = "Automatically gain Biomass every second.",
		Tier = 1,
		BaseCost = 300,
		CostExponent = 1.8,
		Increment = 5, -- +5 Biomass/sec per level
		MaxLevel = 20,
	},
    Magnetism = {
        Name = "Magnetism",
        Description = "Increases range to automatically pick up loot.",
        Tier = 1,
        BaseCost = 250,
        CostExponent = 1.6,
        Increment = 2, -- +2 Studs range per level
        MaxLevel = 10,
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
	Thorns = {
		Name = "Thorns",
		Description = "Enemies take damage when they shoot you.",
		Tier = 2,
		BaseCost = 800,
		CostExponent = 1.8,
		Increment = 2, -- +2 Damage reflection per level
		MaxLevel = 10,
	},
    Featherweight = {
        Name = "Featherweight",
        Description = "Reduces fall damage.",
        Tier = 2,
        BaseCost = 500,
        CostExponent = 1.5,
        Increment = 0.1, -- 10% reduction per level
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
	ToxicAura = {
		Name = "Toxic Aura",
		Description = "Deals damage to nearby enemies every second.",
		Tier = 3,
		BaseCost = 2500,
		CostExponent = 2.1,
		Increment = 5, -- +5 DPS per level
		MaxLevel = 10,
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
-- Specific Getter for Non-Multiplier stats (Flat values like Regen, Thorns)
function MetaConfig.GetValue(stat: string, level: number): number
    local upgrade = MetaConfig.Upgrades[stat]
	if not upgrade then
		return 0
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
