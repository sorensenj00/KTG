local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)
local ScalingEngine = require(ServerScriptService.Services.World.ScalingEngineService)
-- local DamageTracker = require(ServerScriptService.Services.World.DamageTrackerService)
-- local XPOrbService = require(ServerScriptService.Services.World.XPOrbService) -- Lazy loaded to avoid cycle

local ProgressionManager = {}

-- Meta-progression
local MetaProgressionManager = nil
local function getMeta()
	if not MetaProgressionManager then
		pcall(function()
			MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
		end)
	end
	return MetaProgressionManager
end

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
		ScalingEngine.UpdateCharacter(character, (entity:GetAttribute("Biomass") :: number?) or 0)
	end)

	-- 2. Calculate Speed
	local baseSpeed = ScalingConfig.GetWalkSpeed(effectiveLevel)
	local speedMult = 1

	-- Apply Meta Multipliers only for players
	if entity:IsA("Player") and getMeta() then
		speedMult = getMeta().GetStatMultiplier(entity, "Speed")
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
	player:GetAttributeChangedSignal("Biomass"):Connect(onStatsChanged) -- CRITICAL: Listen for Biomass changes
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

	-- Force update on respawn
	player.CharacterAdded:Connect(function(newCharacter)
		-- Clear cache to force update
		lastUpdateCache[player] = nil
		
		-- Wait for character to be ready (Humanoid, etc)
		task.spawn(function()
			local humanoid = newCharacter:WaitForChild("Humanoid", 10)
			if humanoid then
				enforceEntityStats(player, newCharacter)
			end
		end)
	end)
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
			
			-- Update Level attribute FIRST so scaling can use it
			target:SetAttribute("Level", currentLevel)
			target:SetAttribute("Biomass", totalBiomass)
			
			-- Update scaling BEFORE healing (so MaxHealth is calculated with new biomass)
			if isPlayer and target:IsA("Player") and target.Character then
				ScalingEngine.UpdateCharacter(target.Character, totalBiomass)
				local humanoid = target.Character:FindFirstChild("Humanoid")
				if humanoid then
					humanoid.Health = humanoid.MaxHealth -- Now heals to the NEW MaxHealth
				end
			elseif isBot and target:IsA("Model") then
				ScalingEngine.UpdateCharacter(target, totalBiomass)
				local humanoid = target:FindFirstChild("Humanoid")
				if humanoid then
					humanoid.Health = humanoid.MaxHealth -- Now heals to the NEW MaxHealth
				end
			end
		else
			break
		end
	end

	-- Update Attributes if not already set during level up
	target:SetAttribute("Level", currentLevel)
	target:SetAttribute("Biomass", totalBiomass)

	-- Force final Scaling Update for smooth scaling (only if we didn't level up)
	-- If we leveled up, scaling was already applied during the level up with full heal
	-- [FIX] Removed unthrottled update here to prevent stutter. 
	-- The attribute change listener (setupPlayerScaling) will handle it with throttling (enforceEntityStats).
	if levelsGained == 0 then
		-- Let the throttled listener handle it
	end

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
		-- Check if it's a character of a player
		local player = Players:GetPlayerFromCharacter(argument)
		if player then
			return player
		end
	end
	return nil
end

-- Initialize Players
Players.PlayerAdded:Connect(initializePlayer)
for _, player in ipairs(Players:GetPlayers()) do
	initializePlayer(player)
end

-- Bot Handling (Listen for new bots)
-- Setup reactive scaling via attribute signals for bots (same as players)
local function setupBotScaling(bot: Model)
	-- Initialize bot attributes if missing
	if not bot:GetAttribute("Level") then bot:SetAttribute("Level", 1) end
	if not bot:GetAttribute("Biomass") then bot:SetAttribute("Biomass", 0) end
	
	-- Setup reactive scaling via attribute signals (replaces expensive polling)
	local function onBotStatsChanged()
		enforceEntityStats(bot, bot)
	end
	
	bot:GetAttributeChangedSignal("Level"):Connect(onBotStatsChanged)
	bot:GetAttributeChangedSignal("Biomass"):Connect(onBotStatsChanged)
	
	-- Also trigger on spawn
	task.spawn(function()
		local humanoid = bot:WaitForChild("Humanoid", 10)
		if humanoid then
			-- Clear cache to force initial update
			lastUpdateCache[bot] = nil
			enforceEntityStats(bot, bot)
		end
	end)
end

CollectionService:GetInstanceAddedSignal("BotAI"):Connect(setupBotScaling)

-- Initialize existing bots
for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
	setupBotScaling(bot)
end

function ProgressionManager.Start()
	print("--- Starting ProgressionManager ---")
	
    local ServiceBus = require(ServerScriptService.Services.ServiceBus)

    -- Listen for AwardBiomass event
    ServiceBus.Get("AwardBiomass").Event:Connect(function(player, amount)
        ProgressionManager.AddBiomass(player, amount)
    end)

	-- Listen for Kills from Blaster System
	task.spawn(function()
		local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
		if not blasterFolder then return end
		
		local eliminatedEvent = blasterFolder:WaitForChild("Events"):WaitForChild("Eliminated", 10)
		if eliminatedEvent then
			eliminatedEvent.Event:Connect(function(_gameState, killerArg, victimArg, _toolArg)
				local killer = resolveEntity(killerArg)
				local victim = resolveEntity(victimArg)
				
				if killer and victim then
					-- Calculate XP Reward
					local victimLevel = victim:GetAttribute("Level") or 1
					local baseXP = 100
					local xpReward = baseXP * victimLevel
					
					-- 50% Direct Award
					local directXP = math.floor(xpReward * 0.5)
					ProgressionManager.AddBiomass(killer, directXP)
					
					-- 50% Dropped as Orbs
					local dropXP = xpReward - directXP
                    
                    if victimArg:IsA("Model") and victimArg.PrimaryPart then
                        ServiceBus.Get("SpawnXPOrbs"):Fire(victimArg.PrimaryPart.Position, dropXP)
                    elseif victimArg:IsA("Model") then
                        -- Fallback if no PrimaryPart
                        local hrp = victimArg:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            ServiceBus.Get("SpawnXPOrbs"):Fire(hrp.Position, dropXP)
                        end
                    end
					
					print(string.format("⚔️ %s killed %s! (+%d XP Direct, +%d XP Orbs)", 
						killer.Name, victim.Name, directXP, dropXP))
				end
			end)
			print("✅ ProgressionManager: Hooked into Blaster Elimination")
		end
	end)
	
	-- NOTE: The 1-second polling loop has been REMOVED.
	-- Scaling is now handled reactively via attribute change signals:
	-- - Players: setupPlayerScaling() connects to Level/XP/Biomass changes
	-- - Bots: setupBotScaling() connects to Level/Biomass changes
	-- This eliminates redundant CPU usage and prevents duplicate updates.
	print("✅ ProgressionManager: Using event-driven scaling (no polling)")
end

return ProgressionManager
