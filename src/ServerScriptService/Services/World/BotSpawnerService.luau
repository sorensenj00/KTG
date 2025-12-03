--[[
    Module: BotSpawner
    Description: Spawns bots, applies attributes, and handles respawning.
    Fixes: Unanchors ALL parts and improves raycast filtering.
    
    Dependencies:
    - ServerScriptService.GameLoop.ScalingEngine
    - ReplicatedStorage.GameLoop.GameConfig
    
    Author: System
    Last Updated: 2025-01-20
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ScalingEngine = require(ServerScriptService.Services.World.ScalingEngineService)
local GameConfig = require(ReplicatedStorage.GameLoop.GameConfig)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local SafeZoneConfig = require(ReplicatedStorage.GameLoop.SafeZoneConfig)

local BotSpawner = {}

local SPAWN_COUNT = GameConfig.Performance.MaxBots
local RESPAWN_DELAY = 3

-- Bots spawn directly in Workspace (no folder)

-- Helper to check if a point is inside any safe zone
local function isPointInSafeZone(x: number, z: number): boolean
	for _, pos in ipairs(SafeZoneConfig.SAFE_ZONE_LOCATIONS) do
		local size = SafeZoneConfig.SAFE_ZONE_SIZE
		-- Simple AABB check (ignore Y since we only care about X/Z)
		if math.abs(x - pos.X) <= size.X / 2 and math.abs(z - pos.Z) <= size.Z / 2 then
			return true
		end
	end
	return false
end

-- Helper to get random X/Z coordinates on Baseplate (avoiding safe zones)
local function getRandomSpawnXZ()
	-- Attempt to find the map/baseplate by common names
	local baseplate = Workspace:FindFirstChild("Baseplate")
		or Workspace:FindFirstChild("Map")
		or Workspace:FindFirstChild("Ground")

	local targetX, targetZ = 0, 0
	local size = Vector3.new(2048, 1, 2048) -- Default to standard map size (fixes "small square" issue)

	if baseplate then
		if baseplate:IsA("Model") then
			local cf, s = baseplate:GetBoundingBox()
			targetX, targetZ = cf.Position.X, cf.Position.Z
			size = s
		elseif baseplate:IsA("BasePart") then
			targetX, targetZ = baseplate.Position.X, baseplate.Position.Z
			size = baseplate.Size
		end
	else
		warn("BotSpawner: Baseplate/Map not found, using default 2048x2048 bounds")
	end

	local halfSizeX = size.X / 2
	local halfSizeZ = size.Z / 2

	-- Keep them slightly away from the absolute edge
	-- Retry up to 10 times to avoid safe zones
	for _ = 1, 10 do
		local x = math.random(-halfSizeX + 20, halfSizeX - 20)
		local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)
		local worldX, worldZ = targetX + x, targetZ + z
		
		if not isPointInSafeZone(worldX, worldZ) then
			return worldX, worldZ
		end
	end
	
	-- Fallback: return anyway if we couldn't find a non-safezone spot
	local x = math.random(-halfSizeX + 20, halfSizeX - 20)
	local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)
	return targetX + x, targetZ + z
end

