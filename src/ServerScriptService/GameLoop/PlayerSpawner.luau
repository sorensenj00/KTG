local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local PlayerSpawner = {}

function PlayerSpawner.Start()
	print("--- Starting PlayerSpawner ---")

	-- Re-using similar logic to BotSpawner for consistency
	local function getRandomSpawnPosition(playerLevel: number?)
		-- Attempt to find the map/baseplate by common names
		local baseplate = Workspace:FindFirstChild("Baseplate")
			or Workspace:FindFirstChild("Map")
			or Workspace:FindFirstChild("Ground")

		local pos = Vector3.new(0, 10, 0)
		local size = Vector3.new(2048, 1, 2048) -- Default fallback

		if baseplate then
			if baseplate:IsA("Model") then
				local cf, s = baseplate:GetBoundingBox()
				pos = cf.Position
				size = s
			elseif baseplate:IsA("BasePart") then
				pos = baseplate.Position
				size = baseplate.Size
			end
		else
			warn("PlayerSpawner: Baseplate not found, using default bounds")
		end

		local halfSizeX = size.X / 2
		local halfSizeZ = size.Z / 2

		-- Random offset within baseplate (leaving a margin)
		local x = math.random(-halfSizeX + 20, halfSizeX - 20)
		local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)
		
		local targetX = pos.X + x
		local targetZ = pos.Z + z

		-- Calculate spawn height based on player size
		local level = playerLevel or 1
		local sizeMultiplier = ScalingConfig.GetSizeMultiplier(level)
		local playerHeight = 5 * sizeMultiplier
		local clearanceMargin = 5 -- Safety margin in studs

		-- Raycast to find exact floor height (prevents spawning on roof of map models)
		local rayOrigin = Vector3.new(targetX, 500, targetZ)
		local rayDirection = Vector3.new(0, -1000, 0)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {Workspace:FindFirstChild("Bots"), Workspace:FindFirstChild("Orbs"), Workspace:FindFirstChild("Players")}
		
		local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
		local spawnY = pos.Y + size.Y / 2 + (playerHeight / 2) + clearanceMargin -- Fallback

		if rayResult then
			spawnY = rayResult.Position.Y + (playerHeight / 2) + clearanceMargin
		end

		return Vector3.new(targetX, spawnY, targetZ)
	end

	local function onCharacterAdded(character)
		local rootPart = character:WaitForChild("HumanoidRootPart")
		if rootPart then
			-- Brief wait to ensure physics init
			task.wait()
			
			-- Get player level to calculate appropriate spawn height
			local player = Players:GetPlayerFromCharacter(character)
			local playerLevel = 1
			if player then
				playerLevel = player:GetAttribute("Level") or 1
			end
			
			local spawnPos = getRandomSpawnPosition(playerLevel)
			character:PivotTo(CFrame.new(spawnPos))
		end
	end

	local function onPlayerAdded(player)
		player.CharacterAdded:Connect(onCharacterAdded)
		-- Initial spawn since AutoLoads is off
		player:LoadCharacter()
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return PlayerSpawner
