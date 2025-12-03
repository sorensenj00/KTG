--[[
    Module: XPOrbService (Optimized - Data Only)
    Description: Server-authoritative orb data management with client-side visuals.
    
    Performance Improvements:
    - Single Heartbeat loop (was ~100 individual connections)
    - No Part instances on server (client renders visuals)
    - Batched replication via RemoteEvents
    
    Author: System (Refactored Phase 3)
    Last Updated: 2025-11-29
]]

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")




local XPOrbConfig = require(ReplicatedStorage.GameLoop.XPOrbConfig)

local XPOrbService = {}

-- Data Storage (Server only - no Part instances)
local activeOrbs = {} -- [orbId] = {id, position, tier, xpValue, spawnTime, magnetTarget}
local nextOrbId = 1

-- Remotes
local orbEvents
local collectOrbRemote
-- local ProgressionService = nil

-- Helper to get random spawn position
local function getRandomSpawnPosition()
	local baseplate = Workspace:FindFirstChild("Baseplate")
		or Workspace:FindFirstChild("Map")
		or Workspace:FindFirstChild("Ground")

	local centerX, centerZ = 0, 0
	local sizeX, sizeZ = 2048, 2048

	if baseplate then
		if baseplate:IsA("Model") then
			local cf, s = baseplate:GetBoundingBox()
			centerX, centerZ = cf.Position.X, cf.Position.Z
			sizeX, sizeZ = s.X, s.Z
		elseif baseplate:IsA("BasePart") then
			centerX, centerZ = baseplate.Position.X, baseplate.Position.Z
			sizeX, sizeZ = baseplate.Size.X, baseplate.Size.Z
		end
	end

	local halfSizeX = sizeX / 2
	local halfSizeZ = sizeZ / 2

	local x = math.random(-halfSizeX + 20, halfSizeX - 20)
	local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)

	local targetX = centerX + x
	local targetZ = centerZ + z

	-- Raycast to find floor height
	local rayOrigin = Vector3.new(targetX, 500, targetZ)
	local rayDirection = Vector3.new(0, -1000, 0)
	
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {Players}
	raycastParams.RespectCanCollide = true

	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	local yPos = 10
	if rayResult then
		yPos = rayResult.Position.Y
	end

	return Vector3.new(targetX, yPos, targetZ)
end

-- Spawn orb (data only)
local function spawnOrb()
	if #activeOrbs >= XPOrbConfig.MAX_ORBS then
		-- Remove oldest orb
		local oldestId = next(activeOrbs)
		if oldestId then
			activeOrbs[oldestId] = nil
			orbEvents:FireAllClients({Action = "Despawn", Id = oldestId})
		end
	end

	-- Select tier
	local randomValue = math.random(1, 100)
	local accumulatedChance = 0
	local selectedTier = XPOrbConfig.TIER_LIST[1]

	for _, tier in ipairs(XPOrbConfig.TIER_LIST) do
		accumulatedChance = accumulatedChance + tier.Chance
		if randomValue <= accumulatedChance then
			selectedTier = tier
			break
		end
	end

	local spawnPos = getRandomSpawnPosition()
	-- Fix: Offset Y by half size so it sits ON the ground
	spawnPos = spawnPos + Vector3.new(0, selectedTier.Size.Y / 2, 0)

	local orbId = nextOrbId
	nextOrbId = nextOrbId + 1

	-- Calculate Average Level for Scaling
	local totalLevel = 0
	local playerCount = 0
	for _, p in ipairs(Players:GetPlayers()) do
		totalLevel = totalLevel + (p:GetAttribute("Level") or 1)
		playerCount = playerCount + 1
	end
	local avgLevel = playerCount > 0 and (totalLevel / playerCount) or 1
	local scalingMult = 1 + (avgLevel * 0.5) -- +50% per average level

	-- Store orb data
	activeOrbs[orbId] = {
		id = orbId,
		position = spawnPos,
		tier = selectedTier,
		currentSize = selectedTier.Size, -- Copy size to allow individual scaling
		xpValue = math.floor(selectedTier.XP * scalingMult),
		spawnTime = tick(),
		growthStage = 0,
		magnetTarget = nil
	}

	-- Replicate to all clients
	orbEvents:FireAllClients({
		Action = "Spawn",
		Id = orbId,
		Position = spawnPos,
		Tier = {
			Name = selectedTier.Name,
			Size = selectedTier.Size,
			Color = selectedTier.Color
		},
		XP = selectedTier.XP
	})
end

-- Server update loop (single Heartbeat for all orbs)
local magnetCheckTimer = 0
local MAGNET_CHECK_INTERVAL = 0.15 -- Check for magnets ~6 times a second (Optimization)

