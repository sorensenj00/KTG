local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local KillstreakManager = {}

-- Configuration
local SPEED_BOOST_MULTIPLIER = 1.5
local SPEED_BOOST_DURATION = 20 -- seconds
local SHIELD_DURATION = 10 -- seconds
local NUKE_RADIUS = 100 -- studs
local NUKE_DROP_HEIGHT = 200 -- studs above map

-- Killstreak thresholds
local KILLSTREAK_SPEED = 3
local KILLSTREAK_SHIELD = 5
local KILLSTREAK_NUKE = 10

-- State tracking
local killstreaks = {} -- [player] = killCount
local activeEffects = {} -- [player] = {speedBoost = endTime, shield = endTime}

-- RemoteEvent for client updates
local killstreakRemote = nil

-- Helper to resolve entity (Player or Bot Model)
local function resolveEntity(argument)
	if not argument then
		return nil, false -- entity, isBot
	end

	if typeof(argument) ~= "Instance" then
		return nil, false
	end

	-- 1. Check for Player
	if argument:IsA("Player") then
		return argument, false
	elseif argument:IsA("Model") then
		if CollectionService:HasTag(argument, "BotAI") then
			return argument, true -- Return the Bot Model directly
		end
		return Players:GetPlayerFromCharacter(argument), false
	elseif argument:IsA("Humanoid") then
		local model = argument.Parent
		if CollectionService:HasTag(model, "BotAI") then
			return model, true
		end
		return Players:GetPlayerFromCharacter(model), false
	end
	return nil, false
end

-- Get baseplate center position
local function getBaseplateCenter()
	local baseplate = Workspace:FindFirstChild("Baseplate")
	local pos = Vector3.new(0, 0, 0)
	local size = Vector3.new(100, 1, 100)

	if baseplate then
		if baseplate:IsA("Model") then
			local cf, s = baseplate:GetBoundingBox()
			pos = cf.Position
			size = s
		elseif baseplate:IsA("BasePart") then
			pos = baseplate.Position
			size = baseplate.Size
		end
	end

	return pos, size
end

-- Send killstreak update to client
local function updateClientKillstreak(player, killCount, activeSpeedBoost, activeShield)
	if killstreakRemote and player then
		killstreakRemote:FireClient(player, killCount, activeSpeedBoost, activeShield)
	end
end

-- Apply speed boost
local function applySpeedBoost(player)
	if not player.Character then
		return
	end

	local humanoid = player.Character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local level = player:GetAttribute("Level") or 1
	local baseSpeed = ScalingConfig.GetWalkSpeed(level)
	local boostedSpeed = baseSpeed * SPEED_BOOST_MULTIPLIER

	humanoid.WalkSpeed = boostedSpeed

	-- Store end time
	if not activeEffects[player] then
		activeEffects[player] = {}
	end
	activeEffects[player].speedBoost = tick() + SPEED_BOOST_DURATION

	-- Restore speed after duration
	task.delay(SPEED_BOOST_DURATION, function()
		if player.Character and player.Character:FindFirstChild("Humanoid") then
			local currentLevel = player:GetAttribute("Level") or 1
			local expectedSpeed = ScalingConfig.GetWalkSpeed(currentLevel)
			player.Character.Humanoid.WalkSpeed = expectedSpeed
		end
		if activeEffects[player] then
			activeEffects[player].speedBoost = nil
		end

		-- Update client
		local killCount = killstreaks[player] or 0
		local hasShield = activeEffects[player]
			and activeEffects[player].shield
			and activeEffects[player].shield > tick()
		updateClientKillstreak(player, killCount, false, hasShield or false)
	end)

	print("⚡ Speed boost applied to", player.Name, "for", SPEED_BOOST_DURATION, "seconds")
end

