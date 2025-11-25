local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Constants = require(ReplicatedStorage.Blaster.Constants)
local lerp = require(ReplicatedStorage.Utility.lerp)
local camera = Workspace.CurrentCamera
local recoil = Vector2.new()
local zoom = 0
local screenShake = Vector2.new()
local screenShakeDecay = 15 -- How fast screen shake decays
local function onRenderStepped(deltaTime: number)
	camera.CFrame *= CFrame.Angles(recoil.Y * deltaTime, recoil.X * deltaTime, 0)
	camera.FieldOfView = Constants.RECOIL_DEFAULT_FOV + zoom
	
	-- Apply screen shake
	if screenShake.Magnitude > 0.01 then
		local random = Random.new()
		local shakeX = (random:NextNumber() - 0.5) * screenShake.X * 2
		local shakeY = (random:NextNumber() - 0.5) * screenShake.Y * 2
		camera.CFrame = camera.CFrame * CFrame.new(shakeX, shakeY, 0)
	end
	
	recoil = recoil:Lerp(Vector2.zero, math.min(deltaTime * Constants.RECOIL_STOP_SPEED, 1))
	zoom = lerp(zoom, 0, math.min(deltaTime * Constants.RECOIL_ZOOM_RETURN_SPEED, 1))
	screenShake = screenShake:Lerp(Vector2.zero, math.min(deltaTime * screenShakeDecay, 1))
end
local CameraRecoiler = {}
function CameraRecoiler.recoil(recoilAmount: Vector2)
	zoom = 1
	recoil += recoilAmount
	-- Add subtle screen shake on shoot
	local shakeIntensity = 0.15 -- Small shake amount
	screenShake = Vector2.new(shakeIntensity, shakeIntensity)
end
-- apply recoil after aim assist
RunService:BindToRenderStep(Constants.RECOIL_BIND_NAME, Enum.RenderPriority.Camera.Value + 2, onRenderStepped)
return CameraRecoiler