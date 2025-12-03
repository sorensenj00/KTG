--[[
    Module: BotController
    Description:
        Bot AI prioritizing CONSTANT MOVEMENT for map life.
        Bots are always walking somewhere - wandering, chasing orbs, or fighting.
        Simplified pathfinding with aggressive fallbacks for cluttered environments.

    Dependencies:
    - PathfindingService, CollectionService, RunService
    - ScalingConfig, castRays, ProgressionManager, DamageTracker

    Author: Jules (Movement-First Rewrite)
    Last Updated: 2025-12-03
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

-- === Constants (Tuned for constant movement) ===
local UPDATE_INTERVAL = 5 -- Run AI logic every 5 frames (~12 times/sec) - MORE RESPONSIVE
local AGGRO_DURATION = 8
local NETWORK_OWNERSHIP_RADIUS = 200
local ORB_SEARCH_INTERVAL = 0.5 -- Check for orbs less frequently to prioritize wandering
local REACTION_TIME = 1.2

-- Movement Constants
local STUCK_THRESHOLD = 0.3 -- Smaller = detect stuck faster
local STUCK_TIME = 0.5 -- Recover from stuck in 0.5 seconds (was 1.0)
local IDLE_TIMEOUT = 0.8 -- Force movement after 0.8s of no movement (was 2.0)
local WANDER_DISTANCE_MIN = 40 -- Minimum wander distance
local WANDER_DISTANCE_MAX = 80 -- Maximum wander distance  
local WANDER_ARRIVAL_DIST = 8 -- How close to get before picking new destination
local PATH_FAIL_SIDESTEP = 20 -- Sidestep distance when path fails

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

-- Shared RaycastParams
local sharedRayParams = RaycastParams.new()
sharedRayParams.FilterType = Enum.RaycastFilterType.Exclude
sharedRayParams.RespectCanCollide = true

-- Cache Orb Folder
local orbFolder = Workspace:WaitForChild("Orbs", 5)

-- === State Management ===
local botStates: { [Model]: BotState } = {}

type BotState = {
	Target: Instance | {ID: number?, Position: Vector3, Name: string, XP: number} | nil,
	State: "WANDER" | "COMBAT" | "ORB",
	WanderDestination: Vector3?, -- Current wander target
	WanderStartTime: number, -- When we started walking to current destination
	NextOrbSearch: number,
	AggroTable: { [Instance]: number },
	LastPos: Vector3,
	LastMoveTime: number,
	StuckSince: number?,
	StuckRecoveryAttempts: number, -- Track how many times we've tried to unstick
	LastShot: number,
	StrafeDir: number,
	NextStrafeChange: number,
	IsPathfinding: boolean,
	LastPathTime: number,
	Path: Path?,
	PathWaypoints: {PathWaypoint}?,
	CurrentWaypointIndex: number?,
	TargetAcquiredTime: number,
	OrbBlacklist: { [number]: number },
	LastMoveToPos: Vector3?,
	LastMoveToTime: number,
	PathFailCount: number, -- Track consecutive path failures
}

-- Initialize State
local function getBotState(bot)
	if not botStates[bot] then
		botStates[bot] = {
			Target = nil,
			State = "WANDER", -- Start in WANDER state, not IDLE
			WanderDestination = nil,
			WanderStartTime = 0,
			NextOrbSearch = 0,
			AggroTable = {},
			LastPos = bot.PrimaryPart and bot.PrimaryPart.Position or Vector3.zero,
			LastMoveTime = os.clock(),
			StuckSince = nil,
			StuckRecoveryAttempts = 0,
			LastShot = 0,
			StrafeDir = 1,
			NextStrafeChange = 0,
			IsPathfinding = false,
			LastPathTime = 0,
			TargetAcquiredTime = 0,
			OrbBlacklist = {},
			LastMoveToPos = nil,
			LastMoveToTime = 0,
			PathFailCount = 0,
		}
	end
	return botStates[bot]
end

-- === Helper: Pick Random Wander Destination ===
local function pickWanderDestination(bot, state)
	local root = bot.PrimaryPart
	if not root then return nil end
	
	local botLevel = bot:GetAttribute("Level") or 1
	local sizeMultiplier = ScalingConfig.GetSizeMultiplier(botLevel)
	
	-- Scale wander distance with bot size
	local wanderDist = math.random(WANDER_DISTANCE_MIN, WANDER_DISTANCE_MAX) * math.max(1, sizeMultiplier * 0.5)
	
	-- Pick random angle
	local angle = math.random() * math.pi * 2
	local offsetX = math.cos(angle) * wanderDist
	local offsetZ = math.sin(angle) * wanderDist
	
	local targetPos = root.Position + Vector3.new(offsetX, 0, offsetZ)
	
	-- Raycast down to find ground
	sharedRayParams.FilterDescendantsInstances = { bot, orbFolder or Workspace:FindFirstChild("Orbs") }
	local groundRay = Workspace:Raycast(
		Vector3.new(targetPos.X, root.Position.Y + 50, targetPos.Z),
		Vector3.new(0, -200, 0),
		sharedRayParams
	)
	
	if groundRay then
		return Vector3.new(targetPos.X, groundRay.Position.Y + 3, targetPos.Z)
	else
		-- No ground found, just use flat position
		return Vector3.new(targetPos.X, root.Position.Y, targetPos.Z)
	end
end

-- === Helper: Force Movement (Guaranteed to issue a MoveTo) ===
local function forceMoveTo(hum, state, targetPos)
	hum:MoveTo(targetPos)
	state.LastMoveToPos = targetPos
	state.LastMoveToTime = os.clock()
end

-- === Helper: Smart Movement (with minimal throttling) ===
local MOVE_TO_MIN_INTERVAL = 0.1 -- Reduced from 0.15

local function smartMoveTo(hum, state, targetPos)
	local now = os.clock()
	
	-- Always move if enough time passed or no previous movement
	if not state.LastMoveToPos or now - state.LastMoveToTime > MOVE_TO_MIN_INTERVAL then
		forceMoveTo(hum, state, targetPos)
	end
end

-- === Helper: Network Ownership ===
local function updateNetworkOwnership(bot, target)
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local newOwner = nil
	local shortestDist = NETWORK_OWNERSHIP_RADIUS

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

	if root:IsDescendantOf(Workspace) and not root.Anchored then
		local success, currentOwner = pcall(function() return root:GetNetworkOwner() end)
		if success and currentOwner ~= newOwner then
			pcall(function() root:SetNetworkOwner(newOwner) end)
		end
	end
end

-- === Helper: Safe Zone Check ===
local function getEscapeSafeZoneTarget(position: Vector3): Vector3?
	for _, zonePos in ipairs(SafeZoneConfig.SAFE_ZONE_LOCATIONS) do
		local size = SafeZoneConfig.SAFE_ZONE_SIZE
		local relX = position.X - zonePos.X
		local relZ = position.Z - zonePos.Z
		
		if math.abs(relX) <= size.X / 2 and math.abs(relZ) <= size.Z / 2 then
			local escapeDir = Vector3.new(relX, 0, relZ)
			if escapeDir.Magnitude < 1 then
				escapeDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
			end
			escapeDir = escapeDir.Unit
			local escapeDistance = math.max(size.X, size.Z) / 2 + 50
			return position + escapeDir * escapeDistance
		end
	end
	return nil
end

-- === Helper: Spatial Orb Search ===
local function findNearestOrb(bot, state, range)
	local root = bot.PrimaryPart
	if not root then return nil end
	return XPOrbService.GetNearestOrb(root.Position, range, state.OrbBlacklist)
end

-- === Helper: Target Validation ===
local function isValidTarget(bot, target)
	if not target then return false end
	
	if typeof(target) == "table" and target.Name == "XPOrb" then
		return true
	end
	
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
	
	for _, otherBot in ipairs(CollectionService:GetTagged("BotAI")) do
		if otherBot ~= bot and isValidTarget(bot, otherBot) then
			local otherRoot = otherBot.PrimaryPart
			if otherRoot then
				local dist = (otherRoot.Position - root.Position).Magnitude
				if dist < bestDist then
					bestDist = dist
					bestTarget = otherBot
				end
			end
		end
	end
	
	return bestTarget
end

-- === Simplified Movement (Prioritize moving over perfect paths) ===
local function moveTowardTarget(bot, state, targetPos, allowPathfinding)
	local root = bot.PrimaryPart
	local hum = bot:FindFirstChild("Humanoid")
	if not root or not hum then return end
	
	local now = os.clock()
	local direction = (targetPos - root.Position)
	local distance = direction.Magnitude
	
	-- If we have an active path, follow it
	if state.Path and state.PathWaypoints and state.CurrentWaypointIndex and state.CurrentWaypointIndex <= #state.PathWaypoints then
		local waypoint = state.PathWaypoints[state.CurrentWaypointIndex]
		local distToWaypoint = (root.Position - waypoint.Position).Magnitude
		local botRadius = 2 * ScalingConfig.GetSizeMultiplier(bot:GetAttribute("Level") or 1)
		
		if distToWaypoint < (botRadius + 4) then
			-- Reached waypoint, move to next
			state.CurrentWaypointIndex = state.CurrentWaypointIndex + 1
			if state.CurrentWaypointIndex <= #state.PathWaypoints then
				forceMoveTo(hum, state, state.PathWaypoints[state.CurrentWaypointIndex].Position)
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					hum.Jump = true
				end
			else
				-- Path complete
				state.Path = nil
				state.PathWaypoints = nil
				state.PathFailCount = 0
			end
		else
			smartMoveTo(hum, state, waypoint.Position)
		end
		return
	end
	
	-- No path - try direct movement first (ALWAYS prefer moving)
	local botLevel = bot:GetAttribute("Level") or 1
	local botRadius = 2 * ScalingConfig.GetSizeMultiplier(botLevel)
	
	-- Simple raycast check (not spherecast - too strict in cluttered maps)
	sharedRayParams.FilterDescendantsInstances = { bot, orbFolder or Workspace:FindFirstChild("Orbs") }
	local checkDist = math.min(distance, 15) -- Only check short distance ahead
	local blocked = Workspace:Raycast(root.Position + Vector3.new(0, 2, 0), direction.Unit * checkDist, sharedRayParams)
	
	-- Ignore floors/slopes (normal pointing up)
	if blocked and blocked.Normal.Y > 0.4 then
		blocked = nil
	end
	
	if not blocked or distance < 10 then
		-- Path is clear OR we're close enough to just go for it
		smartMoveTo(hum, state, targetPos)
		state.Path = nil
		state.PathFailCount = 0
		return
	end
	
	-- Path is blocked - try alternatives before pathfinding
	state.PathFailCount = (state.PathFailCount or 0) + 1
	
	-- Alternative 1: Sidestep (try going around the obstacle)
	if state.PathFailCount <= 3 then
		local right = Vector3.new(-direction.Unit.Z, 0, direction.Unit.X)
		local sideDir = (state.PathFailCount % 2 == 0) and right or -right
		local sideTarget = root.Position + sideDir * PATH_FAIL_SIDESTEP + direction.Unit * 10
		smartMoveTo(hum, state, sideTarget)
		return
	end
	
	-- Alternative 2: Jump and move
	if state.PathFailCount <= 5 then
		hum.Jump = true
		smartMoveTo(hum, state, targetPos)
		return
	end
	
	-- Alternative 3: Use pathfinding (only if allowed and not on cooldown)
	if allowPathfinding and not state.IsPathfinding and now - state.LastPathTime > 0.5 then
		state.IsPathfinding = true
		state.LastPathTime = now
		
		local agentRadius = botRadius * 0.8 -- Slightly smaller for more lenient paths
		local agentHeight = 5 * ScalingConfig.GetSizeMultiplier(botLevel)
		local startPos = root.Position
		
		task.spawn(function()
			local path = PathfindingService:CreatePath({
				AgentRadius = agentRadius,
				AgentHeight = agentHeight,
				AgentCanJump = true,
				AgentCanClimb = false,
				WaypointSpacing = 6, -- Wider spacing for smoother movement
				Costs = { Water = 100 }
			})
			
			local success = pcall(function()
				path:ComputeAsync(startPos, targetPos)
			end)
			
			if success and path.Status == Enum.PathStatus.Success then
				if botStates[bot] then
					state.Path = path
					state.PathWaypoints = path:GetWaypoints()
					state.CurrentWaypointIndex = 2
					state.PathFailCount = 0
				end
			else
				-- Pathfinding failed - pick new wander destination
				if botStates[bot] and state.State == "WANDER" then
					state.WanderDestination = nil -- Force new destination
				end
			end
			
			if botStates[bot] then
				state.IsPathfinding = false
			end
		end)
	end
	
	-- While waiting for pathfinding, keep trying to move
	smartMoveTo(hum, state, targetPos)
end

-- === Combat Logic ===
local function handleCombat(bot, state, now)
	local target = state.Target
	if not isValidTarget(bot, target) then
		state.Target = nil
		state.State = "WANDER"
		state.WanderDestination = nil
		state.Path = nil
		state.NextOrbSearch = 0
		state.LastMoveToPos = nil
		state.LastMoveToTime = 0
		return
	end

	local root = bot.PrimaryPart
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not root or not targetRoot then return end

	local dist = (targetRoot.Position - root.Position).Magnitude
	local hum = bot:FindFirstChild("Humanoid")
	if not hum then return end
	
	-- ALWAYS be moving in combat
	if dist < 30 then
		-- Close range: Strafe around enemy
		if now > state.NextStrafeChange then
			state.StrafeDir = -state.StrafeDir
			state.NextStrafeChange = now + math.random(1, 3)
		end
		
		local toEnemy = (targetRoot.Position - root.Position).Unit
		local right = Vector3.new(-toEnemy.Z, 0, toEnemy.X)
		local strafePos = root.Position + (right * state.StrafeDir * 15) + (toEnemy * math.random(-3, 8))
		forceMoveTo(hum, state, strafePos)
	else
		-- Long range: Chase
		moveTowardTarget(bot, state, targetRoot.Position, true)
	end

	-- Shooting Logic
	if now - state.LastShot > 0.35 and now - state.TargetAcquiredTime > REACTION_TIME then
		local origin = bot.Head.Position
		local targetHead = target:FindFirstChild("Head") or targetRoot
		local aimPos = targetHead.Position

		local spread = math.clamp(dist / 12, 3.0, 10.0)
		local inaccuracy = Vector3.new(
			math.random() - 0.5,
			math.random() - 0.5,
			math.random() - 0.5
		) * spread
		
		local dir = ((aimPos + inaccuracy) - origin).Unit * 300

		sharedRayParams.FilterDescendantsInstances = { bot }
		local los = Workspace:Raycast(origin, (aimPos - origin).Unit * dist, sharedRayParams)
		
		if not los or los.Instance:IsDescendantOf(target) then
			state.LastShot = now
			local results = castRays(bot, origin, { dir }, 1)

			if replicateShotRemote then
				local clientResults = {}
				for _, hit in ipairs(results) do
					table.insert(clientResults, {
						position = hit.position,
						normal = hit.normal or Vector3.yAxis,
						instance = hit.instance,
						taggedHumanoid = hit.taggedHumanoid
					})
				end
				
				replicateShotRemote:FireAllClients({
					{
						tool = bot:FindFirstChildWhichIsA("Tool"),
						origin = origin,
						results = clientResults
					}
				})
			end

			for _, hit in ipairs(results) do
				if hit.taggedHumanoid then
					local baseDamage = 6 * ScalingConfig.GetDamageMultiplier(bot:GetAttribute("Level") or 1)
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

-- === Wander Logic (Core of constant movement) ===
local function handleWander(bot, state, hum, root, now)
	-- Pick new destination if needed
	if not state.WanderDestination 
		or (root.Position - state.WanderDestination).Magnitude < WANDER_ARRIVAL_DIST
		or now - state.WanderStartTime > 8 -- Timeout after 8 seconds
	then
		state.WanderDestination = pickWanderDestination(bot, state)
		state.WanderStartTime = now
		state.Path = nil
		state.PathFailCount = 0
	end
	
	-- Move toward destination
	if state.WanderDestination then
		moveTowardTarget(bot, state, state.WanderDestination, true)
	end
end

-- === Public API: Aggro ===
function BotController.RecordAggro(bot, attacker)
	if not bot or not attacker then return end
	
	local attackerChar = nil
	if typeof(attacker) == "Instance" then
		if attacker:IsA("Player") then
			attackerChar = attacker.Character
		elseif CollectionService:HasTag(attacker, "BotAI") then
			attackerChar = attacker
		end
	end
	
	if not attackerChar or not isValidTarget(bot, attackerChar) then
		return
	end
	
	local state = getBotState(bot)
	local now = os.clock()
	
	state.AggroTable[attackerChar] = now
	
	local currentTargetIsPlayer = state.Target and typeof(state.Target) == "Instance" and Players:GetPlayerFromCharacter(state.Target)

	if not currentTargetIsPlayer then
		state.Target = attackerChar
		state.State = "COMBAT"
		state.Path = nil
		state.TargetAcquiredTime = now
	end
end

-- === Stuck Recovery (Aggressive) ===
local function handleStuckRecovery(bot, state, hum, root, now, moved)
	-- Check if stuck (trying to move but not moving)
	if moved < STUCK_THRESHOLD and hum.MoveDirection.Magnitude > 0.1 then
		if not state.StuckSince then 
			state.StuckSince = now 
		end
		
		if now - state.StuckSince > STUCK_TIME then
			state.StuckRecoveryAttempts = (state.StuckRecoveryAttempts or 0) + 1
			
			-- Progressive recovery attempts
			if state.StuckRecoveryAttempts <= 2 then
				-- Try 1-2: Jump and move in random direction
				hum.Jump = true
				local randomDir = Vector3.new(math.random()-0.5, 0, math.random()-0.5).Unit * 25
				forceMoveTo(hum, state, root.Position + randomDir)
			elseif state.StuckRecoveryAttempts <= 4 then
				-- Try 3-4: Bigger jump, bigger random move
				hum.Jump = true
				local randomDir = Vector3.new(math.random()-0.5, 0, math.random()-0.5).Unit * 50
				forceMoveTo(hum, state, root.Position + randomDir)
			else
				-- Try 5+: Complete reset - pick entirely new destination
				state.WanderDestination = nil
				state.Target = nil
				state.State = "WANDER"
				state.Path = nil
				state.PathFailCount = 0
				state.StuckRecoveryAttempts = 0
				hum.Jump = true
			end
			
			state.StuckSince = nil
			state.Path = nil
			state.LastMoveToPos = nil
			state.LastMoveToTime = 0
			return true -- Handled
		end
	else
		-- Moving successfully - reset stuck tracking
		state.StuckSince = nil
		if moved > 2 then
			state.StuckRecoveryAttempts = 0
		end
	end
	
	-- Check for complete idle (not even trying to move)
	if moved < STUCK_THRESHOLD and hum.MoveDirection.Magnitude < 0.1 then
		if now - state.LastMoveToTime > IDLE_TIMEOUT then
			-- Bot is completely idle - force a new destination
			state.WanderDestination = pickWanderDestination(bot, state)
			state.WanderStartTime = now
			if state.WanderDestination then
				forceMoveTo(hum, state, state.WanderDestination)
			end
			state.Path = nil
			state.IsPathfinding = false
			
			-- Reset orb chasing if stuck
			if state.State == "ORB" and state.Target and state.Target.ID then
				state.OrbBlacklist[state.Target.ID] = now
				state.State = "WANDER"
				state.Target = nil
			end
			return true
		end
	end
	
	return false
end

-- === Main Loop ===
function BotController.Start()
	print("--- Starting Movement-First BotController ---")

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
			
			-- Fix physics state issues
			local humState = hum:GetState()
			if humState == Enum.HumanoidStateType.Physics or humState == Enum.HumanoidStateType.None then
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end

			local state = getBotState(bot)

			-- Network ownership (distributed check)
			if (i + frameCount) % 10 == 0 then
				updateNetworkOwnership(bot, state.Target)
			end

			-- AI throttling (but combat gets priority)
			if (i + frameCount) % UPDATE_INTERVAL ~= 0 and state.State ~= "COMBAT" then
				continue
			end

			-- Combat runs more frequently
			if state.State == "COMBAT" and (i + frameCount) % 3 == 0 then
				handleCombat(bot, state, now)
				continue
			end

			-- === Movement Guarantee Checks ===
			local moved = (root.Position - state.LastPos).Magnitude
			
			-- Handle stuck/idle recovery
			if handleStuckRecovery(bot, state, hum, root, now, moved) then
				state.LastPos = root.Position
				continue
			end
			
			state.LastPos = root.Position

			-- Clean aggro table
			for attacker, time in pairs(state.AggroTable) do
				local targetEntity = attacker
				if typeof(attacker) == "Instance" and attacker:IsA("Player") then
					targetEntity = attacker.Character
				end
				if (now - time > AGGRO_DURATION) or not isValidTarget(bot, targetEntity) then
					state.AggroTable[attacker] = nil
				end
			end

			-- Clean orb blacklist
			for id, time in pairs(state.OrbBlacklist) do
				if now - time > 15 then
					state.OrbBlacklist[id] = nil
				end
			end

			-- Safe zone escape
			local escapeTarget = getEscapeSafeZoneTarget(root.Position)
			if escapeTarget then
				moveTowardTarget(bot, state, escapeTarget, false)
				state.State = "WANDER"
				state.Target = nil
				state.WanderDestination = escapeTarget
				continue
			end

			-- === State Machine ===
			
			-- Check for aggro targets
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
				handleCombat(bot, state, now)
				continue
			end
			
			-- Check for nearby enemies
			local enemy = findNearestEnemy(bot, 80)
			if enemy then
				state.Target = enemy
				state.State = "COMBAT"
				state.TargetAcquiredTime = now
				handleCombat(bot, state, now)
				continue
			end
			
			-- Look for orbs (less frequently)
			if now > state.NextOrbSearch then
				local level = bot:GetAttribute("Level") or 1
				local searchRange = 500 * ScalingConfig.GetSizeMultiplier(level)
				local orb = findNearestOrb(bot, state, searchRange)
				
				if orb then
					state.State = "ORB"
					state.Target = orb
					state.TargetAcquiredTime = now
					state.WanderDestination = nil
				end
				state.NextOrbSearch = now + ORB_SEARCH_INTERVAL
			end
			
			-- Handle current state
			if state.State == "ORB" and state.Target then
				local targetPos = state.Target.Position
				local distToOrb = (targetPos - root.Position).Magnitude
				
				-- Give up on orb after 6 seconds
				if now - state.TargetAcquiredTime > 6.0 then
					if state.Target.ID then
						state.OrbBlacklist[state.Target.ID] = now
					end
					state.State = "WANDER"
					state.Target = nil
					state.WanderDestination = nil
				elseif distToOrb < 30 then
					-- Close to orb - try to collect
					if state.Target.ID then
						local collected = XPOrbService.CollectOrb(bot, state.Target.ID)
						if collected then
							state.State = "WANDER"
							state.Target = nil
							state.WanderDestination = nil
						end
					end
					moveTowardTarget(bot, state, targetPos, false)
				else
					moveTowardTarget(bot, state, targetPos, true)
				end
			elseif state.State == "COMBAT" then
				if not isValidTarget(bot, state.Target) then
					state.State = "WANDER"
					state.Target = nil
					state.WanderDestination = nil
				else
					handleCombat(bot, state, now)
				end
			else
				-- Default: WANDER (always be moving!)
				state.State = "WANDER"
				handleWander(bot, state, hum, root, now)
			end
		end
	end)
end

return BotController
