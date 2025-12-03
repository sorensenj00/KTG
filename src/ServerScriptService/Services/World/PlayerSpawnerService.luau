local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local PlayerSpawner = {}

function PlayerSpawner.Start()
	print("--- Starting PlayerSpawner ---")

	-- Helper to wait for map (Event-based)
	local function waitForMap()
		local mapNames = {"Baseplate", "Map", "Ground"}
		
		-- 1. Check existing
		for _, name in ipairs(mapNames) do
			local found = Workspace:FindFirstChild(name)
			if found then return found end
		end
		
		-- 2. Wait for map to be added
		print("PlayerSpawner: Waiting for map to load...")
		while true do
			local child = Workspace.ChildAdded:Wait()
			if table.find(mapNames, child.Name) then
				print("PlayerSpawner: Map found via event:", child.Name)
				return child
			end
		end
	end

	-- Re-using similar logic to BotSpawner for consistency
	local function getRandomSpawnPosition(playerLevel: number?)
		local mapObject = waitForMap()
		
		local pos = Vector3.new(0, 10, 0)
		local size = Vector3.new(2048, 1, 2048) -- Default fallback

		if mapObject then
			if mapObject:IsA("Model") then
				local cf, s = mapObject:GetBoundingBox()
				pos = cf.Position
				size = s
			elseif mapObject:IsA("BasePart") then
				pos = mapObject.Position
				size = mapObject.Size
			elseif mapObject:IsA("Folder") then
				-- Wait for content if empty
				if #mapObject:GetChildren() == 0 then
					warn("PlayerSpawner: Map folder is empty! Waiting for parts...")
					mapObject.ChildAdded:Wait()
					task.wait(1) -- Give a moment for more parts to load
				end

				-- Calculate bounding box of folder contents
				local min = Vector3.new(math.huge, math.huge, math.huge)
				local max = Vector3.new(-math.huge, -math.huge, -math.huge)
				local foundParts = false
				
				for _, child in ipairs(mapObject:GetDescendants()) do
					if child:IsA("BasePart") then
						foundParts = true
						local p = child.Position
						local s = child.Size
						local halfS = s / 2
						
						min = min:Min(p - halfS)
						max = max:Max(p + halfS)
					end
				end
				
				if foundParts then
					size = max - min
					pos = min + (size / 2)
				end
			end
		else
			warn("PlayerSpawner: Map not found after timeout, using default bounds")
		end

		local halfSizeX = size.X / 2
		local halfSizeZ = size.Z / 2
		
		-- Calculate spawn height based on player size
		local level = playerLevel or 1
		local sizeMultiplier = ScalingConfig.GetSizeMultiplier(level)
		local playerHeight = 5 * sizeMultiplier
		local clearanceMargin = 5 -- Safety margin in studs
		
		-- Strict Validation Loop: Wait until we find valid ground
		-- This prevents spawning in the void if the map geometry hasn't streamed in yet
		while true do
			-- Random offset within baseplate (leaving a margin)
			local x = math.random(-halfSizeX + 20, halfSizeX - 20)
			local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)
			
			local targetX = pos.X + x
			local targetZ = pos.Z + z

			-- Raycast to find exact floor height
			local rayOrigin = Vector3.new(targetX, 500, targetZ)
			local rayDirection = Vector3.new(0, -1000, 0)
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = {Workspace:FindFirstChild("Bots"), Workspace:FindFirstChild("Orbs"), Workspace:FindFirstChild("Players")}
			
			local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
			
			if rayResult then
				local spawnY = rayResult.Position.Y + (playerHeight / 2) + clearanceMargin
				return Vector3.new(targetX, spawnY, targetZ)
			end
			
			-- Wait a bit before retrying to prevent freezing
			task.wait(0.1)
		end
	end

	local function onCharacterAdded(character)
		local rootPart = character:WaitForChild("HumanoidRootPart")
		if rootPart then
			-- **CRITICAL FIX**: Anchor immediately to prevent falling while we calculate spawn position
			-- LoadCharacter() spawns at (0,0,0) by default, which might be in the void
			rootPart.Anchored = true
			print("PlayerSpawner: Character spawned, anchored at", rootPart.Position)
			
			-- Get player level to calculate appropriate spawn height
			local player = Players:GetPlayerFromCharacter(character)
			local playerLevel = 1
			if player then
				playerLevel = player:GetAttribute("Level") or 1
			end
			
			-- This may take time if map is still loading
			local spawnPos = getRandomSpawnPosition(playerLevel)
			print("PlayerSpawner: Moving", player and player.Name or "character", "to", spawnPos)
			character:PivotTo(CFrame.new(spawnPos))
			
			-- Unanchor after positioning
			task.wait(0.1) -- Brief delay to ensure position is set
			rootPart.Anchored = false
			print("PlayerSpawner: Character unanchored")
			
			-- Add death tracking to fire ShowDeathSummary
			if player then
				local humanoid = character:WaitForChild("Humanoid", 10)
				if humanoid then
					humanoid.Died:Once(function()
						-- Fire ShowDeathSummary to client to show respawn UI
						task.spawn(function()
							local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 5)
							if remotes then
								local showDeathRemote = remotes:FindFirstChild("ShowDeathSummary")
								if showDeathRemote then
									-- Get session stats for death summary
									local sessionKills = player:GetAttribute("Kills") or 0
									local biomassLost = player:GetAttribute("Biomass") or 0
									local earnedDNA = 0 -- DNA calculation can be added later
									
									-- Fire to client
									showDeathRemote:FireClient(player, sessionKills, biomassLost, earnedDNA)
									print("💀 ShowDeathSummary fired for", player.Name)
								end
							end
						end)
					end)
				end
			end
		end
	end

	local function onPlayerAdded(player)
		player.CharacterAdded:Connect(onCharacterAdded)
		-- Initial spawn is handled by LobbyController (Quick Play)
		-- player:LoadCharacter() -- Removed to prevent bypassing Lobby
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
		
		-- CRITICAL: If player already has a character (spawned before service started),
		-- manually call onCharacterAdded since CharacterAdded event already fired
		if player.Character then
			print("PlayerSpawner: Processing existing character for", player.Name)
			onCharacterAdded(player.Character)
		end
	end
	
	-- Fire ServerReady event to tell clients spawning is ready
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
		if remotes then
			local serverReadyEvent = remotes:FindFirstChild("ServerReady")
			if not serverReadyEvent then
				serverReadyEvent = Instance.new("RemoteEvent")
				serverReadyEvent.Name = "ServerReady"
				serverReadyEvent.Parent = remotes
				print("✅ PlayerSpawner: Created ServerReady event")
			end
			serverReadyEvent:FireAllClients()
			print("✅ PlayerSpawner: Server ready - clients can spawn")
		end
	end)
end

return PlayerSpawner
