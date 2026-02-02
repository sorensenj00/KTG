--[[
	BotController: Movement-first bot AI
	Bots always wander, chase orbs, or fight - never stand still.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
-- Removed SafeZoneConfig
local DamageTracker = require(ServerScriptService.Services.World.DamageTrackerService)
local castRays = require(ServerScriptService.Utility.castRays)
local ProgressionManager = require(ServerScriptService.Services.Progression.ProgressionService)
local XPOrbService = require(ServerScriptService.Services.World.XPOrbService)

-- Constants
local UPDATE_INTERVAL = 5
local COMBAT_UPDATE_INTERVAL = 3
local AGGRO_DURATION = 8
local REACTION_TIME = 1.2
local STUCK_TIME = 0.5
local IDLE_TIMEOUT = 0.8
local WANDER_DIST = { MIN = 40, MAX = 80 }
local ENEMY_RANGE = 80
local ORB_SEARCH_INTERVAL = 0.5

-- Lazy-loaded remotes
local eliminatedEvent, replicateShotRemote
task.spawn(function()
	local blaster = ServerScriptService:WaitForChild("Blaster", 10)
	if blaster then
		eliminatedEvent = blaster:WaitForChild("Events"):WaitForChild("Eliminated", 10)
	end
	local repBlaster = ReplicatedStorage:WaitForChild("Blaster", 10)
	if repBlaster then
		replicateShotRemote = repBlaster:WaitForChild("Remotes"):WaitForChild("ReplicateShot", 10)
	end
end)

-- Shared state
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.RespectCanCollide = true

local orbFolder = Workspace:WaitForChild("Orbs", 5)
local botStates = {}

local BotController = {}

--== State Helpers ==--

local function getState(bot)
	if not botStates[bot] then
		botStates[bot] = {
			target = nil,
			mode = "WANDER", -- WANDER | COMBAT | ORB
			wanderDest = nil,
			wanderStart = 0,
			nextOrbSearch = 0,
			aggro = {},
			lastPos = bot.PrimaryPart and bot.PrimaryPart.Position or Vector3.zero,
			stuckSince = nil,
			stuckAttempts = 0,
			lastShot = 0,
			strafeDir = 1,
			nextStrafe = 0,
			targetAcquiredAt = 0,
			orbBlacklist = {},
			lastMoveTo = nil,
			lastMoveTime = 0,
			pathfinding = false,
			lastPathTime = 0,
			path = nil,
			waypoints = nil,
			waypointIdx = nil,
			pathFails = 0,
		}
	end
	return botStates[bot]
end

local function clearState(s)
	s.target = nil
	s.mode = "WANDER"
	s.wanderDest = nil
	s.path = nil
	s.waypoints = nil
	s.pathFails = 0
end

--== Utility ==--

local function isValidTarget(target)
	if not target then
		return false
	end
	if typeof(target) == "table" then
		return target.Name == "XPOrb"
	end
	if typeof(target) ~= "Instance" or not target.Parent then
		return false
	end
	local hum = target:FindFirstChild("Humanoid")
	return hum and hum.Health > 0
end

local function findEnemy(bot, range)
	local root = bot.PrimaryPart
	if not root then
		return nil
	end
	local best = nil
	local bestDist = range
	-- Check for bots
	for _, other in ipairs(CollectionService:GetTagged("BotAI")) do
		if other ~= bot and isValidTarget(other) then
			local otherRoot = other.PrimaryPart
			if otherRoot then
				local d = (otherRoot.Position - root.Position).Magnitude
				if d < bestDist then
					best = other
					bestDist = d
				end
			end
		end
	end

	-- Check for players
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and isValidTarget(char) then
			local otherRoot = char.PrimaryPart
			if otherRoot then
				local d = (otherRoot.Position - root.Position).Magnitude
				if d < bestDist then
					best = char
					bestDist = d
				end
			end
		end
	end

	return best
end

-- Removed inSafeZone helper

local function pickWanderDest(bot)
	local root = bot.PrimaryPart
	if not root then
		return nil
	end
	local dist = math.random(WANDER_DIST.MIN, WANDER_DIST.MAX)
	local angle = math.random() * math.pi * 2
	local target = root.Position + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	rayParams.FilterDescendantsInstances = { bot, orbFolder }
	local hit =
		Workspace:Raycast(Vector3.new(target.X, root.Position.Y + 50, target.Z), Vector3.yAxis * -200, rayParams)
	return Vector3.new(target.X, hit and hit.Position.Y + 3 or root.Position.Y, target.Z)
end

--== Movement ==--

local function moveTo(hum, s, pos, force)
	local now = os.clock()
	if force or not s.lastMoveTo or now - s.lastMoveTime > 0.1 then
		hum:MoveTo(pos)
		s.lastMoveTo = pos
		s.lastMoveTime = now
	end
end

local function moveToward(bot, s, targetPos, usePath)
	local root = bot.PrimaryPart
	local hum = bot:FindFirstChild("Humanoid")
	if not root or not hum then
		return
	end

	local dir = targetPos - root.Position
	local dist = dir.Magnitude

	-- Follow existing path
	if s.path and s.waypoints and s.waypointIdx and s.waypointIdx <= #s.waypoints then
		local wp = s.waypoints[s.waypointIdx]
		if (root.Position - wp.Position).Magnitude < 6 then
			s.waypointIdx += 1
			if s.waypointIdx > #s.waypoints then
				s.path = nil
				s.waypoints = nil
			elseif wp.Action == Enum.PathWaypointAction.Jump then
				hum.Jump = true
			end
		end
		if s.waypoints and s.waypointIdx <= #s.waypoints then
			moveTo(hum, s, s.waypoints[s.waypointIdx].Position, false)
		end
		return
	end

	-- Direct movement check (multiple heights to detect obstacles)
	rayParams.FilterDescendantsInstances = { bot, orbFolder }
	local rayDist = math.min(dist, 15)
	local rayDir = dir.Unit * rayDist
	local blocked = nil

	-- Check at multiple heights: feet (0.5), waist (2), head (4)
	for _, heightOffset in { 0.5, 2, 4 } do
		local hit = Workspace:Raycast(root.Position + Vector3.yAxis * heightOffset, rayDir, rayParams)
		if hit and hit.Normal.Y <= 0.4 then -- Not a ramp/slope
			blocked = hit
			break
		end
	end

	if not blocked or dist < 10 then
		moveTo(hum, s, targetPos, false)
		s.path = nil
		s.pathFails = 0
		return
	end

	-- Fallback: sidestep/jump then pathfind quickly
	s.pathFails = (s.pathFails or 0) + 1
	if s.pathFails == 1 then
		-- First fail: try jumping forward
		hum.Jump = true
		moveTo(hum, s, targetPos, false)
		return
	elseif s.pathFails == 2 then
		-- Second fail: sidestep right
		local right = Vector3.new(-dir.Unit.Z, 0, dir.Unit.X)
		moveTo(hum, s, root.Position + right * 25, false)
		return
	elseif s.pathFails == 3 then
		-- Third fail: sidestep left
		local right = Vector3.new(-dir.Unit.Z, 0, dir.Unit.X)
		moveTo(hum, s, root.Position - right * 25, false)
		return
	end
	-- After 3 fails, immediately try pathfinding (handled below)

	-- Pathfinding
	if usePath and not s.pathfinding and os.clock() - s.lastPathTime > 0.5 then
		s.pathfinding = true
		s.lastPathTime = os.clock()
		local level = bot:GetAttribute("Level") or 1
		local startPos = root.Position
		task.spawn(function()
			local path = PathfindingService:CreatePath({
				AgentRadius = 2 * ScalingConfig.GetSizeMultiplier(level) * 0.8,
				AgentHeight = 5 * ScalingConfig.GetSizeMultiplier(level),
				AgentCanJump = true,
			})
			local ok = pcall(function()
				path:ComputeAsync(startPos, targetPos)
			end)
			if ok and path.Status == Enum.PathStatus.Success and botStates[bot] then
				s.path = path
				s.waypoints = path:GetWaypoints()
				s.waypointIdx = 2
				s.pathFails = 0
			elseif botStates[bot] and s.mode == "WANDER" then
				s.wanderDest = nil
			end
			if botStates[bot] then
				s.pathfinding = false
			end
		end)
	end
	moveTo(hum, s, targetPos, false)
end

--== Combat ==--

local function doCombat(bot, s, now)
	local target = s.target
	if not isValidTarget(target) then
		clearState(s)
		return
	end

	local root = bot.PrimaryPart
	local targetRoot = target:FindFirstChild("HumanoidRootPart")
	local hum = bot:FindFirstChild("Humanoid")
	if not root or not targetRoot or not hum then
		return
	end

	local dist = (targetRoot.Position - root.Position).Magnitude

	-- Movement: strafe close, chase far
	if dist < 30 then
		if now > s.nextStrafe then
			s.strafeDir = -s.strafeDir
			s.nextStrafe = now + math.random(1, 3)
		end
		local toEnemy = (targetRoot.Position - root.Position).Unit
		local right = Vector3.new(-toEnemy.Z, 0, toEnemy.X)
		moveTo(hum, s, root.Position + right * s.strafeDir * 15 + toEnemy * math.random(-3, 8), true)
	else
		moveToward(bot, s, targetRoot.Position, true)
	end

	-- Shooting
	if now - s.lastShot > 0.35 and now - s.targetAcquiredAt > REACTION_TIME then
		local origin = bot.Head.Position
		local aimPos = (target:FindFirstChild("Head") or targetRoot).Position
		local spread = math.clamp(dist / 12, 3, 10)
		local inaccuracy = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * spread
		local dir = ((aimPos + inaccuracy) - origin).Unit * 300

		rayParams.FilterDescendantsInstances = { bot }
		local los = Workspace:Raycast(origin, (aimPos - origin).Unit * dist, rayParams)

		if not los or los.Instance:IsDescendantOf(target) then
			s.lastShot = now
			local results = castRays(bot, origin, { dir }, 1)

			if replicateShotRemote then
				local data = {}
				for _, hit in results do
					table.insert(data, {
						position = hit.position,
						normal = hit.normal or Vector3.yAxis,
						instance = hit.instance,
						taggedHumanoid = hit.taggedHumanoid,
					})
				end
				replicateShotRemote:FireAllClients({
					{ tool = bot:FindFirstChildWhichIsA("Tool"), origin = origin, results = data },
				})
			end

			for _, hit in results do
				if hit.taggedHumanoid then
					local dmg = 6 * ScalingConfig.GetDamageMultiplier(bot:GetAttribute("Level") or 1)
					hit.taggedHumanoid:TakeDamage(dmg)
					DamageTracker.RecordDamage(bot, hit.taggedHumanoid.Parent, dmg)
					if hit.taggedHumanoid.Health <= 0 and eliminatedEvent then
						eliminatedEvent:Fire(nil, bot, hit.taggedHumanoid.Parent, bot:FindFirstChildWhichIsA("Tool"))
						ProgressionManager.AddBiomass(bot, 50)
					end
				end
			end
		end
	end
end

--== Stuck Recovery ==--

local function handleStuck(bot, s, hum, root, now, moved)
	if moved < 0.3 and hum.MoveDirection.Magnitude > 0.1 then
		s.stuckSince = s.stuckSince or now
		if now - s.stuckSince > STUCK_TIME then
			s.stuckAttempts = (s.stuckAttempts or 0) + 1
			hum.Jump = true

			-- Escalating escape: random direction, then bigger jumps, then full reset
			if s.stuckAttempts <= 2 then
				local randDir = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
				moveTo(hum, s, root.Position + randDir * 30, true)
			elseif s.stuckAttempts <= 4 then
				-- Try moving backwards from current target
				local escapeDir = s.wanderDest and (root.Position - s.wanderDest).Unit
					or Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
				moveTo(hum, s, root.Position + escapeDir * 50, true)
			else
				-- Fully reset and pick distant destination
				clearState(s)
				s.wanderDest = pickWanderDest(bot)
				s.stuckAttempts = 0
			end
			s.stuckSince = nil
			s.path = nil
			s.pathFails = 0
			return true
		end
	else
		s.stuckSince = nil
		if moved > 2 then
			s.stuckAttempts = 0
		end
	end

	if moved < 0.3 and hum.MoveDirection.Magnitude < 0.1 and now - s.lastMoveTime > IDLE_TIMEOUT then
		s.wanderDest = pickWanderDest(bot)
		if s.wanderDest then
			moveTo(hum, s, s.wanderDest, true)
		end
		s.path = nil
		s.pathfinding = false
		s.pathFails = 0
		if s.mode == "ORB" and s.target and s.target.ID then
			s.orbBlacklist[s.target.ID] = now
		end
		clearState(s)
		return true
	end
	return false
end

--== Main Loop ==--

function BotController.Start()
	print("--- BotController Started ---")
	local frame = 0

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		frame += 1

		for i, bot in CollectionService:GetTagged("BotAI") do
			local hum = bot:FindFirstChild("Humanoid")
			local root = bot:FindFirstChild("HumanoidRootPart")
			if not hum or hum.Health <= 0 or not root then
				botStates[bot] = nil
				continue
			end

			-- Fix physics state
			local humState = hum:GetState()
			if humState == Enum.HumanoidStateType.Physics or humState == Enum.HumanoidStateType.None then
				pcall(function()
					hum:ChangeState(Enum.HumanoidStateType.Running)
				end)
			end

			local s = getState(bot)

			-- Throttle non-combat bots
			local isCombat = s.mode == "COMBAT"
			if not isCombat and (i + frame) % UPDATE_INTERVAL ~= 0 then
				continue
			end
			if isCombat and (i + frame) % COMBAT_UPDATE_INTERVAL ~= 0 then
				continue
			end

			-- Stuck recovery
			local moved = (root.Position - s.lastPos).Magnitude
			if handleStuck(bot, s, hum, root, now, moved) then
				s.lastPos = root.Position
				continue
			end
			s.lastPos = root.Position

			-- Clean old aggro/blacklist
			for attacker, time in pairs(s.aggro) do
				if now - time > AGGRO_DURATION or not isValidTarget(attacker) then
					s.aggro[attacker] = nil
				end
			end
			for id, time in pairs(s.orbBlacklist) do
				if now - time > 15 then
					s.orbBlacklist[id] = nil
				end
			end

-- Removed Safe zone escape

			-- Combat: continue if valid
			if s.mode == "COMBAT" and isValidTarget(s.target) then
				doCombat(bot, s, now)
				continue
			end

			-- Find new target: aggro first
			local bestAggro = nil
			local bestTime = 0
			for attacker, time in pairs(s.aggro) do
				if time > bestTime and isValidTarget(attacker) then
					bestAggro = attacker
					bestTime = time
				end
			end
			if bestAggro then
				if s.target ~= bestAggro then
					s.targetAcquiredAt = now
				end
				s.target = bestAggro
				s.mode = "COMBAT"
				doCombat(bot, s, now)
				continue
			end

			-- Find new target: nearby enemy
			local enemy = findEnemy(bot, ENEMY_RANGE)
			if enemy then
				if s.target ~= enemy then
					s.targetAcquiredAt = now
				end
				s.target = enemy
				s.mode = "COMBAT"
				doCombat(bot, s, now)
				continue
			end

			-- Look for orbs
			if now > s.nextOrbSearch then
				local range = 500 * ScalingConfig.GetSizeMultiplier(bot:GetAttribute("Level") or 1)
				local orb = XPOrbService.GetNearestOrb(root.Position, range, s.orbBlacklist)
				if orb then
					s.mode = "ORB"
					s.target = orb
					s.targetAcquiredAt = now
					s.wanderDest = nil
				end
				s.nextOrbSearch = now + ORB_SEARCH_INTERVAL
			end

			-- Handle ORB state
			if s.mode == "ORB" and s.target then
				local pos = s.target.Position
				local d = (pos - root.Position).Magnitude
				if now - s.targetAcquiredAt > 6 then
					if s.target.ID then
						s.orbBlacklist[s.target.ID] = now
					end
					clearState(s)
				elseif d < 30 and s.target.ID and XPOrbService.CollectOrb(bot, s.target.ID) then
					clearState(s)
				else
					moveToward(bot, s, pos, d >= 10)
				end
				continue
			end

			-- Default: Wander
			s.mode = "WANDER"
			if not s.wanderDest or (root.Position - s.wanderDest).Magnitude < 8 or now - s.wanderStart > 8 then
				s.wanderDest = pickWanderDest(bot)
				s.wanderStart = now
				s.path = nil
				s.pathFails = 0
			end
			if s.wanderDest then
				moveToward(bot, s, s.wanderDest, true)
			end
		end
	end)
end

function BotController.RecordAggro(bot, attacker)
	if not bot or not attacker then
		return
	end

	-- Normalize attacker to character model
	local char
	if typeof(attacker) == "Instance" then
		if attacker:IsA("Player") then
			char = attacker.Character
		elseif attacker:IsA("Model") and CollectionService:HasTag(attacker, "BotAI") then
			char = attacker
		end
	end

	if not char or not isValidTarget(char) then
		return
	end

	local s = getState(bot)
	s.aggro[char] = os.clock()

	-- Only switch target if current target isn't a player
	local currentTargetIsPlayer = typeof(s.target) == "Instance" and Players:GetPlayerFromCharacter(s.target)
	if not currentTargetIsPlayer then
		s.target = char
		s.mode = "COMBAT"
		s.path = nil
		s.targetAcquiredAt = os.clock()
	end
end

return BotController
