--[[
    Module: BotController
    Description:
        Optimized Bot AI with Pathfinding, Spatial Queries, and Network Ownership Transfer.
        Implements distributed updates for performance and instant combat reaction.
        Non-blocking pathfinding to prevent frame drops.

    Dependencies:
    - PathfindingService, CollectionService, RunService
    - ScalingConfig, castRays, ProgressionManager, DamageTracker

    Author: Jules (Optimized)
    Last Updated: 2025-01-22
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local SafeZoneConfig = require(ReplicatedStorage.GameLoop.SafeZoneConfig)
local ScalingEngine = require(ServerScriptService.Services.World.ScalingEngineService)
local DamageTracker = require(ServerScriptService.Services.World.DamageTrackerService)
local MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
local castRays = require(ServerScriptService.Utility.castRays)
local ProgressionManager = require(ServerScriptService.Services.Progression.ProgressionService)
local XPOrbService = require(ServerScriptService.Services.World.XPOrbService)

-- === Constants ===
local UPDATE_INTERVAL = 10 -- Run AI logic every 10 frames (approx 6 times/sec)
local AGGRO_DURATION = 8
local NETWORK_OWNERSHIP_RADIUS = 200 -- Transfer ownership if player is within 200 studs
local ORB_SEARCH_INTERVAL = 0.1 -- Search for orbs very frequently
local STUCK_THRESHOLD = 0.5
local STUCK_TIME = 1.0
local IDLE_TIMEOUT = 2.0 -- Max seconds a bot can be idle without any movement command
local REACTION_TIME = 1.2 -- Delay before shooting after acquiring target (Increased for easier difficulty)

-- === Events ===
local eliminatedEvent
task.spawn(function()
	eliminatedEvent = ServerScriptService:WaitForChild("Blaster", 10):WaitForChild("Events"):WaitForChild("Eliminated", 10)
end)

local replicateShotRemote
task.spawn(function()
	replicateShotRemote = ReplicatedStorage:WaitForChild("Blaster", 10):WaitForChild("Remotes"):WaitForChild("ReplicateShot", 10)
end)

local BotController = {}

-- Optimization: Shared RaycastParams to prevent GC thrashing
local sharedRayParams = RaycastParams.new()
sharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
sharedRayParams.RespectCanCollide = true

-- Optimization: Cache Orb Folder to avoid Finding it every frame
local orbFolder = Workspace:WaitForChild("Orbs", 5)

-- === State Management ===
-- Storing state locally for speed
local botStates: { [Model]: BotState } = {}
-- botStates[bot] = {
--    Target = Instance | nil,
--    State = "IDLE" | "COMBAT" | "ORB",
--    NextOrbSearch = number,
--    Path = Path | nil,
--    PathWaypoints = {} | nil,
--    CurrentWaypointIndex = 1,
--    IsPathfinding = boolean,
--    LastPathTime = number,
--    LastPos = Vector3,
--    LastMoveTime = number,
--    StuckSince = number | nil,
--    AggroTable = { [player] = timestamp },
--    LastShot = number,
--    StrafeDir = 1,
--    NextStrafeChange = number
-- }

type BotState = {
	Target: Instance | {ID: number?, Position: Vector3, Name: string, XP: number} | nil,
	State: "IDLE" | "COMBAT" | "ORB",
	NextOrbSearch: number,
	AggroTable: { [Instance]: number },
	LastPos: Vector3,
	LastMoveTime: number,
	StuckSince: number?,
	LastShot: number,
	StrafeDir: number,
	NextStrafeChange: number,
	IsPathfinding: boolean,
	LastPathTime: number,
	Path: Path?,
	PathWaypoints: {PathWaypoint}?,
	CurrentWaypointIndex: number?,
	TargetAcquiredTime: number,
	OrbBlacklist: { [number]: number }, -- [OrbID] = timestamp
	LastMoveToPos: Vector3?, -- Track last MoveTo position to avoid spam
	LastMoveToTime: number, -- Track when we last called MoveTo
}

-- Initialize State
local function getBotState(bot)
	if not botStates[bot] then
		botStates[bot] = {
			Target = nil,
			State = "IDLE",
			NextOrbSearch = 0,
			AggroTable = {},
			LastPos = bot.PrimaryPart and bot.PrimaryPart.Position or Vector3.zero,
			LastMoveTime = os.clock(),
			StuckSince = nil,
			LastShot = 0,
			StrafeDir = 1,
			NextStrafeChange = 0,
			IsPathfinding = false,
			LastPathTime = 0,
			TargetAcquiredTime = 0,
			OrbBlacklist = {},
			LastMoveToPos = nil,
			LastMoveToTime = 0,
		}
	end
	return botStates[bot]
end

-- Throttled MoveTo to prevent stuttering
-- Only issues a new MoveTo if position changed significantly or enough time passed
local MOVE_TO_MIN_INTERVAL = 0.15 -- Minimum time between MoveTo calls
local MOVE_TO_MIN_DISTANCE = 3 -- Minimum distance change to trigger new MoveTo
local MOVE_TO_REFRESH_INTERVAL = 1.0 -- Force refresh MoveTo even for stationary targets

local function throttledMoveTo(hum, state, targetPos)
	local now = os.clock()
	local shouldMove = false
	
	-- Always move if we haven't moved yet
	if not state.LastMoveToPos then
		shouldMove = true
	-- Move if enough time has passed
	elseif now - state.LastMoveToTime > MOVE_TO_MIN_INTERVAL then
		-- Check if target position changed significantly
		local distChange = (targetPos - state.LastMoveToPos).Magnitude
		if distChange > MOVE_TO_MIN_DISTANCE then
			shouldMove = true
		-- Force refresh for stationary targets to prevent bots from stopping
		elseif now - state.LastMoveToTime > MOVE_TO_REFRESH_INTERVAL then
			shouldMove = true
		end
	end
	
	if shouldMove then
		hum:MoveTo(targetPos)
		state.LastMoveToPos = targetPos
		state.LastMoveToTime = now
	end
end

-- === Helper: Network Ownership ===
local function updateNetworkOwnership(bot, target)
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local newOwner = nil
	local shortestDist = NETWORK_OWNERSHIP_RADIUS

	-- Priority 1: The Target (if it's a player)
	if target and typeof(target) == "Instance" and target:IsA("Model") then
		local player = Players:GetPlayerFromCharacter(target)
		if player then
			local targetRoot = target:FindFirstChild("HumanoidRootPart")
			if targetRoot then
				local dist = (targetRoot.Position - root.Position).Magnitude
				if dist < NETWORK_OWNERSHIP_RADIUS then
					newOwner = player
				end
			end
		end
	end

	-- Priority 2: Any nearby player (if no target or target is bot)
	if not newOwner then
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				local dist = (player.Character.HumanoidRootPart.Position - root.Position).Magnitude
				if dist < shortestDist then
					shortestDist = dist
					newOwner = player
				end
			end
		end
	end

	-- Apply Ownership
	if root:IsDescendantOf(Workspace) and not root.Anchored then
		local success, currentOwner = pcall(function() return root:GetNetworkOwner() end)
		if success and currentOwner ~= newOwner then
			pcall(function() root:SetNetworkOwner(newOwner) end)
		end
	end
end

-- === Helper: Safe Zone Check ===
-- Returns nil if not in safezone, or a position to move to if in safezone
local function getEscapeSafeZoneTarget(position: Vector3): Vector3?
	for _, zonePos in ipairs(SafeZoneConfig.SAFE_ZONE_LOCATIONS) do
		local size = SafeZoneConfig.SAFE_ZONE_SIZE
		local relX = position.X - zonePos.X
		local relZ = position.Z - zonePos.Z
		
		-- Check if inside this zone (AABB)
		if math.abs(relX) <= size.X / 2 and math.abs(relZ) <= size.Z / 2 then
			-- Inside! Calculate escape direction (move away from zone center)
			local escapeDir = Vector3.new(relX, 0, relZ)
			if escapeDir.Magnitude < 1 then
				-- Too close to center, pick random direction
				escapeDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			end
			escapeDir = escapeDir.Unit
			
			-- Target position: just outside the zone
			local escapeDistance = math.max(size.X, size.Z) / 2 + 50
			return position + escapeDir * escapeDistance
		end
	end
	return nil -- Not in any safezone
end

-- === Helper: Spatial Orb Search ===
local function findNearestOrb(bot, state, range)
	local root = bot.PrimaryPart
	if not root then return nil end

	-- Use Optimized XPOrbService (Data-only query, no physics)
	return XPOrbService.GetNearestOrb(root.Position, range, state.OrbBlacklist)
end

-- === Helper: Target Validation & Scoring ===
local function isValidTarget(bot, target)
	if not target then return false end
	
	-- Handle Orb Data (Table)
	if typeof(target) == "table" and target.Name == "XPOrb" then
		return true
	end
	
	-- Handle Instances (Players/Bots)
	if typeof(target) == "Instance" then
		if not target.Parent then return false end
		local hum = target:FindFirstChild("Humanoid")
		if not hum or hum.Health <= 0 then return false end
		return true
	end
	
	return false
end

-- === Helper: Find Nearest Enemy ===
local function findNearestEnemy(bot, range)
	local root = bot.PrimaryPart
	if not root then return nil end
	
	local bestTarget = nil
	local bestDist = range
	
	-- 1. Check other Bots (Only target bots actively)
	for _, otherBot in ipairs(CollectionService:GetTagged("BotAI")) do
		if otherBot ~= bot and isValidTarget(bot, otherBot) then
			local dist = (otherBot.PrimaryPart.Position - root.Position).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestTarget = otherBot
			end
		end
	end
	
	return bestTarget
end

-- === Pathfinding ===
local function moveToPath(bot, state, targetPos)
	local root = bot.PrimaryPart
	local hum = bot:FindFirstChild("Humanoid")
	if not root or not hum then return end

	-- Update Waypoint Logic
	if state.Path and state.PathWaypoints and state.CurrentWaypointIndex <= #state.PathWaypoints then
		local waypoint = state.PathWaypoints[state.CurrentWaypointIndex]

		-- Check if we reached the waypoint
		local distToWaypoint = (root.Position - waypoint.Position).Magnitude
		local botRadius = 2 * ScalingConfig.GetSizeMultiplier(bot:GetAttribute("Level") or 1)

		if distToWaypoint < (botRadius + 2) then
			-- Reached, move to next
			state.CurrentWaypointIndex = state.CurrentWaypointIndex + 1
			if state.CurrentWaypointIndex <= #state.PathWaypoints then
				-- Force immediate MoveTo for waypoint transitions
				hum:MoveTo(state.PathWaypoints[state.CurrentWaypointIndex].Position)
				state.LastMoveToPos = state.PathWaypoints[state.CurrentWaypointIndex].Position
				state.LastMoveToTime = os.clock()

				-- Jump if needed
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					hum.Jump = true
				end
			else
				-- End of path, move directly to target
				throttledMoveTo(hum, state, targetPos)
				state.Path = nil
			end
		else
			-- Continue to current waypoint (throttled)
			throttledMoveTo(hum, state, waypoint.Position)
		end
	else
		-- No path, create one?
		-- Only create path if direct line is blocked (Optimization)
		local direction = (targetPos - root.Position)
		local distance = direction.Magnitude

		local botLevel = bot:GetAttribute("Level") or 1
		local botRadius = 2 * ScalingConfig.GetSizeMultiplier(botLevel)

		-- Optimization: Reuse shared RaycastParams
		sharedRayParams.FilterDescendantsInstances = { bot, orbFolder or Workspace:FindFirstChild("Orbs") }

		-- Use Spherecast to account for bot width (Reduced radius for leniency)
		local blocked = Workspace:Spherecast(root.Position, botRadius * 0.75, direction.Unit * math.min(distance, 50), sharedRayParams)

		-- Fix: Ignore floor/slopes
		if blocked and blocked.Normal.Y > 0.5 then
			blocked = nil
		end

		if blocked then
			-- Blocked
			
			-- 1. Check if already pathfinding or cooldown
			if state.IsPathfinding then
				-- Keep moving towards target while waiting (throttled)
				throttledMoveTo(hum, state, targetPos)
				return
			end
			if os.clock() - state.LastPathTime < 1.0 then
				-- On cooldown: Just move directly (throttled) instead of stopping
				-- This prevents stuttering if the block is minor or a false positive
				throttledMoveTo(hum, state, targetPos)
				return
			end

			-- 2. Start Async Pathfinding
			state.IsPathfinding = true
			state.LastPathTime = os.clock()

			local agentRadius = 2 * ScalingConfig.GetSizeMultiplier(botLevel)
			local agentHeight = 5 * ScalingConfig.GetSizeMultiplier(botLevel)
			local startPos = root.Position

			task.spawn(function()
				local path = PathfindingService:CreatePath({
					AgentRadius = agentRadius,
					AgentHeight = agentHeight,
					AgentCanJump = true,
					Costs = {
						Water = 20
					}
				})

				local success, errorMessage = pcall(function()
					path:ComputeAsync(startPos, targetPos)
				end)

				if success and path.Status == Enum.PathStatus.Success then
					if botStates[bot] then -- Ensure bot still exists
						state.Path = path
						state.PathWaypoints = path:GetWaypoints()
						state.CurrentWaypointIndex = 2 -- Skip first (current pos)
					end
				end

				if botStates[bot] then
					state.IsPathfinding = false
				end
			end)

			-- While waiting, continue moving directly (throttled)
			throttledMoveTo(hum, state, targetPos)
		else
			-- Clear, move directly (throttled)
			throttledMoveTo(hum, state, targetPos)
			state.Path = nil -- Clear old path
		end
	end
end

-- === Combat Logic ===
local function handleCombat(bot, state, now)
	local target = state.Target
	if not isValidTarget(bot, target) then
		state.Target = nil
		state.State = "IDLE"
		state.Path = nil
		state.NextOrbSearch = 0
		state.LastMoveToPos = nil -- Force immediate movement on next update
		state.LastMoveToTime = 0
		return
	end

	local root = bot.PrimaryPart
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not root or not targetRoot then return end

	local dist = (targetRoot.Position - root.Position).Magnitude

	-- Movement: Strafe or Chase
	local hum = bot:FindFirstChild("Humanoid")
	if not hum then return end
	
	if dist < 30 then
		-- Close range: Strafe
		if now > state.NextStrafeChange then
			state.StrafeDir = -state.StrafeDir
			state.NextStrafeChange = now + math.random(2, 4)
		end
		
		local toEnemy = (targetRoot.Position - root.Position).Unit
		local right = Vector3.new(-toEnemy.Z, 0, toEnemy.X)
		local strafePos = root.Position + (right * state.StrafeDir * 10) + (toEnemy * math.random(-5, 5))
		
		-- Use throttled move to prevent stuttering
		throttledMoveTo(hum, state, strafePos)
	else
		-- Long range: Chase
		moveToPath(bot, state, targetRoot.Position)
	end

	-- Shooting Logic
	-- Check cooldown and reaction time
	if now - state.LastShot > 0.35 and now - state.TargetAcquiredTime > REACTION_TIME then -- Fire rate limit & Reaction time (Slowed down for easier difficulty)

		-- Raycast for LOS
		local origin = bot.Head.Position
		local targetHead = target:FindFirstChild("Head") or targetRoot
		local aimPos = targetHead.Position

		-- Add Inaccuracy
		-- Increased spread to prevent "perfect aim" (Further increased for easier difficulty)
		local spread = math.clamp(dist / 12, 3.0, 10.0) -- Increased base spread
		local inaccuracy = Vector3.new(
			math.random() - 0.5,
			math.random() - 0.5,
			math.random() - 0.5
		) * spread
		
		local dir = ((aimPos + inaccuracy) - origin).Unit * 300
		
		-- Check LOS before firing to save Raycasts? No, castRays handles it.
		-- Actually, we should check if we are shooting a wall

		-- Optimization: Use shared RaycastParams
		sharedRayParams.FilterDescendantsInstances = { bot }

		local los = Workspace:Raycast(origin, (aimPos - origin).Unit * dist, sharedRayParams)
		if not los or los.Instance:IsDescendantOf(target) then
			-- Clear shot
			state.LastShot = now

			-- Fire
			local results = castRays(bot, origin, { dir }, 1)

			-- Replicate shot visuals to all clients
			-- Format as: { {tool, origin, results}, ... }
			if replicateShotRemote then
				-- Convert results to proper format for client
				local clientResults = {}
				for _, hit in ipairs(results) do
					table.insert(clientResults, {
						position = hit.position,
						normal = hit.normal or Vector3.yAxis,
						instance = hit.instance,
						taggedHumanoid = hit.taggedHumanoid
					})
				end
				
				-- Send in batch format expected by client
				replicateShotRemote:FireAllClients({
					{
						tool = bot:FindFirstChildWhichIsA("Tool"),
						origin = origin,
						results = clientResults
					}
				})
			end

			-- Damage
			for _, hit in ipairs(results) do
				if hit.taggedHumanoid then
					local baseDamage = 6 * ScalingConfig.GetDamageMultiplier(bot:GetAttribute("Level") or 1) -- Reduced damage for easier difficulty
					hit.taggedHumanoid:TakeDamage(baseDamage)
					DamageTracker.RecordDamage(bot, hit.taggedHumanoid.Parent, baseDamage)

					if hit.taggedHumanoid.Health <= 0 and eliminatedEvent then
						eliminatedEvent:Fire(nil, bot, hit.taggedHumanoid.Parent, bot:FindFirstChildWhichIsA("Tool"))
						ProgressionManager.AddBiomass(bot, 50)
					end
				end
			end
		end
	end
end

-- === Public API: Aggro ===
function BotController.RecordAggro(bot, attacker)
	if not bot or not attacker then return end
	
	-- Normalize attacker to character model
	local attackerChar = nil
	if typeof(attacker) == "Instance" then
		if attacker:IsA("Player") then
			attackerChar = attacker.Character
		elseif CollectionService:HasTag(attacker, "BotAI") then
			attackerChar = attacker
		end
	end
	
	-- Validate we have a valid character
	if not attackerChar or not isValidTarget(bot, attackerChar) then
		return
	end
	
	local state = getBotState(bot)
	local now = os.clock()
	
	-- Record timestamp (store character, not player object)
	state.AggroTable[attackerChar] = now
	
	-- Instant Reaction: Switch target immediately if not already locked on a player
	local currentTargetIsPlayer = state.Target and typeof(state.Target) == "Instance" and Players:GetPlayerFromCharacter(state.Target)

	if not currentTargetIsPlayer then
		state.Target = attackerChar
		state.State = "COMBAT"
		state.Path = nil -- Clear old path
		state.TargetAcquiredTime = now
		-- print("Bot " .. bot.Name .. " instantly reacted to " .. attackerChar.Name)
	end
end


-- === Main Loop ===
function BotController.Start()
	print("--- Starting Optimized BotController ---")

	local frameCount = 0

	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		frameCount = frameCount + 1

		local bots = CollectionService:GetTagged("BotAI")

		for i, bot in ipairs(bots) do
			local hum = bot:FindFirstChild("Humanoid")
			local root = bot:FindFirstChild("HumanoidRootPart")

			if not hum or hum.Health <= 0 or not root then
				botStates[bot] = nil
				continue
			end

			local state = getBotState(bot)

			-- 1. Network Ownership (Frequent Check for Smoothness)
			-- Distribute this check: 1/10th of bots per frame
			if (i + frameCount) % 10 == 0 then
				updateNetworkOwnership(bot, state.Target)
			end

			-- 2. AI Decision Throttling
			-- Distribute updates: Only update if it's this bot's turn in the bucket
			-- HOWEVER: If State is COMBAT, we allow pass-through to the high-freq combat check
			if (i + frameCount) % UPDATE_INTERVAL ~= 0 and state.State ~= "COMBAT" then
				continue
			end

			-- High Frequency Combat Checks (Every 3 frames for combat bots)
			if state.State == "COMBAT" and (i + frameCount) % 3 == 0 then
				handleCombat(bot, state, now)
				continue
			end

			-- 3. Main State Machine (Low Frequency / Fallthrough)

			-- Clean Aggro
			for attacker, time in pairs(state.AggroTable) do
				local targetEntity = attacker
				if attacker:IsA("Player") then
					targetEntity = attacker.Character
				end

				-- Remove if expired OR if target is dead/invalid
				if (now - time > AGGRO_DURATION) or not isValidTarget(bot, targetEntity) then
					state.AggroTable[attacker] = nil
				end
			end

			-- Clean Blacklist
			for id, time in pairs(state.OrbBlacklist) do
				if now - time > 15 then -- Blacklist duration: 15 seconds
					state.OrbBlacklist[id] = nil
				end
			end

			-- Give Up Logic (Unreachable Orbs)
			if (state.State :: any) == "ORB" and state.Target and state.Target.ID then
				if now - state.TargetAcquiredTime > 5.0 then -- Give up after 5 seconds
					-- Blacklist this orb
					state.OrbBlacklist[state.Target.ID] = now
					
					-- Reset
					state.State = "IDLE"
					state.Target = nil
					state.Path = nil
					state.NextOrbSearch = 0 -- Search again immediately (for a different orb)
					continue
				end
			end

			-- Stuck Detection (bot trying to move but can't)
			local moved = (root.Position - state.LastPos).Magnitude
			if moved < STUCK_THRESHOLD and hum.MoveDirection.Magnitude > 0.1 then
				if not state.StuckSince then state.StuckSince = now end
				if now - state.StuckSince > STUCK_TIME then
					-- Unstick: Jump and random move
					hum.Jump = true
					local randomDir = Vector3.new(math.random()-0.5, 0, math.random()-0.5).Unit * 15
					hum:MoveTo(root.Position + randomDir)
					state.Path = nil -- Reset path
					state.StuckSince = nil -- Reset and wait
					state.LastMoveToPos = nil -- Force new movement command
					state.LastMoveToTime = 0
					state.LastPos = root.Position
					continue
				end
			else
				state.StuckSince = nil
			end
			
			-- Idle Timeout Detection (bot has no movement command at all)
			-- This catches bots that are completely frozen with MoveDirection = 0
			if moved < STUCK_THRESHOLD and hum.MoveDirection.Magnitude < 0.1 then
				-- Bot is stationary AND not trying to move - force recovery
				if now - state.LastMoveToTime > IDLE_TIMEOUT then
					-- Force a wander command to wake up the bot
					local randomDir = Vector3.new(math.random()-0.5, 0, math.random()-0.5).Unit * 20
					local wanderPos = root.Position + randomDir
					hum:MoveTo(wanderPos)
					state.LastMoveToPos = wanderPos
					state.LastMoveToTime = now
					state.Path = nil
					state.IsPathfinding = false -- Reset pathfinding state
					-- Also reset state to IDLE if stuck in a bad state
					if state.State == "ORB" and state.Target then
						-- Blacklist the orb we couldn't reach
						if state.Target.ID then
							state.OrbBlacklist[state.Target.ID] = now
						end
						state.State = "IDLE"
						state.Target = nil
					end
				end
			end
			state.LastPos = root.Position

			-- Safe Zone Escape: Bots should not stay in safe zones
			local escapeTarget = getEscapeSafeZoneTarget(root.Position)
			if escapeTarget then
				-- Bot is in a safe zone! Force it to leave
				moveToPath(bot, state, escapeTarget)
				state.State = "IDLE" -- Reset state while escaping
				state.Target = nil
				continue -- Skip normal AI this frame, focus on escaping
			end
			
			-- Target Selection
			if state.State == "COMBAT" then
				if not isValidTarget(bot, state.Target) then
					state.State = "IDLE"
					state.Target = nil
					state.Path = nil
					state.NextOrbSearch = 0
					state.LastMoveToPos = nil -- Force immediate movement
					state.LastMoveToTime = 0
				end
			end

			if (state.State :: any) == "IDLE" or (state.State :: any) == "ORB" then
				-- Look for Aggro Targets first
				local bestAggro = nil
				local bestTime = 0
				for attacker, time in pairs(state.AggroTable) do
					if time > bestTime and isValidTarget(bot, attacker) then
						bestAggro = attacker
						bestTime = time
					end
				end
				
				if bestAggro then
					state.Target = bestAggro
					state.State = "COMBAT"
					state.TargetAcquiredTime = now
				else
					-- NEW: Active Enemy Search
					local enemy = findNearestEnemy(bot, 80) -- 80 stud view range
					if enemy then
						state.Target = enemy
						state.State = "COMBAT"
						state.TargetAcquiredTime = now
					else
						-- Look for Orbs
						if now > state.NextOrbSearch then
							local level = bot:GetAttribute("Level") or 1
							local searchRange = 1000 * ScalingConfig.GetSizeMultiplier(level)
							local orb = findNearestOrb(bot, state, searchRange)

							if orb then
								state.State = "ORB"
								state.Target = orb
								state.TargetAcquiredTime = now -- Track when we started chasing this orb
								-- Move to orb
								moveToPath(bot, state, orb.Position)
							end
							state.NextOrbSearch = now + ORB_SEARCH_INTERVAL
						elseif (state.State :: any) == "IDLE" then
							-- Idle logic
						end
						
						if (state.State :: any) == "ORB" and state.Target then
							-- Continue moving to orb
							local targetPos = state.Target.Position
							if (targetPos - root.Position).Magnitude < 30 then
								-- Attempt collection
								if state.Target.ID then
									local collected = XPOrbService.CollectOrb(bot, state.Target.ID)
									if collected then
										state.State = "IDLE"
										state.Target = nil
									end
								end
							else
								moveToPath(bot, state, targetPos)
							end
						elseif (state.State :: any) == "IDLE" then
							-- Idle wandering: pick a random nearby position and walk there
							-- This prevents bots from standing completely still
							-- Reduced timeout from 3s to 1.5s for more responsive wandering
							if not state.LastMoveToPos or (root.Position - state.LastMoveToPos).Magnitude < 5 or now - state.LastMoveToTime > 1.5 then
								local wanderDist = 30
								local randomDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
								local wanderPos = root.Position + randomDir * wanderDist
								throttledMoveTo(hum, state, wanderPos)
							end
						end
					end
				end
			end
		end
	end)
end

return BotController
