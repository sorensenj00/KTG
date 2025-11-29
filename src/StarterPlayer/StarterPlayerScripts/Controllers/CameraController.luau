--[[
    Controller: CameraController
    Description: Manages all camera behavior including recoil, screen shake, and level-based camera offset.
    Consolidates camera growth, recoil, shake, and giant footstep effects into a single controller.
    
    Dependencies:
    - Players (Roblox Service)
    - RunService (Roblox Service)
    - Workspace (Roblox Service)
    - ReplicatedStorage (Roblox Service)
    - ReplicatedStorage.GameLoop.ScalingConfig
    - ReplicatedStorage.Utility.lerp
    - ReplicatedStorage.Blaster.Constants
    - ReplicatedStorage.Blaster.Remotes.GiantFootstepShake (RemoteEvent)
    
    Public API:
    - Start(): void - Initialize the controller
    - Recoil(amount: Vector2): void - Apply recoil to the camera (called by BlasterController)
    
    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local lerp = require(ReplicatedStorage.Utility.lerp)
local Constants = require(ReplicatedStorage.Blaster.Constants)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Configuration
local CAMERA_GROWTH_BIND_NAME = "CameraGrowthController"
local CAMERA_PITCH_OFFSET_MAX = math.rad(-15) -- Maximum downward angle in radians (15 degrees)
local CAMERA_OFFSET_Y_MAX = 5 -- Maximum camera height offset in studs
local LERP_SPEED = 5 -- How fast camera adjusts
local RECOIL_STOP_SPEED = Constants.RECOIL_STOP_SPEED or 10
local RECOIL_ZOOM_RETURN_SPEED = Constants.RECOIL_ZOOM_RETURN_SPEED or 20
local RECOIL_DEFAULT_FOV = Constants.RECOIL_DEFAULT_FOV or 70

-- State
local targetPitchOffset = 0
local currentPitchOffset = 0
local targetCameraOffsetY = 0
local currentCameraOffsetY = 0
local humanoid = nil
local lastAppliedPitchOffset = 0

-- Recoil state
local recoil = Vector2.new()
local zoom = 0

-- Screen shake state (from recoil/shooting)
local screenShake = Vector2.new()
local screenShakeDecay = 15

-- Giant footstep shake state
local giantFootstepShake = Vector2.new()
local giantFootstepShakeDecay = 12

-- Camera shaker state (micro-shake on shoot, thud on kill)
local shakeOffset = Vector3.new(0, 0, 0)
local shakeDecay = 25

-- Calculate camera adjustments based on level
local function updateCameraTargets(level: number)
	local sizeMultiplier = ScalingConfig.GetSizeMultiplier(level)

	-- Calculate progress from min size to max size
	local minSize = ScalingConfig.MIN_SIZE
	local maxSize = ScalingConfig.MAX_SIZE
	local progress = math.clamp((sizeMultiplier - minSize) / (maxSize - minSize), 0, 1)

	-- Pitch offset: More downward angle as player grows
	targetPitchOffset = progress * CAMERA_PITCH_OFFSET_MAX

	-- Camera height offset: Higher camera position as player grows
	targetCameraOffsetY = progress * CAMERA_OFFSET_Y_MAX
end

-- Render step for recoil (Camera.Value + 2)
local function onRecoilRenderStepped(deltaTime: number)
	camera.CFrame *= CFrame.Angles(recoil.Y * deltaTime, recoil.X * deltaTime, 0)
	camera.FieldOfView = RECOIL_DEFAULT_FOV + zoom

	-- Apply screen shake from shooting
	if screenShake.Magnitude > 0.01 then
		local random = Random.new()
		local shakeX = (random:NextNumber() - 0.5) * screenShake.X * 2
		local shakeY = (random:NextNumber() - 0.5) * screenShake.Y * 2
		camera.CFrame = camera.CFrame * CFrame.new(shakeX, shakeY, 0)
	end

	recoil = recoil:Lerp(Vector2.zero, math.min(deltaTime * RECOIL_STOP_SPEED, 1))
	zoom = lerp(zoom, 0, math.min(deltaTime * RECOIL_ZOOM_RETURN_SPEED, 1))
	screenShake = screenShake:Lerp(Vector2.zero, math.min(deltaTime * screenShakeDecay, 1))
end

-- Render step for camera growth (Camera.Value + 3)
local function onGrowthRenderStepped(deltaTime: number)
	-- Smoothly interpolate camera offset Y
	currentCameraOffsetY = lerp(currentCameraOffsetY, targetCameraOffsetY, math.min(deltaTime * LERP_SPEED, 1))

	-- Pitch offset removed to prevent camera drift
	-- We only adjust height now

	-- Apply camera height offset (Y-axis only) via Humanoid
	if humanoid then
		humanoid.CameraOffset = Vector3.new(0, currentCameraOffsetY, 0)
	end
end

-- Render step for shake (Camera.Value + 4)
local function onShakeRenderStepped(deltaTime: number)
	-- Apply giant footstep shake
	if giantFootstepShake.Magnitude > 0.01 then
		local random = Random.new()
		local shakeX = (random:NextNumber() - 0.5) * giantFootstepShake.X
		local shakeY = (random:NextNumber() - 0.5) * giantFootstepShake.Y
		camera.CFrame = camera.CFrame * CFrame.new(shakeX, shakeY, 0)
	end

	-- Decay giant footstep shake
	giantFootstepShake = giantFootstepShake:Lerp(Vector2.zero, math.min(deltaTime * giantFootstepShakeDecay, 1))

	-- Apply camera shaker offset (micro-shake on shoot, thud on kill)
	if shakeOffset.Magnitude > 0.01 then
		camera.CFrame = camera.CFrame * CFrame.new(shakeOffset)
		shakeOffset = shakeOffset:Lerp(Vector3.zero, math.min(deltaTime * shakeDecay, 1))
	else
		shakeOffset = Vector3.zero
	end
end

-- Listen for level changes
local function onLevelChanged(newLevel: number)
	updateCameraTargets(newLevel)
end

local CameraController = {}

-- Public API: Apply recoil (called by BlasterController)
function CameraController.Recoil(recoilAmount: Vector2)
	zoom = 1
	recoil += recoilAmount
	-- Add subtle screen shake on shoot
	local shakeIntensity = 0.15 -- Small shake amount
	screenShake = Vector2.new(shakeIntensity, shakeIntensity)
end

-- Public API: Apply micro-shake on shoot
function CameraController.ShakeOnShoot()
	local random = Random.new()
	local intensity = 0.08 -- Low amplitude
	shakeOffset = shakeOffset
		+ Vector3.new((random:NextNumber() - 0.5) * intensity, (random:NextNumber() - 0.5) * intensity, 0)
end

-- Public API: Apply larger thud on kill
function CameraController.ShakeOnKill()
	local random = Random.new()
	local intensity = 0.3 -- Larger amplitude
	shakeOffset = shakeOffset
		+ Vector3.new((random:NextNumber() - 0.5) * intensity, (random:NextNumber() - 0.5) * intensity, 0)
end

function CameraController.Start()
	-- Initialize humanoid and level
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

	-- Bind render steps with proper priorities
	RunService:BindToRenderStep(Constants.RECOIL_BIND_NAME, Enum.RenderPriority.Camera.Value + 2, onRecoilRenderStepped)
	RunService:BindToRenderStep(CAMERA_GROWTH_BIND_NAME, Enum.RenderPriority.Camera.Value + 3, onGrowthRenderStepped)
	RunService:BindToRenderStep("GiantFootstepShake", Enum.RenderPriority.Camera.Value + 4, onShakeRenderStepped)
	RunService:BindToRenderStep("CameraShaker", Enum.RenderPriority.Camera.Value + 3, onShakeRenderStepped)

	-- Listen for giant footstep shake events
	local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
	local giantFootstepShakeRemote = remotes:WaitForChild("GiantFootstepShake")

	giantFootstepShakeRemote.OnClientEvent:Connect(function(shakeIntensity: number)
		-- Add shake to current shake value
		giantFootstepShake = giantFootstepShake + Vector2.new(shakeIntensity, shakeIntensity)
	end)

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
		recoil = Vector2.zero
		zoom = 0
		screenShake = Vector2.zero
		giantFootstepShake = Vector2.zero
		shakeOffset = Vector3.zero
	end)

	print("✅ CameraController: Initialized")
end

return CameraController
