local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local camera = Workspace.CurrentCamera

-- Configuration
local SHAKE_DECAY = 12 -- How fast screen shake decays

-- State
local screenShake = Vector2.new()

-- Handle screen shake from giant footsteps
local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
local giantFootstepShakeRemote = remotes:WaitForChild("GiantFootstepShake")

giantFootstepShakeRemote.OnClientEvent:Connect(function(shakeIntensity: number)
	-- Add shake to current shake value
	screenShake = screenShake + Vector2.new(shakeIntensity, shakeIntensity)
end)

-- Apply screen shake on render step
-- This should run after CameraRecoiler to work with existing shake system
-- CameraRecoiler uses Camera.Value + 2, so we'll use Camera.Value + 4
local RunService = game:GetService("RunService")
RunService:BindToRenderStep("GiantFootstepShake", Enum.RenderPriority.Camera.Value + 4, function(deltaTime: number)
	if screenShake.Magnitude > 0.01 then
		local random = Random.new()
		local shakeX = (random:NextNumber() - 0.5) * screenShake.X
		local shakeY = (random:NextNumber() - 0.5) * screenShake.Y
		camera.CFrame = camera.CFrame * CFrame.new(shakeX, shakeY, 0)
	end
	
	-- Decay shake over time
	screenShake = screenShake:Lerp(Vector2.zero, math.min(deltaTime * SHAKE_DECAY, 1))
end)