local function spawnBot()
	local template = ServerStorage:FindFirstChild("TrainingBot")
	if not template then
		warn("No TrainingBot in ServerStorage")
		return
	end

	local bot = template:Clone()
	bot.Name = "Bot_" .. math.random(1000, 9999)

	local level = math.random(1, 5) -- Start at lower levels to prevent giant bots immediately
	bot:SetAttribute("Level", level)
	local biomass = ScalingConfig.GetXPRequired(level)
	bot:SetAttribute("Biomass", biomass)
	bot:SetAttribute("XP", 0)
	bot:SetAttribute("SpawnTime", Workspace:GetServerTimeNow())

	-- NOTE: "BotAI" tag is added AFTER physics initialization (see below)
	-- This prevents BotController from trying to move a bot in Physics state

	-- Give Weapon
	local weapon = ServerStorage:FindFirstChild("AutoBlaster")
	if weapon then
		local w = weapon:Clone()
		w.Parent = bot
	end

	local humanoid = bot:WaitForChild("Humanoid", 5)
	local rootPart = bot:WaitForChild("HumanoidRootPart", 5)

	if not humanoid or not rootPart then
		bot:Destroy()
		return
	end

	-- Disable ALL default Roblox UI (health bar and name display)
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.NameDisplayDistance = 0

	bot.PrimaryPart = rootPart

	-- === FIX 4: Reset Pivot Offset ===
	-- If the model's Pivot is offset from the RootPart (e.g. 500 studs down), 
	-- spawning it at the ground will place the body 500 studs in the sky.
	-- This forces the Pivot to match the RootPart exactly.
	rootPart.PivotOffset = CFrame.new()
	

	-- === FIX 1: Unanchor EVERYTHING ===
	-- Just unanchoring rootPart isn't enough if the template has anchored Head/Limbs
	for _, desc in ipairs(bot:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = true
		end
	end
	
	-- === IMPORTANT: Apply Scaling BEFORE Workspace ===
	-- Scaling the bot before it enters physics simulation prevents joints from breaking
	ScalingEngine.ResizeCharacter(bot, level)
	task.wait(0.1) -- Allow scaling to fully apply
	
	-- NOW parent to Workspace with correct scale
	bot.Parent = Workspace
	task.wait(0.05) -- Let physics initialize

	-- Calculate Position
	local targetX, targetZ = getRandomSpawnXZ()

	-- === FIX 2: Improved Raycast with Penetration ===
	-- We use a loop to ignore invisible parts (like sky barriers) that might be in MapVisuals
	local function castRayToGround(origin, dir)
		local ignoreList = { bot }
		if Workspace:FindFirstChild("Orbs") then
			table.insert(ignoreList, Workspace.Orbs)
		end
		if Workspace:FindFirstChild("Bots") then
			table.insert(ignoreList, Workspace.Bots)
		end
		-- Note: We intentionally DO NOT ignore MapVisuals/MapInteractables initially
		-- We want to hit them, but filter out the invisible ones below

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = ignoreList

		local result = Workspace:Raycast(origin, dir, rayParams)
		local attempts = 0
		
		-- Penetration Loop: If we hit something invisible, ignore it and try again
		while result and attempts < 10 do
			if result.Instance.Transparency >= 0.95 then
				-- Hit invisible part (likely barrier/trigger), add to ignore and retry
				table.insert(ignoreList, result.Instance)
				rayParams.FilterDescendantsInstances = ignoreList
				result = Workspace:Raycast(origin, dir, rayParams)
				attempts += 1
			else
				-- Hit visible part! Stop here.
				break
			end
		end
		
		return result
	end

	local rayOrigin = Vector3.new(targetX, 500, targetZ)
	local rayDirection = Vector3.new(0, -1000, 0)
	
	local rayResult = castRayToGround(rayOrigin, rayDirection)

	if rayResult then

		local hipHeight = humanoid.HipHeight
		-- Use ExtentsSize for safer height calculation if HipHeight is unreliable
		local size = bot:GetExtentsSize()
		local safeY = math.max(hipHeight + 2, size.Y / 2 + 1)
		
		-- Spawn slightly above the hit position
		local spawnPos = rayResult.Position + Vector3.new(0, safeY, 0)
		bot:PivotTo(CFrame.new(spawnPos))
	else
		-- Fallback: Use Baseplate height if available, otherwise default
		local fallbackY = 50
		
		-- Try to find ground height from Baseplate
		local baseplate = Workspace:FindFirstChild("Baseplate") or Workspace:FindFirstChild("Map")
		if baseplate then
			if baseplate:IsA("Model") then
				-- Try to find a part inside
				local part = baseplate:FindFirstChildWhichIsA("BasePart", true)
				if part then
					fallbackY = part.Position.Y + (part.Size.Y / 2)
				else
					fallbackY = baseplate:GetPivot().Position.Y
				end
			elseif baseplate:IsA("BasePart") then
				fallbackY = baseplate.Position.Y + (baseplate.Size.Y / 2)
			end
		end
		
		warn(string.format("BotSpawner: Raycast failed for bot %s at X=%.1f, Z=%.1f - using fallback Y=%.1f", bot.Name, targetX, targetZ, fallbackY))
		local hipHeight = humanoid.HipHeight
		bot:PivotTo(CFrame.new(targetX, fallbackY + hipHeight + 2, targetZ))
	end

	-- === FIX 3: Force Physics Wakeup ===
	-- Sometimes parts sleep in the air. This forces them to react to gravity.
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	task.delay(0.5, function()
		if bot and bot.Parent then
			-- Ensure EVERYTHING is unanchored before setting network owner
			for _, desc in ipairs(bot:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.Anchored = false
				end
			end
			
			if rootPart and rootPart:IsA("BasePart") and rootPart:IsDescendantOf(Workspace) then
				rootPart:SetNetworkOwner(nil)
			end
		end
		
		-- Reset to running so they can move
		if humanoid then
			humanoid:ChangeState(Enum.HumanoidStateType.Running)
		end
		
		-- NOW add the BotAI tag so BotController can start managing this bot
		-- This ensures the bot is in Running state and ready for MoveTo commands
		if bot and bot.Parent then
			CollectionService:AddTag(bot, "BotAI")
		end
	end)

	-- Respawn Logic
	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			if bot then
				bot:Destroy()
			end
			spawnBot()
		end)
	end)
