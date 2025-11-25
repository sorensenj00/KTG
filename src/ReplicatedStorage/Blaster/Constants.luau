--[[
    Module: Constants
    Description: Centralized constants for the Blaster weapon system including attribute keys, tags, UI settings, and weapon configuration.
    
    Dependencies: None
    
    Usage:
    - Attribute keys are used to read/write weapon properties on Tool instances
    - Tags are used with CollectionService for filtering and identification
    - UI constants control client-side interface behavior
    - VFX constants control visual effects timing and appearance
    
    Author: System
    Last Updated: 2025-01-20
]]

local Constants = {
	RAY_EXCLUDE_TAG = "RayExclude",
	NON_STATIC_TAG = "NonStatic",
	FIRE_MODE = {
		SEMI = "Semi",
		AUTO = "Auto",
	},
	AMMO_ATTRIBUTE = "_ammo",
	RELOADING_ATTRIBUTE = "_reloading",
	DAMAGE_ATTRIBUTE = "damage",
	FIRE_MODE_ATTRIBUTE = "fireMode",
	MAGAZINE_SIZE_ATTRIBUTE = "magazineSize",
	RANGE_ATTRIBUTE = "range",
	RATE_OF_FIRE_ATTRIBUTE = "rateOfFire",
	RELOAD_TIME_ATTRIBUTE = "reloadTime",
	RAYS_PER_SHOT_ATTRIBUTE = "raysPerShot",
	RAY_RADIUS_ATTRIBUTE = "rayRadius",
	SPREAD_ATTRIBUTE = "spread",
	VIEW_MODEL_ATTRIBUTE = "viewModel",
	RECOIL_MIN_ATTRIBUTE = "recoilMin",
	RECOIL_MAX_ATTRIBUTE = "recoilMax",
	UNANCHORED_IMPULSE_FORCE_ATTRIBUTE = "unanchoredImpulseForce",
	AIM_ASSIST_RANGE_ATTRIBUTE = "aimAssistRange",
	AIM_ASSIST_FOV_ATTRIBUTE = "aimAssistFov",
	AIM_ASSIST_FRICTION_STRENGTH_ATTRIBUTE = "aimAssistFrictionStrength",
	AIM_ASSIST_TRACKING_STRENGTH_ATTRIBUTE = "aimAssistTrackingStrength",
	AIM_ASSIST_CENTERING_STRENGTH_ATTRIBUTE = "aimAssistCenteringStrength",

	KEYBOARD_RELOAD_KEY_CODE = Enum.KeyCode.R,
	GAMEPAD_RELOAD_KEY_CODE = Enum.KeyCode.ButtonX,

	-- Pixel size under which a screen is considered 'small'. This is the same threshold used by the default touch UI.
	UI_SMALL_SCREEN_THRESHOLD = 500,
	-- Amount to scale the UI when on a small screen
	UI_SMALL_SCREEN_SCALE = 0.6,

	HITMARKER_SOUND_DELAY = 0.1,

	-- Aim assist
	AIM_ASSIST_BIND_NAME_START = "AimAssistStart",
	AIM_ASSIST_BIND_NAME_APPLY = "AimAssistApply",
	AIM_ASSIST_TARGET_TAG = "Target",

	AIM_ASSIST_DEADZONE = 0.1,
	AIM_ASSIST_INACTIVITY = 0.1,
	AIM_ASSIST_MIN_RANGE = 10,

	-- View model
	VIEW_MODEL_BIND_NAME = "BlasterViewModel",
	VIEW_MODEL_OFFSET = CFrame.new(0.9, -1.3, -1.3),
	VIEW_MODEL_BOBBING_SPEED = 0.4,
	VIEW_MODEL_BOBBING_AMOUNT = 0.05,
	VIEW_MODEL_BOBBING_TRANSITION_SPEED = 10,
	VIEW_MODEL_RELOAD_FADE_TIME = 0.1,
	-- Recoil
	RECOIL_BIND_NAME = "Recoiler",
	RECOIL_STOP_SPEED = 10,
	RECOIL_ZOOM_RETURN_SPEED = 20,
	RECOIL_DEFAULT_FOV = 70,
	-- VFX
	LASER_BEAM_VISUAL_SPEED = 200,
	
	-- Sway & Bobbing
	SWAY_AMOUNT = 0.6,
	SWAY_SMOOTHNESS = 12, -- Spring dampening
	WALK_BOB_SPEED = 14,
	WALK_BOB_MAGNITUDE = 0.15,
	
	-- Recoil (Spring Physics)
	RECOIL_KICK_BACK = 0.5, -- Z axis
	RECOIL_KICK_UP = 0.2,   -- Y axis rotation
	RECOIL_RECOVERY_SPEED = 20,
	
	-- Visuals
	BEAM_FADE_TIME = 0.15,
	BEAM_TEXTURE_SPEED = 4,
	IMPACT_LIGHT_BRIGHTNESS = 3,
	
	-- Audio
	PITCH_VARIATION = 0.05, -- +/- 5%
}

return Constants