-- Apply shield
local function applyShield(player)
	if not player.Character then
		return
	end

	-- Create ForceField for invincibility
	local forceField = Instance.new("ForceField")
	forceField.Name = "KillstreakShield"
	forceField.Parent = player.Character

	-- Store end time
	if not activeEffects[player] then
		activeEffects[player] = {}
	end
	activeEffects[player].shield = tick() + SHIELD_DURATION

	-- Remove shield after duration
	task.delay(SHIELD_DURATION, function()
		if forceField and forceField.Parent then
			forceField:Destroy()
		end
		if activeEffects[player] then
			activeEffects[player].shield = nil
		end

		-- Update client
		local killCount = killstreaks[player] or 0
		local hasSpeedBoost = activeEffects[player]
			and activeEffects[player].speedBoost
			and activeEffects[player].speedBoost > tick()
		updateClientKillstreak(player, killCount, hasSpeedBoost or false, false)
	end)

	print("🛡️ Shield applied to", player.Name, "for", SHIELD_DURATION, "seconds")
end

-- Spawn nuke (toilet paper roll)
local function spawnNuke(killer)
	local pos, size = getBaseplateCenter()
	local spawnPos = Vector3.new(pos.X, pos.Y + NUKE_DROP_HEIGHT, pos.Z)

	-- Create toilet paper roll model
	local nuke = Instance.new("Model")
	nuke.Name = "Nuke"

	-- Main cylinder (toilet paper roll)
	local mainPart = Instance.new("Part")
	mainPart.Name = "Roll"
	mainPart.Size = Vector3.new(20, 30, 20)
	mainPart.Shape = Enum.PartType.Cylinder
	mainPart.Material = Enum.Material.SmoothPlastic
	mainPart.Color = Color3.fromRGB(255, 255, 255)
	mainPart.Anchored = true
	mainPart.CanCollide = false
	mainPart.CFrame = CFrame.new(spawnPos) * CFrame.Angles(0, 0, math.rad(90))
	mainPart.Parent = nuke

	-- Add glow effect
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = 2
	pointLight.Color = Color3.fromRGB(255, 255, 0)
	pointLight.Range = 50
	pointLight.Parent = mainPart

	-- Add particles
	local attachment = Instance.new("Attachment")
	attachment.Parent = mainPart

	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	particles.Size = NumberSequence.new(2, 5)
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Rate = 50
	particles.Speed = NumberRange.new(5, 10)
	particles.Parent = attachment

	nuke.Parent = Workspace

	-- Animate drop
	local targetPos = Vector3.new(pos.X, pos.Y + size.Y / 2 + 5, pos.Z)
	local dropTime = 2 -- seconds

	local tween =
		TweenService:Create(mainPart, TweenInfo.new(dropTime, Enum.EasingStyle.Linear), { Position = targetPos })

	tween:Play()

	-- Wait for impact
	tween.Completed:Wait()

	-- Explosion effect
	particles.Enabled = false
	pointLight:Destroy()

	-- Create explosion particles
	local explosion = Instance.new("Explosion")
	explosion.Position = targetPos
	explosion.BlastRadius = NUKE_RADIUS
	explosion.BlastPressure = 0 -- Don't push, just damage
	explosion.Visible = true
	explosion.Parent = Workspace

	-- Damage all players in radius (except killer)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	overlapParams.FilterDescendantsInstances = {}

	local sphere = Instance.new("Part")
	sphere.Shape = Enum.PartType.Ball
	sphere.Size = Vector3.new(NUKE_RADIUS * 2, NUKE_RADIUS * 2, NUKE_RADIUS * 2)
	sphere.Position = targetPos
	sphere.Anchored = true
	sphere.CanCollide = false
	sphere.Transparency = 1
	sphere.Parent = Workspace

	local parts = Workspace:GetPartsInPart(sphere, overlapParams)
	local eliminatedEvent = ServerScriptService.Blaster:WaitForChild("Events"):WaitForChild("Eliminated", 5)

	-- Get killer's character to exclude from damage
	local killerCharacter = killer.Character

	for _, part in ipairs(parts) do
		local model = part.Parent
		if model and model:FindFirstChild("Humanoid") then
			local humanoid = model:FindFirstChild("Humanoid")

			-- Skip killer's character
			if model == killerCharacter then
				continue
			end

			if humanoid.Health > 0 then
				local victim, victimIsBot = resolveEntity(model)

				-- Kill the victim
				humanoid.Health = 0

				-- Fire eliminated event
				if eliminatedEvent then
					eliminatedEvent:Fire(nil, killer, model, nil)
				end
			end
		end
	end

	-- Cleanup
	sphere:Destroy()
	task.delay(1, function()
		if nuke and nuke.Parent then
			nuke:Destroy()
		end
	end)

	print("💣 Nuke dropped by", killer.Name)