end

function BotSpawner.Start()

	
	-- Wait for Baseplate/Map to ensure world geometry is loaded
	-- This prevents raycast failures that cause bots to spawn in the sky
	local mapObject = nil
	local startTime = os.clock()
	while os.clock() - startTime < 30 do
		mapObject = Workspace:FindFirstChild("Baseplate") 
			or Workspace:FindFirstChild("Map") 
			or Workspace:FindFirstChild("Ground")
		
		if mapObject then
			break
		end
		task.wait(1)
	end

	if not mapObject then
		warn("BotSpawner: Map/Baseplate not found after 30 seconds! Bots may spawn incorrectly.")
	else
		print("BotSpawner: Found map object: " .. mapObject.Name)
	end
	
	for _ = 1, SPAWN_COUNT do
		spawnBot()
		task.wait(0.1)
	end
	
	-- Spawn Display Bots
	BotSpawner.SpawnDisplayBots()
end

function BotSpawner.SpawnDisplayBots()
	-- Get random position
	local targetX, targetZ = getRandomSpawnXZ()
	
	-- Raycast to find ground height
	local function castRayToGround(origin, dir)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = {Workspace:FindFirstChild("Bots"), Workspace:FindFirstChild("Orbs")}
		
		local result = Workspace:Raycast(origin, dir, rayParams)
		return result
	end
	
	local rayOrigin = Vector3.new(targetX, 500, targetZ)
	local rayDirection = Vector3.new(0, -1000, 0)
	local rayResult = castRayToGround(rayOrigin, rayDirection)
	
	local startPos
	if rayResult then
		startPos = rayResult.Position
	else
		warn("BotSpawner: Could not find ground for display bots, using default height")
		startPos = Vector3.new(targetX, 5, targetZ)
	end

	local levels = {1, 5, 15, 30}
	local spacing = 15
	-- Center the line around the random position
	local lineStartX = startPos.X - ((#levels - 1) * spacing) / 2
	local lineZ = startPos.Z
	
	print(string.format("🎨 Spawning Display Bots at Random Location: %.1f, %.1f, %.1f", startPos.X, startPos.Y, startPos.Z))
	
	for i, level in ipairs(levels) do
		local template = ServerStorage:FindFirstChild("TrainingBot")
		if not template then break end
		
		local bot = template:Clone()
		bot.Name = "DisplayBot_Lv" .. level
		
		bot:SetAttribute("Level", level)
		local biomass = ScalingConfig.GetXPRequired(level)
		bot:SetAttribute("Biomass", biomass)
		bot:SetAttribute("XP", 0)
		bot:SetAttribute("SpawnTime", Workspace:GetServerTimeNow())
		
		-- DO NOT add "BotAI" tag so they don't move/shoot
		CollectionService:AddTag(bot, "DisplayBot")
		
		local humanoid = bot:WaitForChild("Humanoid")
		local rootPart = bot:WaitForChild("HumanoidRootPart")
		
		-- Disable ALL default Roblox UI (health bar and name display)
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		humanoid.NameDisplayDistance = 0
		
		-- Reset Pivot to ensure consistent spawning
		rootPart.PivotOffset = CFrame.new()
		
		-- Scale BEFORE parenting
		ScalingEngine.ResizeCharacter(bot, level)
		task.wait(0.1)
		
		bot.Parent = Workspace
		
		-- Position in a line
		local xPos = lineStartX + (i - 1) * spacing
		
		-- Raycast again for each bot to ensure they are on ground (in case of uneven terrain)
		local botRayOrigin = Vector3.new(xPos, 500, lineZ)
		local botRayResult = castRayToGround(botRayOrigin, rayDirection)
		local groundY = botRayResult and botRayResult.Position.Y or startPos.Y
		
		-- Add extra buffer for large bots to prevent clipping
		-- HipHeight * 1.2 + fixed buffer
		local spawnY = groundY + (humanoid.HipHeight * 1.1) + 4
		
		bot:PivotTo(CFrame.new(xPos, spawnY, lineZ) * CFrame.Angles(0, math.rad(180), 0)) -- Face forward
		
		-- Make completely still
		for _, part in ipairs(bot:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
	end
end

return BotSpawner
