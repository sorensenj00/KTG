local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local lerp = require(ReplicatedStorage.Utility.lerp)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Configuration
local CAMERA_GROWTH_BIND_NAME = "CameraGrowthController"
local CAMERA_PITCH_OFFSET_MAX = math.rad(-15) -- Maximum downward angle in radians (15 degrees)
local CAMERA_OFFSET_Y_MAX = 5 -- Maximum camera height offset in studs
local LERP_SPEED = 5 -- How fast camera adjusts

-- State
local currentLevel = 1
local targetPitchOffset = 0
local currentPitchOffset = 0
local targetCameraOffsetY = 0
local currentCameraOffsetY = 0
local humanoid = nil

-- Calculate camera adjustments based on level
local function updateCameraTargets(level: number)
	local sizeMultiplier = ScalingConfig.GetSizeMultiplier(level)
	
	-- Calculate progress from min size (0.4) to max size (6.0)
	local minSize = ScalingConfig.MIN_SIZE
	local maxSize = ScalingConfig.MAX_SIZE
	local progress = math.clamp((sizeMultiplier - minSize) / (maxSize - minSize), 0, 1)
	
	-- Pitch offset: More downward angle as player grows
	targetPitchOffset = progress * CAMERA_PITCH_OFFSET_MAX
	
	-- Camera height offset: Higher camera position as player grows
	targetCameraOffsetY = progress * CAMERA_OFFSET_Y_MAX
end

-- Store last frame's pitch offset to avoid accumulation
local lastAppliedPitchOffset = 0

-- Update camera on render step
local function onRenderStepped(deltaTime: number)
	-- Smoothly interpolate pitch offset
	currentPitchOffset = lerp(currentPitchOffset, targetPitchOffset, math.min(deltaTime * LERP_SPEED, 1))
	
	-- Smoothly interpolate camera offset Y
	currentCameraOffsetY = lerp(currentCameraOffsetY, targetCameraOffsetY, math.min(deltaTime * LERP_SPEED, 1))
	
	-- Apply pitch offset to camera (downward angle)
	-- Apply only the delta to avoid accumulation
	local pitchDelta = currentPitchOffset - lastAppliedPitchOffset
	if math.abs(pitchDelta) > 0.0001 then
		camera.CFrame = camera.CFrame * CFrame.Angles(pitchDelta, 0, 0)
		lastAppliedPitchOffset = currentPitchOffset
	end
	
	-- Apply camera height offset (Y-axis only) via Humanoid
	if humanoid then
		humanoid.CameraOffset = Vector3.new(0, currentCameraOffsetY, 0)
	end
end

-- Listen for level changes
local function onLevelChanged(newLevel: number)
	currentLevel = newLevel
	updateCameraTargets(newLevel)
end

-- Initialize
local function initialize()
	-- Get humanoid from character
	if player.Character then
		humanoid = player.Character:FindFirstChild("Humanoid")
		local level = player:GetAttribute("Level") or 1
		onLevelChanged(level)
	end
	
	-- Listen for character added to get humanoid
	player.CharacterAdded:Connect(function(character)
		humanoid = character:WaitForChild("Humanoid", 5)
		local level = player:GetAttribute("Level") or 1
		onLevelChanged(level)
	end)
	
	-- Listen for level attribute changes
	player:GetAttributeChangedSignal("Level"):Connect(function()
		local level = player:GetAttribute("Level") or 1
		onLevelChanged(level)
	end)
	
	-- Bind to render step (after CameraRecoiler which is Camera.Value + 2)
	-- We'll use Camera.Value + 3 to run after recoil
	RunService:BindToRenderStep(CAMERA_GROWTH_BIND_NAME, Enum.RenderPriority.Camera.Value + 3, onRenderStepped)
end

-- Cleanup on character removal
player.CharacterRemoving:Connect(function()
	-- Reset camera offsets
	if humanoid then
		humanoid.CameraOffset = Vector3.new(0, 0, 0)
	end
	targetPitchOffset = 0
	currentPitchOffset = 0
	lastAppliedPitchOffset = 0
	targetCameraOffsetY = 0
	currentCameraOffsetY = 0
	humanoid = nil
end)

initialize()

