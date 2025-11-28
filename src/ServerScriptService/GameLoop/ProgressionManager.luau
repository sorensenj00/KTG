local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local ScalingEngine = require(script.Parent.ScalingEngine)
local DamageTracker = require(script.Parent.DamageTracker)

local ProgressionManager = {}

-- Meta-progression
local MetaProgressionManager = require(ServerScriptService.GameLoop.MetaProgressionManager)

ProgressionManager.PlayerReachedMaxLevel = Instance.new("BindableEvent")

-- Cache for throttling updates: [Entity] = lastEffectiveLevel
local lastUpdateCache = {}

-- Helper: Apply Stats to a specific character (Used by the Loop)
local function enforceEntityStats(entity: Instance, character: Model)
	if not character then
		return
	end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local level = entity:GetAttribute("Level") or 1
	local xp = entity:GetAttribute("XP") or 0
	local xpReq = ScalingConfig.GetXPRequired(level)
	
	-- Calculate Effective Level (Float)
	local progress = 0
	if xpReq > 0 then
		progress = math.clamp(xp / xpReq, 0, 0.99)
	end
	local effectiveLevel = level + progress
	
	-- Throttling: Only update if change is significant (> 0.05)
	local lastLevel = lastUpdateCache[entity] or 0
	if math.abs(effectiveLevel - lastLevel) < 0.05 then
		return -- Skip update to save physics
	end
	lastUpdateCache[entity] = effectiveLevel

	-- 1. Apply Size (ScalingEngine handles the heavy lifting)
	-- We wrap this in pcall just in case ScalingEngine errors out
	task.spawn(function()
		ScalingEngine.ResizeCharacter(character, effectiveLevel)
	end)

	-- 2. Calculate Speed
	local baseSpeed = ScalingConfig.GetWalkSpeed(effectiveLevel)
	local speedMult = 1

	-- Apply Meta Multipliers only for players
	if entity:IsA("Player") then
		speedMult = MetaProgressionManager.GetStatMultiplier(entity, "Speed")
	end

	local finalSpeed = baseSpeed * speedMult

	-- 3. Apply Speed (Only if significantly different to reduce replication noise)
	if math.abs(humanoid.WalkSpeed - finalSpeed) > 0.5 then
		humanoid.WalkSpeed = finalSpeed
		-- print("🔧 Enforced Speed for", entity.Name, ":", finalSpeed)
	end
end

-- Helper: Setup player scaling via attribute signals (replaces expensive polling)
local function setupPlayerScaling(player: Player)
	local function onStatsChanged()
		if player.Character then
			enforceEntityStats(player, player.Character)
		end
	end

	player:GetAttributeChangedSignal("Level"):Connect(onStatsChanged)
	player:GetAttributeChangedSignal("XP"):Connect(onStatsChanged)
end

-- Helper: Initialize Data
local function initializePlayer(player: Player)
	if not player:GetAttribute("Level") then
		player:SetAttribute("Level", 1)
	end
	if not player:GetAttribute("Biomass") then
		player:SetAttribute("Biomass", 0)
	end
	if not player:GetAttribute("Kills") then
		player:SetAttribute("Kills", 0)
	end

	local stats = player:FindFirstChild("leaderstats") or Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	-- Biomass (Primary Stat for Leaderboard)
	local sizeVal = stats:FindFirstChild("Biomass") or Instance.new("IntValue")
	sizeVal.Name = "Biomass"
	sizeVal.Value = player:GetAttribute("Biomass")
	sizeVal.Parent = stats

	-- Kills
	local killsVal = stats:FindFirstChild("Kills") or Instance.new("IntValue")
	killsVal.Name = "Kills"
	killsVal.Value = player:GetAttribute("Kills")
	killsVal.Parent = stats

	-- Level (Hidden or Secondary)
	local lvl = stats:FindFirstChild("Level") or Instance.new("IntValue")
	lvl.Name = "Level"
	lvl.Value = player:GetAttribute("Level")
	lvl.Parent = stats

	player:GetAttributeChangedSignal("Level"):Connect(function()
		local newLevel = player:GetAttribute("Level")
		lvl.Value = newLevel
	end)

	player:GetAttributeChangedSignal("Biomass"):Connect(function()
		sizeVal.Value = player:GetAttribute("Biomass")
	end)

	player:GetAttributeChangedSignal("Kills"):Connect(function()
		killsVal.Value = player:GetAttribute("Kills")
	end)

	-- Setup reactive scaling via attribute signals
	setupPlayerScaling(player)
end

