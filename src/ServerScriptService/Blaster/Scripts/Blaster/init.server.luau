local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

-- External Requires
local Constants = require(ReplicatedStorage.Blaster.Constants)
local getRayDirections = require(ReplicatedStorage.Blaster.Utility.getRayDirections)
local castRays = require(ServerScriptService.Utility.castRays)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local DamageTracker = require(ServerScriptService.Services.World.DamageTrackerService)
local AntiExploit = require(ServerScriptService.Utility.AntiExploit)
local ShotReplicator = require(script.ShotReplicator)

-- Start Shot Replicator
ShotReplicator.Start()

-- Lazy Load MetaManager
local MetaProgressionManager = nil
local function getMeta()
	if not MetaProgressionManager then
		pcall(function()
			MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
		end)
	end
	return MetaProgressionManager
end

-- Child Requires
local validateShootArguments = require(script.validateShootArguments)
local validateShot = require(script.validateShot)
local validateReload = require(script.validateReload)

local remotes = ReplicatedStorage.Blaster:WaitForChild("Remotes")
local shootRemote = remotes:WaitForChild("Shoot")
local reloadRemote = remotes:WaitForChild("Reload")
local replicateShotRemote = remotes:WaitForChild("ReplicateShot")
local damageNumberRemote = remotes:WaitForChild("DamageNumber")
local playerDamagedRemote = remotes:WaitForChild("PlayerDamagedEntity", 5)

-- Get the Eliminated Event
local eliminatedEvent
task.spawn(function()
	local eventsFolder = ServerScriptService.Blaster:WaitForChild("Events", 15)
	if eventsFolder then
		eliminatedEvent = eventsFolder:WaitForChild("Eliminated", 15)
	end
end)

