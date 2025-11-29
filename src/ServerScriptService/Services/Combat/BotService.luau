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
local ScalingEngine = require(ServerScriptService.Services.World.ScalingEngineService)
local DamageTracker = require(ServerScriptService.Services.World.DamageTrackerService)
local MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
local castRays = require(ServerScriptService.Utility.castRays)
local ProgressionManager = require(ServerScriptService.Services.Progression.ProgressionService)
local XPOrbService = require(ServerScriptService.Services.World.XPOrbService)

-- === Constants ===
local UPDATE_INTERVAL = 15 -- Run AI logic every 15 frames (approx 4 times/sec)
local AGGRO_DURATION = 8
local NETWORK_OWNERSHIP_RADIUS = 200 -- Transfer ownership if player is within 200 studs
local ORB_SEARCH_INTERVAL = 1.0 -- Search for orbs once per second
local STUCK_THRESHOLD = 0.5
local STUCK_TIME = 1.0
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
	Target: Instance?,
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
	TargetAcquiredTime: number
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
			TargetAcquiredTime = 0
		}
	end
	return botStates[bot]
end

-- === Helper: Network Ownership ===
local function updateNetworkOwnership(bot, target)
	local root = bot:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local newOwner = nil
	local shortestDist = NETWORK_OWNERSHIP_RADIUS

	-- Priority 1: The Target (if it's a player)
	if target and target:IsA("Model") then
		local player = Players:GetPlayerFromCharacter(target)
		if player then
			local dist = (target.HumanoidRootPart.Position - root.Position).Magnitude
			if dist < NETWORK_OWNERSHIP_RADIUS then
				newOwner = player
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

-- === Helper: Spatial Orb Search ===
local function findNearestOrb(bot, range)
	local root = bot.PrimaryPart
	if not root then return nil end

	-- Use Optimized XPOrbService (Data-only query, no physics)
	return XPOrbService.GetNearestOrb(root.Position, range)
end

-- === Helper: Target Validation & Scoring ===
local function isValidTarget(bot, target)
	if not target or not target.Parent then return false end
	local hum = target:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then return false end
	return true
end

-- === Helper: Find Nearest Enemy ===
local function findNearestEnemy(bot, range)
	local root = bot.PrimaryPart
	if not root then return nil end
	
	local bestTarget = nil
	local bestDist = range
	
	-- 1. Check Players
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character and isValidTarget(bot, player.Character) then
			local dist = (player.Character.PrimaryPart.Position - root.Position).Magnitude
			if dist < bestDist then
				bestDist = dist
				bestTarget = player.Character
			end
		end
	end
	
	-- 2. Check other Bots
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
				hum:MoveTo(state.PathWaypoints[state.CurrentWaypointIndex].Position)

				-- Jump if needed
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					hum.Jump = true
				end
			else
				-- End of path, move directly to target
				hum:MoveTo(targetPos)
				state.Path = nil
			end
		else
			-- Continue to current waypoint
			hum:MoveTo(waypoint.Position)
		end
	else
		-- No path, create one?
		-- Only create path if direct line is blocked (Optimization)
		local direction = (targetPos - root.Position)
		local distance = direction.Magnitude

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { bot, Workspace:FindFirstChild("Orbs") }

		local blocked = Workspace:Raycast(root.Position, direction.Unit * math.min(distance, 50), rayParams)

		if blocked and (blocked.Instance.CanCollide or blocked.Instance.Transparency < 0.9) then
			-- Blocked

			-- 1. Check if already pathfinding or cooldown
			if state.IsPathfinding then return end
			if os.clock() - state.LastPathTime < 1.0 then
				-- On cooldown, wait (stand still)
				hum:MoveTo(root.Position)
				return
			end

			-- 2. Start Async Pathfinding
			state.IsPathfinding = true
			state.LastPathTime = os.clock()

			local botLevel = bot:GetAttribute("Level") or 1
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

			-- While waiting, stand still or look at target
			hum:MoveTo(root.Position)
		else
			-- Clear, move directly
			hum:MoveTo(targetPos)
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
		return
	end

	local root = bot.PrimaryPart
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	if not root or not targetRoot then return end

	local dist = (targetRoot.Position - root.Position).Magnitude

	-- Movement: Strafe or Chase
	if dist < 30 then
		-- Close range: Strafe
		if now > state.NextStrafeChange then
			state.StrafeDir = -state.StrafeDir
			state.NextStrafeChange = now + math.random(2, 4)
		end
		
		local toEnemy = (targetRoot.Position - root.Position).Unit
		local right = Vector3.new(-toEnemy.Z, 0, toEnemy.X)
		local strafePos = root.Position + (right * state.StrafeDir * 10) + (toEnemy * math.random(-5, 5))
		
		-- Use direct move for strafing (responsive)
		-- Check path clear for strafe?
		-- For optimization, we assume short strafes are clear, or collision handles it
		bot.Humanoid:MoveTo(strafePos)
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
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { bot }

		local los = Workspace:Raycast(origin, (aimPos - origin).Unit * dist, rayParams)
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
						ProgressionManager.AddXP(bot, 50)
					end
				end
			end
		end
	end
end

-- === Public API: Aggro ===
function BotController.RecordAggro(bot, attacker)
	if not bot or not attacker then return end
	if not attacker:IsA("Player") and not CollectionService:HasTag(attacker, "BotAI") then return end
	
	local state = getBotState(bot)
	local now = os.clock()
	
	-- Record timestamp
	state.AggroTable[attacker] = now
	
	-- Instant Reaction: Switch target immediately if not already locked on a player
	local currentTargetIsPlayer = state.Target and Players:GetPlayerFromCharacter(state.Target)

	if not currentTargetIsPlayer then
		state.Target = attacker.Character or attacker -- Handle Player object vs Character model
		state.State = "COMBAT"
		state.Path = nil -- Clear old path
		state.TargetAcquiredTime = now
		-- print("Bot " .. bot.Name .. " instantly reacted to " .. attacker.Name)
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

			-- Stuck Detection
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
					state.LastPos = root.Position
					continue
				end
			else
				state.StuckSince = nil
			end
			state.LastPos = root.Position

			
			-- Target Selection
			if state.State == "COMBAT" then
				if not isValidTarget(bot, state.Target) then
					state.State = "IDLE"
					state.Target = nil
					state.Path = nil
				end
			end

			if (state.State :: any) == "IDLE" or (state.State :: any) == "ORB" then
				-- Look for Aggro Targets first
				local bestAggro = nil
				local bestTime = 0
				for attacker, time in pairs(state.AggroTable) do
					if time > bestTime and isValidTarget(bot, attacker.Character or attacker) then
						bestAggro = attacker.Character or attacker
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
						local searchRange = 100 * ScalingConfig.GetSizeMultiplier(level)
						local orb = findNearestOrb(bot, searchRange)

						if orb then
							state.State = "ORB"
							state.Target = orb
							-- Move to orb
							moveToPath(bot, state, orb.Position)
						else
							state.State = "IDLE"
							-- Roam logic
							if hum.MoveDirection.Magnitude < 0.1 then
								local roamPos = root.Position + Vector3.new(math.random(-50,50), 0, math.random(-50,50))
								moveToPath(bot, state, roamPos)
							end
						end
						state.NextOrbSearch = now + ORB_SEARCH_INTERVAL
					elseif (state.State :: any) == "ORB" and state.Target then
						-- Continue moving to orb
						if (state.Target.Position - root.Position).Magnitude < 5 then
							-- close enough, wait for pickup
						else
							moveToPath(bot, state, state.Target.Position)
						end
					end
				end
			end
			end

		end
	end)
end

return BotController