-- Public API: Add Biomass (Formerly XP)
function ProgressionManager.AddBiomass(target: Instance, amount: number)
	local isPlayer = target:IsA("Player")
	local isBot = target:IsA("Model") and CollectionService:HasTag(target, "BotAI")

	if not (isPlayer or isBot) then
		return
	end

	local currentLevel = target:GetAttribute("Level") or 1
	if currentLevel >= ScalingConfig.MAX_LEVEL then
		return
	end

	local currentBiomass = target:GetAttribute("Biomass") or 0
	local totalBiomass = currentBiomass + amount
	local levelsGained = 0

	-- Calc Level Up
	while true do
		if currentLevel >= ScalingConfig.MAX_LEVEL then
			totalBiomass = 0
			break
		end

		local biomassRequired = ScalingConfig.GetXPRequired(currentLevel) -- Config still uses "XP" naming for math
		if totalBiomass >= biomassRequired then
			totalBiomass = totalBiomass - biomassRequired
			currentLevel = currentLevel + 1
			levelsGained = levelsGained + 1
			
			-- Heal on level up
			if isPlayer and target:IsA("Player") and target.Character then
				local humanoid = target.Character:FindFirstChild("Humanoid")
				if humanoid then
					humanoid.Health = humanoid.MaxHealth
				end
			elseif isBot and target:IsA("Model") then
				local humanoid = target:FindFirstChild("Humanoid")
				if humanoid then
					humanoid.Health = humanoid.MaxHealth
				end
			end
		else
			break
		end
	end

	-- Update Attributes
	target:SetAttribute("Level", currentLevel)
	target:SetAttribute("Biomass", totalBiomass)

	-- Track Session Data handled in MetaProgression separately now, or not needed?
	-- In new logic: Biomass is the session progress. DNA is the permanent currency.
	-- We don't "add session XP" to meta anymore because meta uses DNA.
	-- However, MetaProgression might want to know for 'Score' or 'Stats'.

	-- Legacy hook for session stats if needed:
	-- if isPlayer and target:IsA("Player") then
	-- 	MetaProgressionManager.AddSessionBiomass(target, amount)
	-- end

	if levelsGained > 0 then
		-- print(string.format("⬆️ %s leveled up to %d", target.Name, currentLevel))
		if currentLevel >= ScalingConfig.MAX_LEVEL then
			ProgressionManager.PlayerReachedMaxLevel:Fire(target)
		end
	end
end

-- Alias for backwards compatibility if needed, but we should switch callers
function ProgressionManager.AddXP(target, amount)
	ProgressionManager.AddBiomass(target, amount)
end

local function resolveEntity(argument)
	if not argument or typeof(argument) ~= "Instance" then
		return nil
	end
	if argument:IsA("Player") then
		return argument
	end
	if argument:IsA("Model") then
		if CollectionService:HasTag(argument, "BotAI") then
			return argument
		end
		return Players:GetPlayerFromCharacter(argument)
	elseif argument:IsA("Humanoid") then
		local model = argument.Parent
		if CollectionService:HasTag(model, "BotAI") then
			return model
		end
		return Players:GetPlayerFromCharacter(model)
	elseif argument:IsA("BasePart") then
		return Players:GetPlayerFromCharacter(argument.Parent)
	end
	return nil
end

