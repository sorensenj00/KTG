--!nocheck
-- Lightweight Camera Shaker
-- Provides micro-shake on shoot and larger thud on kill

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local camera = Workspace.CurrentCamera

local CameraShaker = {}

-- Shake state
local shakeOffset = Vector3.new(0, 0, 0)
local shakeDecay = 25 -- How fast shake decays

-- Update shake on render step (after all other camera logic)
local function updateShake(deltaTime: number)
	if shakeOffset.Magnitude > 0.01 then
		-- Apply shake to camera
		camera.CFrame = camera.CFrame * CFrame.new(shakeOffset)
		
		-- Decay shake
		shakeOffset = shakeOffset:Lerp(Vector3.zero, math.min(deltaTime * shakeDecay, 1))
	else
		shakeOffset = Vector3.zero
	end
end

-- Apply micro-shake on shoot (high frequency, low amplitude)
function CameraShaker:shakeOnShoot()
	local random = Random.new()
	local intensity = 0.08 -- Low amplitude
	local frequency = 20 -- High frequency
	
	-- Add small random shake
	shakeOffset = shakeOffset + Vector3.new(
		(random:NextNumber() - 0.5) * intensity,
		(random:NextNumber() - 0.5) * intensity,
		0
	)
end

-- Apply larger thud on kill
function CameraShaker:shakeOnKill()
	local random = Random.new()
	local intensity = 0.3 -- Larger amplitude
	local frequency = 8 -- Lower frequency
	
	-- Add larger shake
	shakeOffset = shakeOffset + Vector3.new(
		(random:NextNumber() - 0.5) * intensity,
		(random:NextNumber() - 0.5) * intensity,
		0
	)
end

-- Bind to render step (after camera recoil)
RunService:BindToRenderStep(
	"CameraShaker",
	Enum.RenderPriority.Camera.Value + 3, -- After recoil
	updateShake
)

return CameraShaker

