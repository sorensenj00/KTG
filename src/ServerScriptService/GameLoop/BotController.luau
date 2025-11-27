local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local castRays = require(ServerScriptService.Utility.castRays)
local ProgressionManager = require(script.Parent.ProgressionManager)
local DamageTracker = require(script.Parent.DamageTracker)

-- Events
local eliminatedEvent
task.spawn(function()
	eliminatedEvent = ServerScriptService.Blaster:WaitForChild("Events"):WaitForChild("Eliminated", 10)
end)

local BotController = {}

-- Aggro System: [bot] = { [player] = timestamp }
-- Module-level so it's accessible to RecordAggro function
local botAggroTable = {}

-- Aggro duration in seconds
local AGGRO_DURATION = 5

-- Record aggro when a bot is damaged by a player
local function recordBotAggro(bot, attackerPlayer)
	if not bot or not attackerPlayer or not attackerPlayer:IsA("Player") then
		return
	end

	if not botAggroTable[bot] then
		botAggroTable[bot] = {}
	end

	local now = Workspace:GetServerTimeNow()
	botAggroTable[bot][attackerPlayer] = now
end

-- Public API for recording aggro (called from blaster system)
function BotController.RecordAggro(bot, attackerPlayer)
	recordBotAggro(bot, attackerPlayer)
end

-- Check if a player has aggro on a bot (within duration)
local function hasAggro(bot, player)
	-- Defensive checks: ensure bot and player are valid
	if not bot or not player then
		return false
	end

	-- Ensure player is actually a Player instance
	if not player:IsA("Player") then
		return false
	end

	-- Check if bot entry exists in aggro table
	if not botAggroTable[bot] then
		return false
	end

	-- Check if player entry exists for this bot
	if not botAggroTable[bot][player] then
		return false
	end

	local now = Workspace:GetServerTimeNow()
	local aggroTime = botAggroTable[bot][player]
	return (now - aggroTime) <= AGGRO_DURATION
end

-- Clean up stale aggro entries
local function cleanupAggro(bot, now)
	if not botAggroTable[bot] then
		return
	end

	for player, timestamp in pairs(botAggroTable[bot]) do
		if (now - timestamp) > AGGRO_DURATION then
			botAggroTable[bot][player] = nil
		end
	end

	-- Remove bot entry if empty
	if next(botAggroTable[bot]) == nil then
		botAggroTable[bot] = nil
	end
end

