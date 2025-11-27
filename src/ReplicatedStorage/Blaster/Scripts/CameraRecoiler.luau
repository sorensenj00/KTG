local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local lerp = require(ReplicatedStorage.Utility.lerp)
local Spring = require(ReplicatedStorage.Utility.Spring)

local camera = Workspace.CurrentCamera

-- Configuration
local SPRING_STIFFNESS = 20 -- Speed: High for snappy "punch"
local SPRING_DAMPING = 1    -- Friction: High to stop bounce (Critical Damping)

-- State
local recoilSpringX = Spring.new(SPRING_DAMPING, SPRING_STIFFNESS) -- Pitch (Up/Down)
local recoilSpringY = Spring.new(SPRING_DAMPING, SPRING_STIFFNESS) -- Yaw (Left/Right)
local zoom = 0
local screenShake = Vector2.new()
local screenShakeDecay = 15 -- How fast screen shake decays

local function onRenderStepped(deltaTime: number)
	-- DISABLED: Camera recoil is now handled entirely by ViewModelController
	-- The ViewModelController applies visual recoil to the weapon model using Spring physics
	
	-- Springs are kept for potential future use but not currently updating
	-- recoilSpringX:update(deltaTime)
	-- recoilSpringY:update(deltaTime)

	-- Apply Zoom
	camera.FieldOfView = Constants.RECOIL_DEFAULT_FOV + zoom
	zoom = lerp(zoom, 0, math.min(deltaTime * Constants.RECOIL_ZOOM_RETURN_SPEED, 1))
	
	-- Apply Noise (Shake) - Layered on top if needed
	if screenShake.Magnitude > 0.01 then
		local random = Random.new()
		local shakeX = (random:NextNumber() - 0.5) * screenShake.X * 2
		local shakeY = (random:NextNumber() - 0.5) * screenShake.Y * 2
		camera.CFrame = camera.CFrame * CFrame.new(shakeX, shakeY, 0)

		-- Decay shake
		screenShake = screenShake:Lerp(Vector2.zero, math.min(deltaTime * screenShakeDecay, 1))
	end
end

local CameraRecoiler = {}

function CameraRecoiler.recoil(recoilAmount: Vector2)
	-- recoilAmount is typically Vector2(yaw, pitch) in radians
	-- x is usually yaw/horizontal, y is pitch/vertical.

	zoom = 1

	-- Apply Impulse to Springs
	-- "Kick UP" means positive Pitch (X axis rotation).
	-- Note: CFrame.Angles(pitch, yaw, roll). Pitch is X-axis.
	-- If recoilAmount.Y is the vertical kick, we impulse the Pitch spring.

	-- In Roblox, positive X rotation looks DOWN. Negative X looks UP.
	-- We want the camera to kick UP, so we need a NEGATIVE X rotation.

	recoilSpringX:impulse(-recoilAmount.Y) -- Pitch (Kick Up = Negative X)
	recoilSpringY:impulse(recoilAmount.X) -- Yaw (Kick Side)

	-- Note: We generally do NOT add noise to pistol shots as per instructions ("purely use Spring").
	-- So we removed the automatic `screenShake` addition here.
	-- If screen shake is needed for explosions, it should be called via a separate method.
end

-- Function for purely noise-based shake (Explosions, Earthquakes)
function CameraRecoiler.shake(intensity: Vector2)
	screenShake = intensity
end

-- apply recoil after aim assist
RunService:BindToRenderStep(Constants.RECOIL_BIND_NAME, Enum.RenderPriority.Camera.Value + 2, onRenderStepped)

return CameraRecoiler
