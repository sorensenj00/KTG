local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local PlayerSpawner = {}

function PlayerSpawner.Start()
	print("--- Starting PlayerSpawner ---")

	-- Re-using similar logic to BotSpawner for consistency
	local function getRandomSpawnPosition(playerLevel: number?)
		local baseplate = Workspace:FindFirstChild("Baseplate")
		local pos = Vector3.new(0, 10, 0)
		local size = Vector3.new(100, 1, 100) -- Default fallback

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

		-- Calculate spawn height based on player size
		-- For large players, we need to spawn them higher to prevent clipping
		local level = playerLevel or 1
		local sizeMultiplier = ScalingConfig.GetSizeMultiplier(level)
		-- Standard R15 character height is ~5 studs, so scaled height is ~5 * sizeMultiplier
		-- We spawn at: baseplate top + half player height + clearance margin
		local playerHeight = 5 * sizeMultiplier
		local clearanceMargin = 10 -- Safety margin in studs
		local spawnHeight = pos.Y + size.Y / 2 + (playerHeight / 2) + clearanceMargin

		return Vector3.new(pos.X + x, spawnHeight, pos.Z + z)
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
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

return PlayerSpawner
