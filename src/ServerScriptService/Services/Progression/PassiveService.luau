--[[
    Module: PassiveManager
    Description: Handles passive/idle mechanics like Regeneration, Photosynthesis, and Toxic Aura.

    Dependencies:
    - ServerScriptService.GameLoop.MetaProgressionManager
    - ServerScriptService.GameLoop.ProgressionManager
    - ReplicatedStorage.GameLoop.MetaConfig

    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
local ProgressionManager = require(ServerScriptService.Services.Progression.ProgressionService)
local MetaConfig = require(ReplicatedStorage.GameLoop.MetaConfig)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local PassiveManager = {}

-- Reference to Eliminated event for kill credit
local eliminatedEvent = nil

-- Helper to deal damage with kill credit
local function dealDamageWithCredit(attacker, victimHumanoid, damage, _sourceName)
	if not victimHumanoid or victimHumanoid.Health <= 0 then
		return
	end

	local willKill = (victimHumanoid.Health - damage) <= 0

	if willKill and eliminatedEvent then
		-- Fire kill event - attacker can be Player or Character (for bots)
		local attackerEntity = attacker
		if typeof(attacker) == "Instance" and attacker:IsA("Model") then
			-- It's a character, try to get player
			attackerEntity = Players:GetPlayerFromCharacter(attacker) or attacker
		end
		eliminatedEvent:Fire(nil, attackerEntity, victimHumanoid.Parent, nil)
	end

	victimHumanoid:TakeDamage(damage)
end

-- Constants
local TICK_RATE = 1.0 -- Run passives every 1 second
local SCAVENGER_UPDATE_RATE = 0.2 -- Run scavenger every 0.2 seconds
local HEAVY_STEPS_UPDATE_RATE = 0.25 -- Check Heavy Steps every 0.25 seconds
local AURA_RANGE_BASE = 15
local SCAVENGER_RANGE_BASE = 10
local SCAVENGER_SPEED = 25 -- Studs per second attraction (Increased for Gravitational Pull feel)
local HEAVY_STEPS_MIN_SCALE = 3 -- Minimum scale to activate Heavy Steps
local HEAVY_STEPS_DAMAGE_BASE = 10 -- Base damage per tick
local HEAVY_STEPS_RANGE = 5 -- Range to check for enemies (scales with player size)

-- Momentum constants
local MOMENTUM_CHARGE_TIME = 3 -- Seconds of running to activate
local MOMENTUM_SPEED_BONUS_PER_SECOND = 2 -- Speed bonus per second after activation
local MOMENTUM_MAX_BONUS = 50 -- Cap the bonus speed
local MOMENTUM_DIRECTION_TOLERANCE = 0.85 -- Dot product threshold for "straight line"

-- State
local scavengerAccumulator = 0
local heavyStepsAccumulator = 0

-- Momentum tracking per player: { [Player] = { startTime, lastDirection, isActive, bonusSpeed } }
local momentumState = {}

-- Helper: Get Nearby Enemies
local function getNearbyEnemies(centerPos, range, ignorePlayer)
	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { ignorePlayer.Character }
	params.FilterType = Enum.RaycastFilterType.Exclude

	local parts = workspace:GetPartBoundsInRadius(centerPos, range, params)
	local enemiesHit = {}

	for _, part in ipairs(parts) do
		local model = part.Parent
		if model and model:FindFirstChild("Humanoid") and model ~= ignorePlayer.Character then
			-- Avoid double hitting the same model
			if not enemiesHit[model] then
				enemiesHit[model] = true
			end
		end
	end

	return enemiesHit
end

-- Helper: Apply Toxic Aura Damage
local function applyToxicAura(player, character, level)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local dps = MetaProgressionManager.GetStatValue(player, "Toxic Aura")
	if dps <= 0 then
		return
	end

	local enemies = getNearbyEnemies(root.Position, AURA_RANGE_BASE + (level * 1), player)

	for enemyModel, _ in pairs(enemies) do
		local humanoid = enemyModel:FindFirstChild("Humanoid")
		if humanoid and humanoid.Health > 0 then
			-- Credit kill to the player with Toxic Aura
			dealDamageWithCredit(player, humanoid, dps, "Toxic Aura")
		end
	end
end

-- Helper: Momentum Logic (Uncapped speed after running straight for 3s)
local function updateMomentum(player, character, dt)
	local hasMomentum = MetaProgressionManager.GetStatValue(player, "Momentum")
	if not hasMomentum or hasMomentum == 0 then
		-- Clear state if they don't have the mutation
		if momentumState[player] then
			character:SetAttribute("MomentumBonus", 0)
			momentumState[player] = nil
		end
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local moveDir = humanoid.MoveDirection
	local isMoving = moveDir.Magnitude > 0.1

	-- Initialize state if needed
	if not momentumState[player] then
		momentumState[player] = {
			startTime = 0,
			lastDirection = Vector3.zero,
			isActive = false,
			bonusSpeed = 0,
			runTime = 0,
		}
	end

	local state = momentumState[player]

	if not isMoving then
		-- Reset momentum when stopped
		state.runTime = 0
		state.isActive = false
		state.bonusSpeed = 0
		state.lastDirection = Vector3.zero
		character:SetAttribute("MomentumBonus", 0)
		return
	end

	-- Check if running in roughly the same direction
	local normalizedDir = moveDir.Unit
	if state.lastDirection.Magnitude > 0 then
		local dot = normalizedDir:Dot(state.lastDirection)
		if dot < MOMENTUM_DIRECTION_TOLERANCE then
			-- Changed direction, reset
			state.runTime = 0
			state.isActive = false
			state.bonusSpeed = 0
		end
	end

	state.lastDirection = normalizedDir
	state.runTime = state.runTime + dt

	if state.runTime >= MOMENTUM_CHARGE_TIME then
		-- Momentum is active!
		state.isActive = true

		-- Calculate bonus speed (increases over time)
		local activeTime = state.runTime - MOMENTUM_CHARGE_TIME
		state.bonusSpeed = math.min(activeTime * MOMENTUM_SPEED_BONUS_PER_SECOND, MOMENTUM_MAX_BONUS)

		-- Apply speed bonus via attribute (ScalingEngine or direct)
		character:SetAttribute("MomentumBonus", state.bonusSpeed)

		-- Apply directly to humanoid (in addition to base speed)
		local baseSpeed = humanoid.WalkSpeed - (character:GetAttribute("MomentumBonus") or 0)
		humanoid.WalkSpeed = baseSpeed + state.bonusSpeed
	else
		state.bonusSpeed = 0
		character:SetAttribute("MomentumBonus", 0)
	end
end

-- Helper: Heavy Steps Logic (Walking damages enemies if Scale > 3)
local function updateHeavySteps(player, character)
	local hasHeavySteps = MetaProgressionManager.GetStatValue(player, "Heavy Steps")
	if not hasHeavySteps or hasHeavySteps == 0 then
		return
	end

	local scale = character:GetAttribute("Scale") or 1
	if scale < HEAVY_STEPS_MIN_SCALE then
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	-- Only deal damage if actually moving
	local moveDir = humanoid.MoveDirection
	if moveDir.Magnitude < 0.1 then
		return
	end

	-- Calculate damage based on scale
	local damage = HEAVY_STEPS_DAMAGE_BASE * (scale / HEAVY_STEPS_MIN_SCALE)
	local range = HEAVY_STEPS_RANGE * scale

	-- Find enemies in range
	local enemies = getNearbyEnemies(root.Position, range, player)

	for enemyModel, _ in pairs(enemies) do
		local enemyHum = enemyModel:FindFirstChild("Humanoid")
		if enemyHum and enemyHum.Health > 0 then
			-- Only damage smaller enemies
			local enemyScale = enemyModel:GetAttribute("Scale") or 1
			if enemyScale < scale then
				-- Credit kill to the player with Heavy Steps
				dealDamageWithCredit(player, enemyHum, damage, "Heavy Steps")
			end
		end
	end
end

-- Helper: Scavenger / Magnetism Logic
local function updateScavenger(player, character, rangeBoost, dt)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local range = SCAVENGER_RANGE_BASE + rangeBoost

	-- Find Orbs
	local orbFolder = workspace:FindFirstChild("Orbs")
	if not orbFolder then
		return
	end

	-- Optimization: Only check if Orbs exist
	if #orbFolder:GetChildren() == 0 then
		return
	end

	local params = OverlapParams.new()
	params.FilterDescendantsInstances = { orbFolder }
	params.FilterType = Enum.RaycastFilterType.Include

	local nearbyOrbs = workspace:GetPartBoundsInRadius(root.Position, range, params)

	-- We track processed orbs to avoid moving the hitbox AND the orb part twice
	local processedOrbs = {}

	for _, part in ipairs(nearbyOrbs) do
		local orb = nil
		if part.Name == "XPOrb" then
			orb = part
		elseif part.Name == "Hitbox" then
			orb = part.Parent
		end

		if orb and orb:IsA("BasePart") and not processedOrbs[orb] then
			processedOrbs[orb] = true

			-- Pull orb towards player using smooth CFrame interpolation
			local currentPos = orb.Position
			local targetPos = root.Position
			local dir = (targetPos - currentPos).Unit

			-- Move based on speed * dt
			local moveStep = dir * (SCAVENGER_SPEED * 1.5 * dt)

			-- Don't overshoot
			local dist = (targetPos - currentPos).Magnitude
			if moveStep.Magnitude >= dist then
				orb.Position = targetPos
			else
				orb.Position = currentPos + moveStep
			end

			-- Ensure touch triggers if very close
			if dist < 4 then
				-- Teleport into player to force touch event
				orb.Position = root.Position
			end
		end
	end
end

-- Main Loop Function (Slow Tick)
local function onTick()
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 then
			-- 1. Regeneration
			local regenLevel = MetaProgressionManager.GetStatValue(player, "Regeneration")
			if regenLevel > 0 then
				local hum = character.Humanoid
				if hum.Health < hum.MaxHealth then
					hum.Health = math.min(hum.Health + regenLevel, hum.MaxHealth)
				end
			end

			-- 2. Photosynthesis (Passive Biomass)
			local photoLevel = MetaProgressionManager.GetStatValue(player, "Photosynthesis")
			if photoLevel > 0 then
				ProgressionManager.AddBiomass(player, photoLevel)
			end

			-- 3. Toxic Aura
			local auraLevel = MetaProgressionManager.GetStatValue(player, "Toxic Aura")
			if auraLevel > 0 then
				applyToxicAura(player, character, auraLevel)
			end
		end
	end
end

-- Scavenger Loop (Fast Heartbeat)
local function onHeartbeat(dt)
	scavengerAccumulator = scavengerAccumulator + dt
	heavyStepsAccumulator = heavyStepsAccumulator + dt

	-- Heavy Steps check
	if heavyStepsAccumulator >= HEAVY_STEPS_UPDATE_RATE then
		heavyStepsAccumulator = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				updateHeavySteps(player, character)
			end
		end
	end

	-- Momentum update (runs every frame for smooth speed changes)
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			updateMomentum(player, character, dt)
		end
	end

	if scavengerAccumulator >= SCAVENGER_UPDATE_RATE then
		local stepDt = scavengerAccumulator
		scavengerAccumulator = 0

		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				-- NEW: Gravitational Pull Scaling
				-- Base + (Scale * 20%)
				-- Or mutation "Gravitational Pull" value?
				-- Config says "Your Orb Pickup Range scales with your Size."
				-- Mutation "Gravitational Pull" returns: level * 0.2 (20% per level)

				local gravPull = MetaProgressionManager.GetStatValue(player, "Gravitational Pull") -- e.g., 0.2
				local scale = character:GetAttribute("Scale") or 1

				-- Range Boost Calculation
				-- If they have mutation, range scales with size.
				-- Let's say: Boost = BaseRange * (Scale * gravPull)
				-- If gravPull is 0, boost is 0.
				local rangeBoost = 0
				if gravPull > 0 then
					rangeBoost = SCAVENGER_RANGE_BASE * (scale * gravPull)
				end

				-- Legacy "Magnetism" stat?
				local magLegacy = MetaProgressionManager.GetStatValue(player, "Magnetism")
				rangeBoost = rangeBoost + magLegacy

				if rangeBoost > 0 then
					updateScavenger(player, character, rangeBoost, stepDt)
				end
			end
		end
	end
end

function PassiveManager.Start()
	print("--- Starting PassiveManager ---")

	-- Get reference to Eliminated event for kill credit
	task.spawn(function()
		local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
		if blasterFolder then
			local eventsFolder = blasterFolder:WaitForChild("Events", 10)
			if eventsFolder then
				eliminatedEvent = eventsFolder:WaitForChild("Eliminated", 10)
				if eliminatedEvent then
					print("✅ PassiveManager: Connected to Eliminated event for kill credit")
				end
			end
		end
	end)

	-- Clean up momentum state when players leave
	Players.PlayerRemoving:Connect(function(player)
		momentumState[player] = nil
	end)

	-- Start the Tick Loop
	task.spawn(function()
		while true do
			onTick()
			task.wait(TICK_RATE)
		end
	end)

	-- Start Scavenger Loop
	RunService.Heartbeat:Connect(onHeartbeat)
end

return PassiveManager