local function updateOrbs(dt)
	local currentTime = tick()
	magnetCheckTimer += dt
	local checkMagnet = magnetCheckTimer >= MAGNET_CHECK_INTERVAL

	if checkMagnet then
		magnetCheckTimer = 0
	end

	-- Optimization: Cache player positions for this frame to avoid getting HumanoidRootPart N times
	local playerPositions = {}
	if checkMagnet then
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				local root = player.Character:FindFirstChild("HumanoidRootPart")
				if root then
					table.insert(playerPositions, { Player = player, Position = root.Position, UserId = player.UserId })
				end
			end
		end
	end
	
	for orbId, orb in pairs(activeOrbs) do
		-- Check lifetime and upgrade
		local age = currentTime - orb.spawnTime
		
		-- Auto-Despawn
		if age > XPOrbConfig.MAX_LIFETIME then
			activeOrbs[orbId] = nil
			orbEvents:FireAllClients({Action = "Despawn", Id = orbId})
			continue
		end
		
		-- Growth Logic
		local currentStage = math.floor(age / XPOrbConfig.ORB_GROWTH_INTERVAL)
		if currentStage > orb.growthStage and orb.growthStage < XPOrbConfig.MAX_GROWTH_STAGES then
			orb.growthStage = currentStage

			-- Grow Stats
			orb.xpValue = math.floor(orb.xpValue * XPOrbConfig.GROWTH_XP_MULTIPLIER)
			orb.currentSize = orb.currentSize * XPOrbConfig.GROWTH_SIZE_MULTIPLIER -- Grow visual size
			
			-- Replicate Growth
			orbEvents:FireAllClients({
				Action = "Grow",
				Id = orbId,
				NewSize = orb.currentSize
			})
		end
		
		-- Magnet logic (Throttled Search)
		if checkMagnet then
			local closestData = nil
			local closestDistSq = XPOrbConfig.MAGNET_RADIUS * XPOrbConfig.MAGNET_RADIUS -- Compare squared distance (Optimization)

			for _, pData in ipairs(playerPositions) do
				local dx = pData.Position.X - orb.position.X
				local dy = pData.Position.Y - orb.position.Y
				local dz = pData.Position.Z - orb.position.Z
				local distSq = (dx*dx) + (dy*dy) + (dz*dz)

				if distSq < closestDistSq then
					closestDistSq = distSq
					closestData = pData
				end
			end

			if closestData then
				orb.magnetTarget = closestData.UserId -- Compatibility for collection
				orb.targetPlayer = closestData.Player -- Direct Ref for movement
			else
				orb.magnetTarget = nil
				orb.targetPlayer = nil
			end
		end
		
		-- Magnet Movement (Run every frame if we have a target)
		if orb.targetPlayer then
			local targetPlayer = orb.targetPlayer
			
			if targetPlayer.Parent and targetPlayer.Character then
				local root = targetPlayer.Character:FindFirstChild("HumanoidRootPart")
				if root then
					local targetPos = root.Position
					local dist = (targetPos - orb.position).Magnitude -- We need actual dist for speed calc

					if dist < XPOrbConfig.MAGNET_RADIUS then
						local direction = (targetPos - orb.position).Unit
						local speedAlpha = 1 - math.clamp(dist / XPOrbConfig.MAGNET_RADIUS, 0, 1)
						local currentSpeed = XPOrbConfig.MIN_MAGNET_SPEED + (XPOrbConfig.MAX_MAGNET_SPEED - XPOrbConfig.MIN_MAGNET_SPEED) * speedAlpha

						orb.position = orb.position + direction * currentSpeed * dt
					else
						orb.magnetTarget = nil
						orb.targetPlayer = nil
					end
				end
			else
				orb.magnetTarget = nil
				orb.targetPlayer = nil
			end
		end
	end
end

local ServiceBus = require(ServerScriptService.Services.ServiceBus)

-- ... (existing code)

-- Helper: Calculate dynamic collection range based on entity size
local function getCollectionRange(entity)
	local scale = entity:GetAttribute("Scale") or 1.0
	-- Base 30 + (Scale * 5)
	-- Scale 1 = 35 studs
	-- Scale 50 = 280 studs
	return 30 + (scale * 5)
end

-- Handle orb collection from client
local function onCollectOrb(player, orbId)
	local orb = activeOrbs[orbId]
	if not orb then
		return -- Orb already collected or doesn't exist
	end
	
	-- Validate proximity (anti-cheat)
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local dist = (player.Character.HumanoidRootPart.Position - orb.position).Magnitude
		
		local maxDist = getCollectionRange(player.Character)
		
		-- Magnet tolerance
		if orb.magnetTarget == player.UserId then
			maxDist = maxDist + 20 
		end
		
		if dist > maxDist then
			warn("⚠️ Player", player.Name, "tried to collect orb from too far away:", dist, "max:", maxDist)
			return
		end
	else
		return
	end
	
	-- Award XP via EventBus
	ServiceBus.Get("AwardBiomass"):Fire(player, orb.xpValue)
	
	-- Remove orb
	activeOrbs[orbId] = nil
	orbEvents:FireAllClients({Action = "Despawn", Id = orbId})
end

