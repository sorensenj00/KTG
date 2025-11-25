--[[
    Module: Handler
    Description: Server-side Blaster Logic.
    Updates:
    - Broadcasts ReplicateShot to All Clients for global visuals.
    
    Author: System
    Last Updated: 2025-01-20
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- External Requires
local Constants = require(ReplicatedStorage.Blaster.Constants)
local getRayDirections = require(ReplicatedStorage.Blaster.Utility.getRayDirections)
local castRays = require(ServerScriptService.Utility.castRays)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local DamageTracker = require(ServerScriptService.GameLoop.DamageTracker)
local AntiExploit = require(ServerScriptService.Utility.AntiExploit)
local GameConfig = require(ReplicatedStorage.GameLoop.GameConfig)

-- Lazy Load MetaManager
local MetaProgressionManager = nil
local function getMeta()
	if not MetaProgressionManager then
		pcall(function()
			MetaProgressionManager = require(ServerScriptService.GameLoop.MetaProgressionManager)
		end)
	end
	return MetaProgressionManager
end

-- Child Requires (validation scripts)
local validateShootArguments = require(ServerScriptService.Blaster.Scripts.Blaster.validateShootArguments)
local validateShot = require(ServerScriptService.Blaster.Scripts.Blaster.validateShot)
local validateReload = require(ServerScriptService.Blaster.Scripts.Blaster.validateReload)

-- Get Remotes
local remotes = ReplicatedStorage.Blaster:WaitForChild("Remotes")
local shootRemote = remotes:WaitForChild("Shoot")
local reloadRemote = remotes:WaitForChild("Reload")
local replicateShotRemote = remotes:WaitForChild("ReplicateShot")
local damageNumberRemote = remotes:WaitForChild("DamageNumber")

-- Get the Eliminated Event
local eliminatedEvent
task.spawn(function()
	local eventsFolder = ServerScriptService.Blaster:WaitForChild("Events", 15)
	if eventsFolder then
		eliminatedEvent = eventsFolder:WaitForChild("Eliminated", 15)
	end
end)

local function onShoot(player, now, tool, originCF, tagged)
	if not AntiExploit.validateShot(player, now, originCF, tool) then
		return
	end
	if not validateShootArguments(now, tool, originCF, tagged) then
		return
	end

	local spread = tool:GetAttribute(Constants.SPREAD_ATTRIBUTE) or GameConfig.Weapons.DefaultSpread
	local raysPerShot = tool:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE) or 1
	local range = tool:GetAttribute(Constants.RANGE_ATTRIBUTE) or GameConfig.Weapons.DefaultRange
	local rayRadius = tool:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE) or 0.1

	local rayDirections = getRayDirections(originCF, raysPerShot, math.rad(spread), now)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end

	local rayResults = castRays(player, originCF.Position, rayDirections, rayRadius)
	local damage = tool:GetAttribute(Constants.DAMAGE_ATTRIBUTE) or GameConfig.Weapons.DefaultDamage

	if getMeta() then
		local dmgMult = getMeta().GetStatMultiplier(player, "Damage")
		damage = damage * dmgMult
	end

	if not player:GetAttribute("InfiniteAmmo") then
		local currentAmmo = tool:GetAttribute(Constants.AMMO_ATTRIBUTE)
		if currentAmmo > 0 then
			tool:SetAttribute(Constants.AMMO_ATTRIBUTE, currentAmmo - 1)
		end
	end

	local level = player:GetAttribute("Level") or 1
	local damageMult = 1 + ((level - 1) * 0.1)
	damage = damage * damageMult

	for _, result in ipairs(rayResults) do
		local hitPart = result.instance
		local hitHumanoid = result.taggedHumanoid

		if not hitHumanoid and hitPart then
			hitHumanoid = hitPart.Parent:FindFirstChild("Humanoid")
		end

		if hitHumanoid and hitHumanoid.Health > 0 then
			local targetChar = hitHumanoid.Parent
			local spawnTime = targetChar:GetAttribute("SpawnTime")
			if spawnTime and (Workspace:GetServerTimeNow() - spawnTime < 3) then
				continue
			end

			if validateShot(player, now, tool, originCF) then
				local finalDamage = damage

				local willKill = (hitHumanoid.Health - finalDamage) <= 0

				if willKill and eliminatedEvent then
					eliminatedEvent:Fire(nil, player, hitHumanoid.Parent, tool)
				end

				hitHumanoid:TakeDamage(finalDamage)
				DamageTracker.RecordDamage(player, targetChar, finalDamage)

				if CollectionService:HasTag(targetChar, "BotAI") then
					local BotController = require(ServerScriptService.GameLoop.BotController)
					BotController.RecordAggro(targetChar, player)
				end

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

				if damageNumberRemote then
					local hitPosition = result.position
					local head = targetChar:FindFirstChild("Head")
					if head then
						hitPosition = head.Position + Vector3.new(0, 2, 0)
					end
					local xpAmount = willKill and ScalingConfig.GetXPReward(targetChar:GetAttribute("Level") or 1)
						or nil
					damageNumberRemote:FireClient(player, finalDamage, hitPosition, willKill, xpAmount)
				end

				break
			end
		end
	end

	-- Visuals Replication: Fire All Clients (Client handles skipping self)
	local visualRayResults = {}
	for _, r in ipairs(rayResults) do
		table.insert(visualRayResults, { position = r.position, normal = r.normal, instance = r.instance })
	end
	replicateShotRemote:FireAllClients(tool, originCF.Position, visualRayResults)
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

-- Connect Remote Events
shootRemote.OnServerEvent:Connect(onShoot)
reloadRemote.OnServerEvent:Connect(onReload)

return nil
