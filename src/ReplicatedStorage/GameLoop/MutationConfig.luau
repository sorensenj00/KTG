--[[
    Module: MutationConfig
    Description: Configuration for all Mutations, including Rarity, Stats, and Descriptions.

    Rarities:
    1: Common (White)
    2: Uncommon (Green)
    3: Rare (Purple)
    4: Legendary (Gold)

    Author: System
    Last Updated: 2025-01-20
]]

local MutationConfig = {}

MutationConfig.RarityColors = {
	[1] = Color3.fromRGB(255, 255, 255), -- Common
	[2] = Color3.fromRGB(50, 255, 50),   -- Uncommon
	[3] = Color3.fromRGB(180, 50, 255),  -- Rare
	[4] = Color3.fromRGB(255, 215, 0),   -- Legendary
}

MutationConfig.RarityWeights = {
    {Rarity = 1, Weight = 60},
    {Rarity = 2, Weight = 30},
    {Rarity = 3, Weight = 8},
    {Rarity = 4, Weight = 2},
}

MutationConfig.Mutations = {
    -- ⚪ Common (Base Stats)
    ["Sharp Claws"] = {
        Rarity = 1,
        MaxLevel = 50,
        Description = "Increases damage dealt by 1% per level.",
        ImageId = "rbxassetid://10468915",
        GetStat = function(level) return level * 0.01 end,
    },
    ["Thick Skin"] = {
        Rarity = 1,
        MaxLevel = 50,
        Description = "Increases max health by 1% per level.",
        ImageId = "rbxassetid://7169354151",
        GetStat = function(level) return level * 0.01 end,
    },
    ["Adrenaline"] = {
        Rarity = 1,
        MaxLevel = 20,
        Description = "Increases movement speed by 0.5% per level.",
        ImageId = "rbxassetid://1234752",
        GetStat = function(level) return level * 0.005 end,
    },
    ["Magnet Range"] = {
        Rarity = 1,
        MaxLevel = 10,
        Description = "Increases orb pickup range by 10% per level.",
        ImageId = "rbxassetid://7493638708",
        GetStat = function(level) return level * 0.1 end,
    },
    ["Health Regen"] = {
        Rarity = 1,
        MaxLevel = 5,
        Description = "Regenerates 1% max health per second per level.",
        ImageId = "rbxassetid://7169354151",
        GetStat = function(level) return level * 0.01 end,
    },
    ["Magnetism"] = {
        Rarity = 1,
        MaxLevel = 10,
        Description = "Increases range to automatically pick up loot (+2 studs per level).",
        ImageId = "rbxassetid://7493638708",
        GetStat = function(level) return level * 2 end,
    },

    -- ⚪ Common (Adaptation)
    ["Aerodynamics"] = {
        Rarity = 1,
        MaxLevel = 5,
        Description = "Reduces the Speed Penalty from size by 10% per level.",
        ImageId = "rbxassetid://1", -- Placeholder
        GetStat = function(level) return level * 0.1 end, -- 10% -> 50%
    },
    ["Dense Muscle"] = {
        Rarity = 1,
        MaxLevel = 5,
        Description = "+5% Max Health for every 100 Biomass you hold.",
        ImageId = "rbxassetid://2",
        GetStat = function(level) return level * 0.05 end, -- 5% -> 25%
    },
    ["Impact"] = {
        Rarity = 1,
        MaxLevel = 5,
        Description = "Your bullets get larger as you get larger (+0.1 stud radius base per level).",
        ImageId = "rbxassetid://3",
        GetStat = function(level) return level * 0.1 end,
    },
    ["Quick Step"] = {
        Rarity = 1,
        MaxLevel = 5,
        Description = "Increases base Sprint speed by 3% per level.",
        ImageId = "rbxassetid://4",
        GetStat = function(level) return level * 0.03 end,
    },

    -- 🟢 Uncommon (Utility)
    ["Heavy Steps"] = {
        Rarity = 2,
        MaxLevel = 1,
        Description = "If Scale > 3 (Size Lvl 3), walking damages enemies you touch.",
        ImageId = "rbxassetid://5",
        GetStat = function(level) return true end,
    },
    ["Gravitational Pull"] = {
        Rarity = 2,
        MaxLevel = 5,
        Description = "Orb Pickup Range scales with your Size (+20% per level).",
        ImageId = "rbxassetid://6",
        GetStat = function(level) return level * 0.2 end,
    },
    ["Shedding"] = {
        Rarity = 2,
        MaxLevel = 3,
        Description = "Taking damage drops Biomass but gives a speed boost for 3s.",
        ImageId = "rbxassetid://7",
        GetStat = function(level) return 0.2 + (level * 0.1) end, -- Speed Boost %
    },
    ["Iron Skin"] = {
        Rarity = 2,
        MaxLevel = 5,
        Description = "Flat Damage Reduction +1 per level.",
        ImageId = "rbxassetid://8",
        GetStat = function(level) return level * 1 end,
    },
    ["Photosynthesis"] = {
        Rarity = 2,
        MaxLevel = 20,
        Description = "Automatically gain Biomass every second.",
        ImageId = "rbxassetid://16", -- Placeholder
        GetStat = function(level) return level * 5 end, -- +5 Biomass/sec
    },
    ["Thorns"] = {
        Rarity = 2,
        MaxLevel = 10,
        Description = "Enemies take damage when they shoot you.",
        ImageId = "rbxassetid://17",
        GetStat = function(level) return level * 2 end, -- +2 Damage reflection
    },

    -- 🟣 Rare (Specialization)
    ["Momentum"] = {
        Rarity = 3,
        MaxLevel = 1,
        Description = "Uncapped Top Speed. Run straight for 3s to become a train.",
        ImageId = "rbxassetid://9",
        GetStat = function(level) return true end,
    },
    ["Orbitals"] = {
        Rarity = 3,
        MaxLevel = 3,
        Description = "Spawns floating spiked balls that circle you. Orbit radius scales with size.",
        ImageId = "rbxassetid://10",
        GetStat = function(level) return level end, -- Count: 1, 2, 3? Or always 2 and damage scales? Prompt says "2 floating balls". Let's say Level = Damage Mult? Or just unlock. Prompt says "As you get bigger, orbit gets wider". We'll stick to 2 balls.
    },
    ["Titan's Reach"] = {
        Rarity = 3,
        MaxLevel = 3,
        Description = "Melee/Interaction range increases by 50% per level.",
        ImageId = "rbxassetid://11",
        GetStat = function(level) return level * 0.5 end,
    },
    ["Giant Slayer"] = {
        Rarity = 3,
        MaxLevel = 5,
        Description = "Deal +15% Damage (per level) to enemies larger than you.",
        ImageId = "rbxassetid://12",
        GetStat = function(level) return level * 0.15 end,
    },
    ["Regeneration"] = {
        Rarity = 3,
        MaxLevel = 20,
        Description = "Heals X Health per second.",
        ImageId = "rbxassetid://18",
        GetStat = function(level) return level * 1 end, -- +1 HP/sec
    },
    ["Toxic Aura"] = {
        Rarity = 3,
        MaxLevel = 10,
        Description = "Deals damage to nearby enemies every second.",
        ImageId = "rbxassetid://11563251", -- Gas/Bomb
        GetStat = function(level) return level * 5 end, -- +5 DPS
    },

    -- 🟡 Legendary (Raid Boss)
    ["Supernova"] = {
        Rarity = 4,
        MaxLevel = 3,
        Description = "On death, explode dealing damage based on Total Biomass.",
        ImageId = "rbxassetid://13",
        GetStat = function(level) return level end, -- Multiplier
    },
    ["Earthquake"] = {
        Rarity = 4,
        MaxLevel = 1,
        Description = "Landing from a jump stuns nearby smaller enemies for 1s.",
        ImageId = "rbxassetid://14",
        GetStat = function(level) return true end,
    },
    ["Living Fortress"] = {
        Rarity = 4,
        MaxLevel = 1,
        Description = "Take 50% less damage from the front.",
        ImageId = "rbxassetid://15",
        GetStat = function(level) return 0.5 end,
    },
    ["Vampirism"] = {
        Rarity = 4,
        MaxLevel = 5,
        Description = "Heal for 5% of damage dealt per level.",
        ImageId = "rbxassetid://6238815272",
        GetStat = function(level) return level * 0.05 end,
    },
}

function MutationConfig.GetUpgradeCost(rarity, currentLevel)
    -- Scaling Cost: Base * TargetLevel (Linear)
    -- Matches MetaConfig.luau logic
    local base = 100
    local targetLevel = currentLevel + 1
    return math.floor(base * targetLevel)
end

MutationConfig.REROLL_COST = 250 -- Biomass per reroll
MutationConfig.ROLL_COST = 0 -- Initial roll is free (viewing shop)

return MutationConfig