end

-- Handle kill
local function onKill(killer)
	if not killer or not killer:IsA("Player") then
		return
	end

	-- Increment killstreak
	if not killstreaks[killer] then
		killstreaks[killer] = 0
	end

	killstreaks[killer] = killstreaks[killer] + 1
	local killCount = killstreaks[killer]

	print("📊", killer.Name, "killstreak:", killCount)

	-- Check thresholds
	local hasSpeedBoost = false
	local hasShield = false

	if killCount == KILLSTREAK_SPEED then
		applySpeedBoost(killer)
		hasSpeedBoost = true
	elseif killCount == KILLSTREAK_SHIELD then
		applyShield(killer)
		hasShield = true
	elseif killCount == KILLSTREAK_NUKE then
		spawnNuke(killer)
		-- Reset killstreak after nuke
		killstreaks[killer] = 0
		killCount = 0
	end

	-- Check active effects
	if activeEffects[killer] then
		if activeEffects[killer].speedBoost and activeEffects[killer].speedBoost > tick() then
			hasSpeedBoost = true
		end
		if activeEffects[killer].shield and activeEffects[killer].shield > tick() then
			hasShield = true
		end
	end

	-- Update client
	updateClientKillstreak(killer, killCount, hasSpeedBoost, hasShield)
end

-- Reset killstreak on death
local function onPlayerDeath(player)
	if killstreaks[player] then
		killstreaks[player] = 0
		print("💀", player.Name, "died - killstreak reset")
	end

	-- Clear active effects
	if activeEffects[player] then
		activeEffects[player] = {}
	end

	-- Update client
	updateClientKillstreak(player, 0, false, false)
end

function KillstreakManager.Start()
	print("--- Starting KillstreakManager ---")

	-- Get RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
	killstreakRemote = remotes:WaitForChild("Killstreak")

	-- Listen to Blaster System
	task.spawn(function()
		local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
		if not blasterFolder then
			warn("KillstreakManager: Blaster folder not found")
			return
		end

		local eliminatedEvent = blasterFolder:WaitForChild("Events"):WaitForChild("Eliminated", 10)

		if eliminatedEvent then
			print("✅ KillstreakManager: Hooked into Blaster System!")

			-- Listen for Kills
			eliminatedEvent.Event:Connect(function(_gameState, killerArg, _victimArg, _toolArg)
				local killer, killerIsBot = resolveEntity(killerArg)

				-- Only track player killstreaks (not bots)
				if killer and not killerIsBot and killer:IsA("Player") then
					onKill(killer)
				end
			end)
		else
			warn("⚠️ KillstreakManager: EliminatedEvent not found")
		end
	end)

	-- Track player deaths
	Players.PlayerAdded:Connect(function(player)
		-- Initialize killstreak to 0
		killstreaks[player] = 0
		updateClientKillstreak(player, 0, false, false)

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.Died:Connect(function()
					onPlayerDeath(player)
				end)
			end
		end)
	end)

	-- Handle existing players
	for _, player in ipairs(Players:GetPlayers()) do
		killstreaks[player] = 0
		updateClientKillstreak(player, 0, false, false)

		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					onPlayerDeath(player)
				end)
			end
		end
	end
end

return KillstreakManager