function BotController.Start()
	print("--- Starting Smart BotController ---")

	local replicateShotRemote = ReplicatedStorage.Blaster.Remotes.ReplicateShot
	local botData = {} -- [Model] = { NextDecision = 0, Target = nil, StuckTime = 0, LastPos = Vector3, LastMovementTime = 0 }

	local function getBotRanges(bot)
		local level = bot:GetAttribute("Level") or 1
		local scale = ScalingConfig.GetSizeMultiplier(level)
		return {
			Detect = 150 * scale,
		}
	end

	-- Find closest enemy (player or bot) and nearest orb
	-- ✅ IMPROVED: Spatial partitioning for bot target detection
	local function scanSurroundings(bot, rootPos, attackRadius)
		-- Use OverlapParams for efficient spatial queries (replaces Region3)
		local overlapParams = OverlapParams.new()
		overlapParams.FilterType = Enum.RaycastFilterType.Exclude
		overlapParams.FilterDescendantsInstances = { bot }
		overlapParams.MaxParts = 100 -- Increased limit to detect crowded enemies reliably

		local halfSize = attackRadius
		local cframe = CFrame.new(rootPos)
		local size = Vector3.new(halfSize * 2, 100, halfSize * 2)

		local parts = Workspace:GetPartBoundsInBox(cframe, size, overlapParams)

		local bestTarget = nil
		local bestDist = attackRadius

		for _, part in ipairs(parts) do
			local char = part.Parent
			local hum = char:FindFirstChild("Humanoid")
			local humRoot = char:FindFirstChild("HumanoidRootPart")

			if hum and humRoot and hum.Health > 0 and char ~= bot then
				-- Target found
				local targetPos = humRoot.Position
				local dist = (targetPos - rootPos).Magnitude
				if dist < bestDist then
					local targetPlayer = Players:GetPlayerFromCharacter(char)

					-- If target is a player, check if they have aggro
					if targetPlayer and targetPlayer:IsA("Player") then
						-- Check aggro before allowing targeting
						local hasPlayerAggro = hasAggro(bot, targetPlayer)

						if hasPlayerAggro then
							-- Player has shot this bot, valid target
							bestDist = dist
							bestTarget = char
						end
						-- If player hasn't shot bot, skip them (do not update bestDist or bestTarget)
					elseif not targetPlayer then
						-- Target is not a player, check if it's a bot
						-- Verify it's actually a bot by checking for BotAI tag
						if CollectionService:HasTag(char, "BotAI") then
							bestDist = dist
							bestTarget = char
						end
					end
				end
			end
		end

		-- Find orbs (optimized: scan only Orbs folder)
		local bestOrb = nil
		local orbDist = math.huge

		local orbsFolder = Workspace:FindFirstChild("Orbs")
		if orbsFolder then
			for _, child in ipairs(orbsFolder:GetChildren()) do
				if child.Name == "XPOrb" and child:IsA("BasePart") then
					local dist = (child.Position - rootPos).Magnitude
					if dist < orbDist then
						orbDist = dist
						bestOrb = child
					end
				end
			end
		end

		return bestTarget, bestOrb
	end

	-- Check if path from bot to target position is clear of obstacles
	local function checkPathClear(bot, fromPos, toPos, excludeTarget)
		local direction = toPos - fromPos
		local distance = direction.Magnitude
		if distance < 0.1 then
			return true -- Already at target
		end

		local rayDirection = direction.Unit

		-- Build exclude list: bot's character and optionally the target
		local exclude = { bot }
		if excludeTarget then
			table.insert(exclude, excludeTarget)
		end

		-- Create raycast params
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = exclude
		params.IgnoreWater = true

		-- Cast ray from bot position to target
		local rayResult = Workspace:Raycast(fromPos, rayDirection * distance, params)

		-- Path is clear if no hit, or if hit is very close to target (within 5 studs)
		if not rayResult then
			return true
		end

		-- If we hit something, check if it's close to the target (might be the target itself)
		local hitDistance = (rayResult.Position - fromPos).Magnitude
		local targetDistance = distance

		-- Path is considered clear if hit is within 5 studs of target (accounting for target size)
		return (targetDistance - hitDistance) < 5
	end

	local function shootAt(bot, target)
		local tool = bot:FindFirstChildWhichIsA("Tool")
		if not tool or not target then
			return
		end

		-- Simple cooldown check
		local now = Workspace:GetServerTimeNow()
		if botData[bot].LastShot and (now - botData[bot].LastShot < 0.2) then
			return
		end
		
		-- === HUMANIZED AIMING: Reaction Delay ===
		-- Bot needs time to "notice" the target before shooting
		if botData[bot].Target ~= target then
			-- New target detected, start reaction timer
			botData[bot].Target = target
			botData[bot].TargetAcquiredTime = now
			botData[bot].MissCount = 0
			return -- Don't shoot immediately
		end
		
		-- Check if reaction time has passed (0.2-0.4 seconds)
		local reactionTime = 0.2 + math.random() * 0.2
		if now - (botData[bot].TargetAcquiredTime or 0) < reactionTime then
			return -- Still reacting, don't shoot yet
		end

		-- Aim Logic: Calculate from bot's Head to target's HumanoidRootPart
		local origin = bot.Head.Position
		local targetRootPart = target:FindFirstChild("HumanoidRootPart")
		if not targetRootPart then
			return
		end

		local targetPos = targetRootPart.Position
		
		-- 1. Line of Sight Check (Prevent shooting through walls)
		local losDirection = (targetPos - origin)
		local losDistance = losDirection.Magnitude
		local losParams = RaycastParams.new()
		losParams.FilterType = Enum.RaycastFilterType.Exclude
		losParams.FilterDescendantsInstances = {bot, target}
		losParams.IgnoreWater = true
		
		local losResult = Workspace:Raycast(origin, losDirection.Unit * losDistance, losParams)
		if losResult then
			-- Obstructed by something that isn't the bot or the target
			-- Increment miss count or just return
			botData[bot].MissCount = (botData[bot].MissCount or 0) + 1
			if botData[bot].MissCount > 10 then
				-- Reset target if we can't see/hit it for too long
				botData[bot].Target = nil
				botData[bot].MissCount = 0
			end
			return
		end

		local botLevel = bot:GetAttribute("Level") or 1
		local isGiant = botLevel > 20

		-- Calculate base direction
		local baseDirection = (targetPos - origin)
		local dist = baseDirection.Magnitude

		-- For giant bots, add downward angle adjustment to account for size difference
		local direction = baseDirection.Unit
		if isGiant then
			-- Calculate size difference
			local botScale = ScalingConfig.GetSizeMultiplier(botLevel)
			local targetLevel = target:GetAttribute("Level") or (target:FindFirstChild("Humanoid") and 1) or 1
			if target:IsA("Model") then
				local targetPlayer = Players:GetPlayerFromCharacter(target)
				if targetPlayer then
					targetLevel = targetPlayer:GetAttribute("Level") or 1
				end
			end
			local targetScale = ScalingConfig.GetSizeMultiplier(targetLevel)

			-- If bot is much larger, aim slightly downward
			local sizeRatio = botScale / math.max(targetScale, 0.1)
			if sizeRatio > 1.5 then
				-- Calculate downward compensation based on distance and size difference
				local downwardCompensation = math.rad(5 + (sizeRatio - 1.5) * 10) -- 5-30 degrees downward
				local horizontalDist = Vector3.new(baseDirection.X, 0, baseDirection.Z).Magnitude
				local verticalAdjustment = -math.tan(downwardCompensation) * horizontalDist
				direction = (baseDirection + Vector3.new(0, verticalAdjustment, 0)).Unit
			end
		end

		-- === HUMANIZED AIMING: Dynamic Inaccuracy ===
	-- Base spread: worse at range, better up close
	-- INCREASED: Made 3x worse to make bots dodge-able
	local baseSpread = math.clamp(dist / 33, 0.3, 6.0) -- 0.3 at close, 6.0 at 200+ studs
	
	-- Movement penalty: bot is less accurate while moving/strafing
	-- INCREASED: Made 2x worse
	local humanoid = bot:FindFirstChild("Humanoid")
	local movementPenalty = 0
	if humanoid and humanoid.MoveDirection.Magnitude > 0.1 then
		movementPenalty = 2.0 -- Add 2.0 spread while moving (was 1.0)
	end
	
	-- Total spread
	local totalSpread = baseSpread + movementPenalty
	
	-- Apply random spread in 3D
	local inaccuracy = Vector3.new(
		(math.random() - 0.5) * 2,
		(math.random() - 0.5) * 2,
		(math.random() - 0.5) * 2
	) * totalSpread

		local finalDirection = (direction * dist + inaccuracy).Unit
		local rayDir = finalDirection * 300 -- Range

		-- Update last shot time
		botData[bot].LastShot = now

		-- Fire
		local result = castRays(bot, origin, { rayDir }, 1)

		-- Visuals
		replicateShotRemote:FireAllClients(
			tool,
			origin,
			{ { position = origin + rayDir, normal = Vector3.yAxis, instance = nil } }
		)

		-- Damage
		local hitSomething = false
		for _, hit in ipairs(result) do
			if hit.taggedHumanoid then
				hitSomething = true
				local baseDamage = 10
				local victimChar = hit.taggedHumanoid.Parent
				hit.taggedHumanoid:TakeDamage(baseDamage) -- Base damage

				-- Record damage for XP tracking
				DamageTracker.RecordDamage(bot, victimChar, baseDamage)

				if hit.taggedHumanoid.Health <= 0 and eliminatedEvent then
					eliminatedEvent:Fire(nil, bot, hit.taggedHumanoid.Parent, tool)
					ProgressionManager.AddXP(bot, 50)
				end
			end
		end
		
		if hitSomething then
			botData[bot].MissCount = 0
		else
			botData[bot].MissCount = (botData[bot].MissCount or 0) + 1
			if botData[bot].MissCount > 10 then
				-- Reset target if we keep missing
				botData[bot].Target = nil
				botData[bot].MissCount = 0
			end
		end
	end

	-- Update Loop
	-- Queue system for time-slicing bot updates
	local botUpdateQueue = {}
	local BOTS_PER_FRAME = 10 -- Update 10 bots per frame to spread load

	RunService.Heartbeat:Connect(function()
		local now = Workspace:GetServerTimeNow()

		-- Refill queue if empty
		if #botUpdateQueue == 0 then
			local allBots = CollectionService:GetTagged("BotAI")
			-- Shuffle slightly to avoid same order artifacts? Not strictly necessary.
			for _, bot in ipairs(allBots) do
				table.insert(botUpdateQueue, bot)
			end
		end

		-- Process budget
		local processedCount = 0
		while processedCount < BOTS_PER_FRAME and #botUpdateQueue > 0 do
			local bot = table.remove(botUpdateQueue, 1)

			-- Verify bot is still valid
			if not bot or not bot.Parent or not bot:FindFirstChild("Humanoid") or bot.Humanoid.Health <= 0 then
				botData[bot] = nil
				botAggroTable[bot] = nil
				continue
			end

			processedCount = processedCount + 1

			-- Clean up stale aggro entries for this bot
			cleanupAggro(bot, now)

			local root = bot.PrimaryPart
			if not root then
				-- Try to find HumanoidRootPart as fallback
				root = bot:FindFirstChild("HumanoidRootPart")
				if root then
					bot.PrimaryPart = root
				else
					continue -- Skip if no root part
				end
			end

			local data = botData[bot]
				or {
					NextDecision = 0,
					StuckCount = 0,
					LastPos = root.Position,
					LastMovementTime = nil, -- Initialize as nil, set on first stuck detection
					IsRecovering = false,
				}
			botData[bot] = data

			local hum = bot.Humanoid

			-- Get bot scale for scaled thresholds
			local level = bot:GetAttribute("Level") or 1
			local scale = ScalingConfig.GetSizeMultiplier(level)
			local stuckThreshold = 0.5 * scale -- Scale stuck detection with bot size

			-- 1. Improved Stuck Detection (Time-based)
			local movedDistance = (root.Position - data.LastPos).Magnitude
			local moveDirMag = hum.MoveDirection.Magnitude
			local isTryingToMove = moveDirMag > 0.1 -- Use threshold to account for floating point precision

			if movedDistance < stuckThreshold and isTryingToMove then
				-- Bot is trying to move but hasn't moved much
				-- Initialize LastMovementTime on first stuck detection
				if not data.LastMovementTime then
					data.LastMovementTime = now
				end

				local timeStuck = now - data.LastMovementTime

				-- If stuck for 1 second, trigger recovery
				if timeStuck >= 1.0 and not data.IsRecovering then
					data.IsRecovering = true
					data.RecoveryEndTime = now + 0.5 -- Recover for 0.5 seconds

					-- Jump
					hum.Jump = true

					-- Move backward (opposite of current move direction, or random if zero)
					local backwardDir
					if moveDirMag > 0.1 then
						backwardDir = -hum.MoveDirection.Unit
					else
						-- Random direction if MoveDirection is unreliable
						local angle = math.random() * math.pi * 2
						backwardDir = Vector3.new(math.cos(angle), 0, math.sin(angle))
					end
					local backwardPos = root.Position + backwardDir * (10 * scale)
					hum:MoveTo(backwardPos)

					data.NextDecision = now + 0.5 -- Force wait during recovery
				elseif data.IsRecovering and now >= data.RecoveryEndTime then
					-- Recovery complete, resume normal movement
					data.IsRecovering = false
					data.LastMovementTime = now
				end
			else
				-- Bot is moving normally
				if movedDistance >= stuckThreshold then
					data.LastMovementTime = now
					data.IsRecovering = false
				end
			end
			data.LastPos = root.Position

			-- 2. Decision Making (Throttle) - Skip if recovering from stuck
			if now < data.NextDecision or data.IsRecovering then
				continue
			end

			local ranges = getBotRanges(bot)
			local enemy, orb = scanSurroundings(bot, root.Position, ranges.Detect)

			-- === PRIORITY: Orbs over Combat ===
			-- If there's an orb within 50 studs, prioritize it over fighting
			if orb then
				local orbDist = (orb.Position - root.Position).Magnitude
				if orbDist < 50 then
					-- ORB COLLECTION MODE: Prioritize orbs
					hum:MoveTo(orb.Position)
					data.NextDecision = now + 0.3
					
					-- Still shoot at enemies if they're VERY close (< 20 studs) while collecting orbs
					if enemy then
						local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
						if enemyRoot then
							local enemyDist = (enemyRoot.Position - root.Position).Magnitude
							if enemyDist < 20 then
								shootAt(bot, enemy)
							end
						end
					end
					continue
				end
			end

			if enemy then
				-- ATTACK STATE: Move to enemy and shoot
				local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
				if not enemyRoot then
					continue
				end
				
				-- === HUMANIZED BEHAVIOR: Retreat when low health ===
				local healthPercent = hum.Health / hum.MaxHealth
				if healthPercent < 0.3 then
					-- Low health! Try to retreat and find cover
					-- Move away from enemy
					local awayFromEnemy = (root.Position - enemyRoot.Position).Unit
					local retreatPos = root.Position + awayFromEnemy * 30
					
					-- Try to path to retreat position
					hum:MoveTo(retreatPos)
					
					-- Still shoot while retreating (suppressive fire)
					shootAt(bot, enemy)
					
					-- Force next decision soon to re-evaluate
					data.NextDecision = now + 0.5
					continue
				end

				-- Combat Spacing: Maintain distance from enemy
				local toEnemy = (enemyRoot.Position - root.Position)
				local distance = toEnemy.Magnitude
			
			-- Initialize strafe direction if not set
			if not data.StrafeDirection then
				data.StrafeDirection = math.random() > 0.5 and 1 or -1
				data.NextStrafeChange = now + math.random(2, 4)
			end
			
			-- Randomly change strafe direction every 2-4 seconds
			if now >= data.NextStrafeChange then
				data.StrafeDirection = -data.StrafeDirection
				data.NextStrafeChange = now + math.random(2, 4)
			end

			if distance < 15 then
				-- CLOSE RANGE: Strafe/circle around enemy while maintaining distance
				local forward = toEnemy.Unit
				local right = Vector3.new(-forward.Z, 0, forward.X) -- Perpendicular vector
				
				-- Strafe movement: move perpendicular to enemy direction
				-- REDUCED: Was 12, now 6 - less desync for better hit detection
				local strafeOffset = right * (6 * data.StrafeDirection)
				local targetPos = root.Position + strafeOffset
				
				-- Add slight forward/backward component randomly for more dynamic movement
				local fbOffset = math.random(-3, 3)
				targetPos = targetPos + forward * fbOffset
				
				hum:MoveTo(targetPos)
			elseif distance < 30 then
				-- MEDIUM RANGE: Advance while strafing
				local forward = toEnemy.Unit
				local right = Vector3.new(-forward.Z, 0, forward.X)
				
				-- Move toward enemy with some lateral movement
				-- REDUCED: Was 8, now 5 - less desync for better hit detection
				local strafeOffset = right * (5 * data.StrafeDirection)
				local targetPos = enemyRoot.Position + strafeOffset
				
				-- Check if path is clear
				if checkPathClear(bot, root.Position, targetPos, enemy) then
					hum:MoveTo(targetPos)
				else
					-- Path blocked, just strafe
					hum:MoveTo(root.Position + strafeOffset)
				end
			else
					-- Check if path to enemy is clear
					local pathClear = checkPathClear(bot, root.Position, enemyRoot.Position, enemy)

					if pathClear then
						-- Path is clear, move to enemy
						hum:MoveTo(enemyRoot.Position)
					else
						-- Path is blocked, try to move to a position closer that avoids obstacle
						-- Move towards enemy but stop short if blocked
						local direction = toEnemy.Unit

						-- Try moving to a position 70% of the way to enemy
						local alternativePos = root.Position + direction * (distance * 0.7)

						-- Check if alternative path is clear
						if checkPathClear(bot, root.Position, alternativePos, enemy) then
							hum:MoveTo(alternativePos)
						end
						-- If still blocked, don't move but still shoot
					end
				end

				-- Always try to shoot (shooting uses its own raycast that handles obstacles)
				shootAt(bot, enemy)

				-- Note: Removed instant CFrame snap - bots now continue moving while shooting
				-- This makes combat more dynamic and visually appealing

				data.NextDecision = now + 0.1 -- Update 10 times a second during combat
			else
				-- ORB STATE: Always run to nearest orb
				if orb then
					-- Smart Pathfinding: Add random offset to prevent clumping
					local randomOffset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
					local targetOrbPos = orb.Position + randomOffset

					-- Check if path to orb is clear
					local pathClear = checkPathClear(bot, root.Position, targetOrbPos, orb)

					if pathClear then
						-- Path is clear, move to orb with random offset
						hum:MoveTo(targetOrbPos)
					else
						-- Path is blocked, try to find alternative path
						local toOrb = (targetOrbPos - root.Position)
						local distance = toOrb.Magnitude
						local direction = toOrb.Unit

						-- Try moving to a position closer to orb that might avoid obstacle
						local alternativePos = root.Position + direction * (distance * 0.8)

						-- Check if alternative path is clear
						if checkPathClear(bot, root.Position, alternativePos, orb) then
							hum:MoveTo(alternativePos)
						end
						-- If still blocked, skip movement this frame and try again next poll
					end
				end
				data.NextDecision = now + 0.5 -- Poll for orbs every 0.5 seconds
			end
		end
	end)
end

return BotController