local function onShoot(player, now, tool, originCF, tagged)
	-- Validate before processing
	if not AntiExploit.validateShot(player, now, originCF, tool) then
		return -- Reject suspicious shot
	end

	-- 1. Validation
	if not validateShootArguments(now, tool, originCF, tagged) then
		return
	end

	-- Get Player Attributes
	local character = player.Character
	local scale = character and character:GetAttribute("Scale") or 1.0

	-- 2. Raycasting with Impact Scaling
	local spread = tool:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = tool:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = tool:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local baseRayRadius = tool:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE) or 0.5

	-- "Impact" Mutation: Bullets get larger as you get larger
	-- Logic: Base Radius = 0.5. Mutation Impact = Base + (Level * 0.1). Juggernaut Multiplier: * Scale.
	-- Actually prompt says: "Impact Mutation Radius = Base + (Level * 0.1). Juggernaut Size Multiplier: Multiply radius by Scale."

	local impactLevel = 0
	if getMeta() then
		impactLevel = getMeta().GetStatValue(player, "Impact") -- Returns level * 0.1
	end

	local rayRadius = (baseRayRadius + impactLevel) * scale

	local rayDirections = getRayDirections(originCF, raysPerShot, math.rad(spread), now)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end

	local rayResults = castRays(player, originCF.Position, rayDirections, rayRadius)

	-- 3. Damage Logic
	local damage = tool:GetAttribute(Constants.DAMAGE_ATTRIBUTE)

	-- [META] Apply Damage Multiplier
	if getMeta() then
		local dmgMult = getMeta().GetStatMultiplier(player, "Damage")
		damage = damage * dmgMult
	end

	-- Handle Ammo
	if not player:GetAttribute("InfiniteAmmo") then
		local currentAmmo = tool:GetAttribute(Constants.AMMO_ATTRIBUTE)
		if currentAmmo > 0 then
			tool:SetAttribute(Constants.AMMO_ATTRIBUTE, currentAmmo - 1)
		end
	end

	-- Scaling Damage Logic
	local level = player:GetAttribute("Level") or 1
	-- damage = damage * ScalingConfig.GetDamageMultiplier(level) -- Currently 1

	for _, result in ipairs(rayResults) do
		local hitPart = result.instance
		local hitHumanoid = result.taggedHumanoid

		if not hitHumanoid and hitPart then
			hitHumanoid = hitPart.Parent:FindFirstChild("Humanoid")
		end

		if hitHumanoid and hitHumanoid.Health > 0 then
			-- Spawn Protection
			local targetChar = hitHumanoid.Parent
			local spawnTime = targetChar:GetAttribute("SpawnTime")
			if spawnTime and (Workspace:GetServerTimeNow() - spawnTime < 3) then
				continue
			end

			if validateShot(player, now, tool, originCF) then
				local finalDamage = damage

				-- === JUGGERNAUT DAMAGE MODIFIERS ===

				-- 1. Giant Slayer: +15% Damage (per level) to enemies larger than you.
				if getMeta() then
					local slayerBonus = getMeta().GetStatValue(player, "Giant Slayer") -- Returns % e.g., 0.15
					if slayerBonus > 0 then
						local targetScale = targetChar:GetAttribute("Scale") or 1.0
						if targetScale > scale then
							finalDamage = finalDamage * (1 + slayerBonus)
						end
					end
				end

				-- 2. Living Fortress (Target Side): 50% Less dmg from front
				local targetPlayer = Players:GetPlayerFromCharacter(targetChar)
				if targetPlayer and getMeta() then
					local fortress = getMeta().GetStatValue(targetPlayer, "Living Fortress") -- 0.5 if has it
					if fortress > 0 then
						local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
						if targetRoot then
							-- Check angle. Front = Dot Product > 0? No, Front is > 0.5?
							-- Vector from Target to Attacker
							local incomingDir = (originCF.Position - targetRoot.Position).Unit
							local facingDir = targetRoot.CFrame.LookVector
							local dot = incomingDir:Dot(facingDir)

							-- If dot > 0, attacker is in front. (Roughly 180 deg arc)
							if dot > 0 then
								finalDamage = finalDamage * (1 - fortress) -- e.g. * 0.5
								-- print("🛡️ Living Fortress blocked damage!")
							end
						end
					end

					-- 3. Iron Skin (Target Side): Flat Reduction
					local ironSkin = getMeta().GetStatValue(targetPlayer, "Iron Skin") -- Flat val
					if ironSkin > 0 then
						finalDamage = math.max(1, finalDamage - ironSkin)
					end
				end

				-- ===================================

				local willKill = (hitHumanoid.Health - finalDamage) <= 0

				-- Fire Kill Event
				if willKill and eliminatedEvent then
					eliminatedEvent:Fire(nil, player, hitHumanoid.Parent, tool)
				end

				hitHumanoid:TakeDamage(finalDamage)

				-- Lazy load MutationManager
				task.spawn(function()
					local MM = require(ServerScriptService.Services.World.MutationService)
					MM.OnDamage(targetChar, finalDamage, player)
				end)

				-- Record damage for XP tracking
				DamageTracker.RecordDamage(player, targetChar, finalDamage)

				-- Record aggro if target is a bot
				if CollectionService:HasTag(targetChar, "BotAI") then
					local BotController = require(ServerScriptService.Services.Combat.BotService)
					BotController.RecordAggro(targetChar, player)
				end
				
				if playerDamagedRemote then
					playerDamagedRemote:FireClient(player, targetChar)
				end

				-- [META] Vampirism Logic
				if getMeta() then
					local vampMult = getMeta().GetStatMultiplier(player, "Vampirism")
					if vampMult > 1 then
						local healAmount = finalDamage * (vampMult - 1)
						local attackerHum = player.Character and player.Character:FindFirstChild("Humanoid")
						if attackerHum and attackerHum.Health > 0 then
							attackerHum.Health = math.min(attackerHum.Health + healAmount, attackerHum.MaxHealth)
							if damageNumberRemote then
								local head = player.Character:FindFirstChild("Head")
								if head then
									damageNumberRemote:FireClient(
										player,
										-healAmount,
										head.Position + Vector3.new(0, 2, 0),
										false,
										nil
									)
								end
							end
						end
					end
				end

				-- Damage Number
				if damageNumberRemote then
					local hitPosition = result.position
					local xpAmount = willKill and ScalingConfig.GetXPReward(targetChar:GetAttribute("Level") or 1)
						or nil
					damageNumberRemote:FireClient(player, finalDamage, hitPosition, willKill, xpAmount)
				end

				break
			end
		end
	end

	-- Visuals Replication
	local visualRayResults = {}
	for _, r in ipairs(rayResults) do
		table.insert(visualRayResults, {
			position = r.position,
			normal = r.normal,
			instance = r.instance,
		})
	end

	-- Pass scale-adjusted radius to replicator
	ShotReplicator.Buffer(tool, originCF.Position, visualRayResults)
end

local function onReload(player, tool)
	if validateReload(player, tool) then
		local baseMag = tool:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
		local ammoMult = 1
		if getMeta() then
			ammoMult = getMeta().GetStatMultiplier(player, "Ammo")
		end
		local newMagSize = math.floor(baseMag * ammoMult)

		tool:SetAttribute(Constants.AMMO_ATTRIBUTE, newMagSize)
		tool:SetAttribute(Constants.RELOADING_ATTRIBUTE, false)
		reloadRemote:FireAllClients(player, tool)
	end
end

shootRemote.OnServerEvent:Connect(onShoot)
reloadRemote.OnServerEvent:Connect(onReload)
