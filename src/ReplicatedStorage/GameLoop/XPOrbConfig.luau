--[[
    Config: XPOrbConfig
    Description: Shared configuration and strict types for XP Orbs.
    Author: System
    Last Updated: 2025-01-20
]]

local XPOrbConfig = {}

--[[
    -------------------------------------------------------------------------
    CONSTANTS
    -------------------------------------------------------------------------
]]

XPOrbConfig.SPAWN_INTERVAL = 1
XPOrbConfig.ORB_LIFETIME = 60
XPOrbConfig.MAX_LIFETIME = 240 -- 4 Minutes Auto-Despawn
XPOrbConfig.ORB_GROWTH_INTERVAL = 10
XPOrbConfig.MAX_GROWTH_STAGES = 5
XPOrbConfig.MAX_ORBS = 100

-- Growth Scaling
XPOrbConfig.GROWTH_SIZE_MULTIPLIER = 1.5 -- 50% size increase per stage
XPOrbConfig.GROWTH_XP_MULTIPLIER = 1.5 -- 50% XP increase per stage

-- Magnetism
XPOrbConfig.MAGNET_RADIUS = 50 -- Reduced from 100 to 50 to match Client
XPOrbConfig.MIN_MAGNET_SPEED = 10
XPOrbConfig.MAX_MAGNET_SPEED = 80

-- Collection
XPOrbConfig.BASE_COLLECTION_RANGE = 30
XPOrbConfig.SCALE_FACTOR = 5 -- +5 studs per 1.0 scale
XPOrbConfig.MAGNET_TOLERANCE = 20

-- Visuals
XPOrbConfig.POOL_SIZE = 50
XPOrbConfig.FLOAT_AMPLITUDE = 1.5
XPOrbConfig.FLOAT_SPEED = 2

--[[
    -------------------------------------------------------------------------
    TYPES
    -------------------------------------------------------------------------
]]

export type OrbTier = {
    Name: string,
    XP: number,
    Size: Vector3,
    Color: Color3,
    Chance: number,
}

export type OrbData = {
    Id: number,
    Position: Vector3,
    Tier: OrbTier,
    CurrentSize: Vector3,
    XP: number,
    SpawnTime: number,
    GrowthStage: number,
    MagnetTarget: number?, -- UserId of player pulling it
    IsDrop: boolean?,
}

export type OrbEvent = {
    Action: "Spawn" | "Despawn" | "Grow",
    Id: number,
    Position: Vector3?,
    Tier: OrbTier?,
    XP: number?,
    IsDrop: boolean?,
    NewSize: Vector3?,
}

--[[
    -------------------------------------------------------------------------
    TIER DATA
    -------------------------------------------------------------------------
]]

-- Drastically reduced XP to prevent instant leveling (orbs are "snacks", kills are "meals")
XPOrbConfig.TIERS = {
    Common = { Name = "Common", XP = 10, Size = Vector3.new(1.5, 1.5, 1.5), Color = Color3.fromRGB(255, 215, 0), Chance = 75 },
    Uncommon = { Name = "Uncommon", XP = 25, Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(0, 255, 255), Chance = 20 },
    Rare = { Name = "Rare", XP = 100, Size = Vector3.new(4, 4, 4), Color = Color3.fromRGB(163, 35, 35), Chance = 4.5 },
    Legendary = { Name = "Legendary", XP = 500, Size = Vector3.new(8, 8, 8), Color = Color3.fromRGB(197, 209, 28), Chance = 0.5 },
} :: { [string]: OrbTier }

XPOrbConfig.TIER_LIST = {
    XPOrbConfig.TIERS.Common,
    XPOrbConfig.TIERS.Uncommon,
    XPOrbConfig.TIERS.Rare,
    XPOrbConfig.TIERS.Legendary,
}

return XPOrbConfig
