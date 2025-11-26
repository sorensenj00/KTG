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

	-- 1. Apply Size (ScalingEngine handles the heavy lifting)
	-- We wrap this in pcall just in case ScalingEngine errors out
	task.spawn(function()
		ScalingEngine.ResizeCharacter(character, level)
	end)

	-- 2. Calculate Speed
	local baseSpeed = ScalingConfig.GetWalkSpeed(level)
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
	local lastKnownLevel = player:GetAttribute("Level") or 1

	player:GetAttributeChangedSignal("Level"):Connect(function()
		local newLevel = player:GetAttribute("Level") or 1
		if newLevel ~= lastKnownLevel then
			lastKnownLevel = newLevel
			if player.Character then
				enforceEntityStats(player, player.Character)
			end
		end
	end)
end

-- Helper: Initialize Data
local function initializePlayer(player: Player)
	if not player:GetAttribute("Level") then
		player:SetAttribute("Level", 1)
	end
	if not player:GetAttribute("XP") then
		player:SetAttribute("XP", 0)
	end
	if not player:GetAttribute("Kills") then
		player:SetAttribute("Kills", 0)
	end

	local stats = player:FindFirstChild("leaderstats") or Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player

	-- Size (Primary Stat for Leaderboard)
	local sizeVal = stats:FindFirstChild("Size") or Instance.new("IntValue")
	sizeVal.Name = "Size"
	sizeVal.Value = player:GetAttribute("Level")
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
		sizeVal.Value = newLevel -- Size maps directly to Level
	end)

	player:GetAttributeChangedSignal("Kills"):Connect(function()
		killsVal.Value = player:GetAttribute("Kills")
	end)

	-- Setup reactive scaling via attribute signals
	setupPlayerScaling(player)
end

-- Public API: Add XP
function ProgressionManager.AddXP(target: Instance, amount: number)
	local isPlayer = target:IsA("Player")
	local isBot = target:IsA("Model") and CollectionService:HasTag(target, "BotAI")

	if not (isPlayer or isBot) then
		return
	end

	local currentLevel = target:GetAttribute("Level") or 1
	if currentLevel >= ScalingConfig.MAX_LEVEL then
		return
	end

	local currentXP = target:GetAttribute("XP") or 0
	local totalXP = currentXP + amount
	local levelsGained = 0

	-- Calc Level Up
	while true do
		if currentLevel >= ScalingConfig.MAX_LEVEL then
			totalXP = 0
			break
		end

		local xpRequired = ScalingConfig.GetXPRequired(currentLevel)
		if totalXP >= xpRequired then
			totalXP = totalXP - xpRequired
			currentLevel = currentLevel + 1
			levelsGained = levelsGained + 1
		else
			break
		end
	end

	-- Update Attributes ONLY (The loop will handle the physical growth later)
	target:SetAttribute("Level", currentLevel)
	target:SetAttribute("XP", totalXP)

	-- Track Session XP for meta-progression (only for players)
	if isPlayer and target:IsA("Player") then
		MetaProgressionManager.AddSessionXP(target, amount)
		MetaProgressionManager.AddBiomassFromXP(target, amount)
	end

	if levelsGained > 0 then
		print(string.format("⬆️ %s leveled up to %d (Growth pending next loop)", target.Name, currentLevel))
		if currentLevel >= ScalingConfig.MAX_LEVEL then
			ProgressionManager.PlayerReachedMaxLevel:Fire(target)
		end
	end
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

			humanoid.Died:Connect(function()
				player:SetAttribute("Level", 1)
				player:SetAttribute("XP", 0)
			end)

			-- Meta Check
			local currentLevel = player:GetAttribute("Level") or 1
			if currentLevel == 1 then
				local startMult = MetaProgressionManager.GetStatMultiplier(player, "StartLevel")
				if startMult > 1 then
					player:SetAttribute("Level", 2)
				end
			end

			-- IMMEDIATE Scale on spawn (We don't want them to wait 5 seconds to spawn correctly)
			task.wait(0.2)
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

					-- Award XP to killer (existing behavior)
					if killer then
						local xpAmount = ScalingConfig.KILL_BASE_REWARD
						if victim then
							local victimLevel = victim:GetAttribute("Level") or 1
							xpAmount = ScalingConfig.GetXPReward(victimLevel)
						end
						ProgressionManager.AddXP(killer, xpAmount)

						-- Increment Kill Count
						local currentKills = killer:GetAttribute("Kills") or 0
						killer:SetAttribute("Kills", currentKills + 1)
					end

					-- Award XP to all players who damaged the victim (equal to damage dealt)
					if victimChar then
						local damageDealers = DamageTracker.GetDamageDealers(victimChar)
						for attacker, damageAmount in pairs(damageDealers) do
							-- Only award XP to players, not bots
							if attacker and attacker:IsA("Player") then
								ProgressionManager.AddXP(attacker, damageAmount)
								print(
									string.format(
										"💰 %s earned %d XP from damage dealt to %s",
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
		local lastKnownLevel = bot:GetAttribute("Level") or 1

		-- Setup attribute changed signal for this bot (fires when bot levels up)
		bot:GetAttributeChangedSignal("Level"):Connect(function()
			local newLevel = bot:GetAttribute("Level") or 1
			if newLevel ~= lastKnownLevel then
				lastKnownLevel = newLevel
				if bot:FindFirstChild("Humanoid") and bot.Humanoid.Health > 0 then
					enforceEntityStats(bot, bot)
				end
			end
		end)

		-- Note: No initial enforcement here as bots are already scaled correctly in BotSpawner
	end)

	-- Setup scaling for existing bots
	for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
		local lastKnownLevel = bot:GetAttribute("Level") or 1

		bot:GetAttributeChangedSignal("Level"):Connect(function()
			local newLevel = bot:GetAttribute("Level") or 1
			if newLevel ~= lastKnownLevel then
				lastKnownLevel = newLevel
				if bot:FindFirstChild("Humanoid") and bot.Humanoid.Health > 0 then
					enforceEntityStats(bot, bot)
				end
			end
		end)
	end
end

return ProgressionManager