-- PUBLIC API: Server-side collection (for Bots)
function XPOrbService.CollectOrb(entity: Model, orbId: number)
	local orb = activeOrbs[orbId]
	if not orb then return false end -- Orb gone
	
	local root = entity:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	
	local dist = (root.Position - orb.position).Magnitude
	local maxDist = getCollectionRange(entity)
	
	if dist > maxDist then return false end 
	
	-- Award XP
	ServiceBus.Get("AwardBiomass"):Fire(entity, orb.xpValue)
	
	-- Remove
	activeOrbs[orbId] = nil
	orbEvents:FireAllClients({Action = "Despawn", Id = orbId})
	return true
end

-- PUBLIC API: Get nearest orb to a position
function XPOrbService.GetNearestOrb(position: Vector3, maxRange: number, excludeList: {[number]: boolean}?)
	local bestOrb = nil
	local bestDist = maxRange

	for _, orb in pairs(activeOrbs) do
		if excludeList and excludeList[orb.id] then continue end

		local dist = (orb.position - position).Magnitude
		if dist < bestDist then
			bestDist = dist
			bestOrb = {
				ID = orb.id,
				Position = orb.position,
				Name = "XPOrb", -- Compatibility for BotService
				XP = orb.xpValue
			}
		end
	end

	return bestOrb
end

-- PUBLIC API: Spawn drop at specific position
function XPOrbService.SpawnDrop(position: Vector3, totalXP: number)
	-- ... (existing logic)
    if totalXP <= 0 then return end

	local orbCount = math.clamp(math.ceil(totalXP / 100), 1, 10)
	local xpPerOrb = math.floor(totalXP / orbCount)

	for i = 1, orbCount do
		if #activeOrbs >= XPOrbConfig.MAX_ORBS then
			local oldestId = next(activeOrbs)
			if oldestId then
				activeOrbs[oldestId] = nil
				orbEvents:FireAllClients({Action = "Despawn", Id = oldestId})
			end
		end

		-- Determine tier
		local tier = XPOrbConfig.TIERS.Common
		if xpPerOrb >= 2000 then tier = XPOrbConfig.TIERS.Legendary
		elseif xpPerOrb >= 500 then tier = XPOrbConfig.TIERS.Rare
		elseif xpPerOrb >= 250 then tier = XPOrbConfig.TIERS.Uncommon
		end

		-- Scatter position
		local offset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
		local targetX = position.X + offset.X
		local targetZ = position.Z + offset.Z
		
		-- Raycast to find floor
		local rayOrigin = Vector3.new(targetX, position.Y + 20, targetZ)
		local rayDirection = Vector3.new(0, -100, 0)
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = {Players}
		
		local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		local yPos = position.Y
		if rayResult then
			yPos = rayResult.Position.Y
		end
		
		local spawnPos = Vector3.new(targetX, yPos + (tier.Size.Y / 2), targetZ)

		local orbId = nextOrbId
		nextOrbId = nextOrbId + 1

		activeOrbs[orbId] = {
			id = orbId,
			position = spawnPos,
			tier = tier,
			currentSize = tier.Size, -- Add currentSize to match spawnOrb structure
			xpValue = xpPerOrb,
			spawnTime = tick(),
			growthStage = 0, -- Add growthStage to prevent nil comparison error
			magnetTarget = nil,
			isDrop = true
		}

		-- Replicate
		orbEvents:FireAllClients({
			Action = "Spawn",
			Id = orbId,
			Position = spawnPos,
			Tier = {
				Name = tier.Name,
				Size = tier.Size,
				Color = tier.Color
			},
			XP = xpPerOrb,
			IsDrop = true
		})
	end
end

function XPOrbService.Start()
	print("--- Starting Optimized XPOrbService (Client Visuals) ---")
    
    -- Listen for SpawnXPOrbs event
    ServiceBus.Get("SpawnXPOrbs").Event:Connect(function(position, amount)
        XPOrbService.SpawnDrop(position, amount)
    end)

	-- Get remotes
	-- Get remotes
	print("XPOrbService: Waiting for Blaster folder...")
	local blaster = ReplicatedStorage:WaitForChild("Blaster", 10)
	if not blaster then
		warn("❌ XPOrbService: Could not find ReplicatedStorage.Blaster!")
		return
	end
	
	print("XPOrbService: Waiting for Remotes folder...")
	local remotes = blaster:WaitForChild("Remotes", 10)
	if not remotes then
		warn("❌ XPOrbService: Could not find Blaster.Remotes!")
		return
	end
	
	print("XPOrbService: Waiting for OrbEvents...")
	orbEvents = remotes:WaitForChild("OrbEvents", 10)
	if not orbEvents then
		warn("❌ XPOrbService: Could not find OrbEvents remote!")
		return
	end
	
	collectOrbRemote = remotes:WaitForChild("CollectOrb", 10)


	-- Listen for collections
	collectOrbRemote.OnServerEvent:Connect(onCollectOrb)

	-- Single Heartbeat loop for all orbs
	RunService.Heartbeat:Connect(updateOrbs)

	-- Spawn loop
	task.spawn(function()
		while true do
			spawnOrb()
			task.wait(XPOrbConfig.SPAWN_INTERVAL)
		end
	end)
	
	print("✅ XPOrbService: Using client-side rendering (0 server Parts)")
end

return XPOrbService