function ProgressionManager.Start()
	print("--- Starting ProgressionManager ---")

	-- 1. Character Setup
	local function setupCharacterAdded(player)
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
            if not humanoid then return end

			humanoid.Died:Connect(function()
				--Death Logic: Convert Biomass to DNA and show summary
				local sessionKills = player:GetAttribute("Kills") or 0
				local biomassLost = player:GetAttribute("Biomass") or 0
				local earnedDNA = biomassLost -- 1:1 ratio
				
				-- Add DNA to player via MetaProgressionManager
				if biomassLost > 0 then
					MetaProgressionManager.AddDNA(player, earnedDNA)
				end
				
				-- Fire death summary to client
				task.delay(0.1, function()
					local blaster = ReplicatedStorage:FindFirstChild("Blaster")
					if blaster then
						local remotes = blaster:FindFirstChild("Remotes")
						if remotes then
							local showDeathRemote = remotes:FindFirstChild("ShowDeathSummary")
							if showDeathRemote then
								showDeathRemote:FireClient(player, sessionKills, biomassLost, earnedDNA)
								print(string.format("💀 %s died | Kills: %d | DNA Earned: %d", player.Name, sessionKills, earnedDNA))
							end
						end
					end
				end)
				
				-- Reset stats after death summary  is sent
				task.delay(0.2, function()
					player:SetAttribute("Level", 1)
					player:SetAttribute("Biomass", 0)
					player:SetAttribute("Kills", 0)
				end)
			end)

			-- Meta Check (Born Big)
			local currentLevel = player:GetAttribute("Level") or 1
			if currentLevel == 1 then
				local startMult = MetaProgressionManager.GetStatMultiplier(player, "StartLevel")
				if startMult > 1 then
					player:SetAttribute("Level", 2)
				end
			end

			-- IMMEDIATE Scale on spawn (We don't want them to wait 5 seconds to spawn correctly)
			task.wait(0.2)
			
			-- Force update by clearing cache for this player (New Character = Fresh Start)
			lastUpdateCache[player] = nil
			
			enforceEntityStats(player, character)
		end)
	end

	Players.PlayerAdded:Connect(function(player)
		initializePlayer(player)
		setupCharacterAdded(player)
	end)

	-- 2. Initialize existing
	for _, player in ipairs(Players:GetPlayers()) do
		initializePlayer(player)
		setupCharacterAdded(player)
		if player.Character then
			enforceEntityStats(player, player.Character)
		end
	end

	-- 3. BLASTER SYSTEM HOOK
	task.spawn(function()
		local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
		if blasterFolder then
			local eliminatedEvent = blasterFolder:WaitForChild("Events"):WaitForChild("Eliminated", 10)
			if eliminatedEvent then
				eliminatedEvent.Event:Connect(function(_gameState, killerArg, victimArg)
					local killer = resolveEntity(killerArg)
					local victim = resolveEntity(victimArg)

					-- Get victim character model for damage tracking
					local victimChar = nil
					if victimArg then
						if victimArg:IsA("Model") then
							-- Could be character model or bot model - both use the model itself
							victimChar = victimArg
						elseif victimArg:IsA("Humanoid") or victimArg:IsA("BasePart") then
							victimChar = victimArg.Parent
						elseif victimArg:IsA("Player") then
							victimChar = victimArg.Character
						end
					end

					-- Award Biomass to killer
					if killer then
						local xpAmount = ScalingConfig.KILL_BASE_REWARD
						if victim then
							local victimLevel = victim:GetAttribute("Level") or 1
							xpAmount = ScalingConfig.GetXPReward(victimLevel)
						end
						ProgressionManager.AddBiomass(killer, xpAmount)

						-- Increment Kill Count
						local currentKills = killer:GetAttribute("Kills") or 0
						killer:SetAttribute("Kills", currentKills + 1)
					end

					-- Award Biomass to all players who damaged the victim (equal to damage dealt)
					if victimChar then
						local damageDealers = DamageTracker.GetDamageDealers(victimChar)
						for attacker, damageAmount in pairs(damageDealers) do
							-- Only award to players, not bots
							if attacker and attacker:IsA("Player") then
								ProgressionManager.AddBiomass(attacker, damageAmount)
								print(
									string.format(
										"💰 %s earned %d Biomass from damage dealt to %s",
										attacker.Name,
										damageAmount,
										victimChar.Name
									)
								)
							end
						end

						-- Clear damage data for this victim
						DamageTracker.ClearVictimData(victimChar)
					end
				end)
			end
		end
	end)

	-- =====================================================
	-- ✅ REACTIVE SCALING VIA ATTRIBUTE SIGNALS (Replaces expensive polling)
	-- =====================================================
	-- Setup reactive scaling for bots via CollectionService tag events
	CollectionService:GetInstanceAddedSignal("BotAI"):Connect(function(bot)
		local function onBotStatsChanged()
			if bot:FindFirstChild("Humanoid") and bot.Humanoid.Health > 0 then
				enforceEntityStats(bot, bot)
			end
		end

		-- Setup attribute changed signal for this bot (fires when bot levels up or gains XP)
		bot:GetAttributeChangedSignal("Level"):Connect(onBotStatsChanged)
		bot:GetAttributeChangedSignal("XP"):Connect(onBotStatsChanged)

		-- Note: No initial enforcement here as bots are already scaled correctly in BotSpawner
	end)

	-- Setup scaling for existing bots
	for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
		local function onBotStatsChanged()
			if bot:FindFirstChild("Humanoid") and bot.Humanoid.Health > 0 then
				enforceEntityStats(bot, bot)
			end
		end

		bot:GetAttributeChangedSignal("Level"):Connect(onBotStatsChanged)
		bot:GetAttributeChangedSignal("XP"):Connect(onBotStatsChanged)
	end
	
	-- =====================================================
	-- 🔄 RESPAWN HANDLER
	-- =====================================================
	task.spawn(function()
		local blaster = ReplicatedStorage:WaitForChild("Blaster", 10)
		if blaster then
			local remotes = blaster:WaitForChild("Remotes", 10)
			if remotes then
				local respawnRemote = remotes:WaitForChild("RequestRespawn", 10)
				if respawnRemote then
					respawnRemote.OnServerEvent:Connect(function(player)
						if player.Character then
							player.Character:BreakJoints() -- Kills the player
						end
						task.wait(0.1)
						player:LoadCharacter() -- Respawns them
						print(string.format("�� %s respawned", player.Name))
					end)
					print("✅ ProgressionManager: Respawn handler connected")
				end
			end
		end
	end)
end

return ProgressionManager
