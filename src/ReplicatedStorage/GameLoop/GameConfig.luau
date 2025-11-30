-- ReplicatedStorage/GameLoop/GameConfig.lua

-- Centralized configuration to avoid scattered constants

local GameConfig = {}

-- === PERFORMANCE SETTINGS ===

GameConfig.Performance = {

	MaxXPOrbs = 500,

	MaxBots = 8,

	MaxVehicles = 3,

	UpdateInterval = 0.1, -- Heartbeat interval for expensive operations

	MaxParticlesPerEffect = 50,
}

-- === AUDIO ASSETS ===

-- Centralized to prevent asset ID duplication and ease licensing tracking

GameConfig.Audio = {

	HitMarker = "rbxassetid://705502934",

	WeaponShoot = "rbxassetid://131961136",

	-- Add source/license comments here

	-- TODO: Replace with licensed assets
}

-- === VISUAL EFFECTS ===

GameConfig.VFX = {

	BeamFadeTime = 0.15,

	ImpactLightBrightness = 3,

	ParticleLifetime = 1.5,

	MaxActiveBeams = 50,
}

-- === WEAPON DEFAULTS ===

GameConfig.Weapons = {

	DefaultDamage = 10,

	DefaultRange = 300,

	DefaultFireRate = 600, -- RPM

	DefaultSpread = 2, -- Degrees

	RecoilMultiplier = 1.0,
}

-- === PLAYER PROGRESSION ===

GameConfig.Progression = {

	StartingLevel = 1,

	MaxLevel = 50,

	XPBaseRequirement = 150,

	XPExponent = 2.2,

	KillBaseReward = 50,

	KillRewardMultiplier = 150,
}

-- === META PROGRESSION ===

GameConfig.Meta = {

	SessionXPToGlobalXPRatio = 0.5,

	GlobalXPPerKill = 10,

	StartingBiomass = 0,
}

-- === ZONES ===

GameConfig.Zones = {

	SafeZoneRadius = 200,

	SafeZoneMaxLevel = 50,

	SafeZoneSpeed = 5,
}

-- === KILLSTREAKS ===

GameConfig.Killstreaks = {

	SpeedBoostThreshold = 3,

	SpeedBoostMultiplier = 1.5,

	SpeedBoostDuration = 20,

	ShieldThreshold = 5,

	ShieldDuration = 10,

	NukeThreshold = 10,

	NukeRadius = 100,
}

-- === CAMERA ===

GameConfig.Camera = {

	DefaultFOV = 70,

	RecoilStopSpeed = 10,

	MaxPitchOffset = -15, -- Degrees

	MaxHeightOffset = 5, -- Studs

	ShakeDecay = 12,
}

-- === VALIDATION ===

-- Ensure critical values are within safe ranges

local function validate()
	assert(GameConfig.Progression.MaxLevel > 0, "MaxLevel must be positive")

	assert(GameConfig.Performance.MaxXPOrbs > 0, "MaxXPOrbs must be positive")

	assert(GameConfig.Meta.SessionXPToGlobalXPRatio >= 0, "XP ratio cannot be negative")

	print("✅ GameConfig validated successfully")
end

validate()

return GameConfig
