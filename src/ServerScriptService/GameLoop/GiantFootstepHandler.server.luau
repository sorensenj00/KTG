local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
local giantFootstepRemote = remotes:WaitForChild("GiantFootstep")
local giantFootstepShakeRemote = remotes:WaitForChild("GiantFootstepShake")

-- Configuration
local SHAKE_RANGE = 100 -- Distance in studs that players feel the shake
local SHAKE_INTENSITY_BASE = 0.3 -- Base shake intensity

-- Handle giant footstep from client
giantFootstepRemote.OnServerEvent:Connect(function(player: Player, footstepPosition: Vector3)
	-- Validate that player has a character and is actually a giant
	if not player.Character then
		return
	end

	local level = player:GetAttribute("Level") or 1
	if level < 21 then
		return -- Not a giant
	end

	-- Find all nearby players
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer == player then
			continue -- Skip the player who made the footstep
		end

		if not otherPlayer.Character then
			continue
		end

		local otherRootPart = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
		if not otherRootPart then
			continue
		end

		-- Calculate distance
		local distance = (footstepPosition - otherRootPart.Position).Magnitude

		if distance <= SHAKE_RANGE then
			-- Calculate shake intensity based on distance (closer = more intense)
			local distanceFactor = 1 - (distance / SHAKE_RANGE)
			local shakeIntensity = SHAKE_INTENSITY_BASE * distanceFactor

			-- Fire shake event to nearby player
			giantFootstepShakeRemote:FireClient(otherPlayer, shakeIntensity)
		end
	end
end)
