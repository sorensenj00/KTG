local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")

local MetaConfig = require(ReplicatedStorage.GameLoop.MetaConfig)

local MetaProgressionManager = {}

-- Check if running in Studio (DataStore not available)
local IS_STUDIO = RunService:IsStudio()

-- DataStore setup (only if not in Studio)
local DATASTORE_NAME = "MetaProgression"
local datastore = not IS_STUDIO and DataStoreService:GetDataStore(DATASTORE_NAME) or nil

-- Player data cache
local playerData = {}
-- Structure:
-- {
--    GlobalXP = 0 (This is DNA/Currency),
--    Biomass = 0 (This is Lifetime DNA earned, used for Tiers/Unlocks),
--    Upgrades = {...},
--    SessionKills = 0
-- }

-- Remotes
local purchaseUpgradeRemote
local updateMetaStatsRemote
local requestMetaDataRemote
local showDeathSummaryRemote
local requestRespawnRemote
local harvestRemote

-- Helper to get all upgrade stat names from config
local function getAllUpgradeNames()
	local upgradeNames = {}
	for tier, upgrades in pairs(MetaConfig.Upgrades) do
		for statName, _ in pairs(upgrades) do
			upgradeNames[statName] = true
		end
	end
	return upgradeNames
end

-- Default data structure
local function getDefaultData()
	local defaultUpgrades = {}
	local allUpgrades = getAllUpgradeNames()
	for statName, _ in pairs(allUpgrades) do
		defaultUpgrades[statName] = 0
	end

	return {
		GlobalXP = 0, -- Current DNA (Spendable)
		Biomass = 0,  -- Lifetime DNA (Unlock Progress)
		Upgrades = defaultUpgrades,
		SessionKills = 0,
	}
end

-- Load player data from DataStore
local function loadPlayerData(player: Player)
	-- Skip DataStore in Studio mode
	if IS_STUDIO then
		playerData[player] = getDefaultData()
		print("📝 Studio mode: Using default data for", player.Name)
		return
	end

	local success, data = pcall(function()
		return datastore:GetAsync("Player_" .. player.UserId)
	end)

	if success and data then
		-- Validate data structure
		if typeof(data) == "table" and data.GlobalXP and data.Upgrades then
			-- Handle migration: if Biomass is missing, set it to current GlobalXP
			local biomass = data.Biomass
			if biomass == nil then
				biomass = data.GlobalXP or 0
			end

			-- Load all upgrade stats
			local allUpgrades = getAllUpgradeNames()
			local upgrades = {}
			for statName, _ in pairs(allUpgrades) do
				upgrades[statName] = (data.Upgrades and data.Upgrades[statName]) or 0
			end

			playerData[player] = {
				GlobalXP = data.GlobalXP or 0,
				Biomass = biomass,
				Upgrades = upgrades,
				SessionKills = 0,
			}
			print("✅ Loaded meta-progression data for", player.Name)
		else
			-- Invalid data, use defaults
			playerData[player] = getDefaultData()
			print("⚠️ Invalid data structure for", player.Name, "- using defaults")
		end
	else
		-- No data or error, use defaults
		playerData[player] = getDefaultData()
		if not success then
			warn("❌ Failed to load data for", player.Name, ":", data)
		end
	end
end

-- Save player data to DataStore with retry logic
local function savePlayerData(player: Player)
	if not playerData[player] then
		return
	end

	-- Skip DataStore in Studio mode
	if IS_STUDIO then
		print("📝 Studio mode: Skipping save for", player.Name)
		return true
	end

	-- Save all upgrade stats dynamically
	local allUpgrades = getAllUpgradeNames()
	local upgradesToSave = {}
	for statName, _ in pairs(allUpgrades) do
		upgradesToSave[statName] = playerData[player].Upgrades[statName] or 0
	end

	local dataToSave = {
		GlobalXP = playerData[player].GlobalXP,
		Biomass = playerData[player].Biomass or 0,
		Upgrades = upgradesToSave,
	}

	local maxRetries = 3
	local retryDelay = 1

	for attempt = 1, maxRetries do
		local success, err = pcall(function()
			datastore:SetAsync("Player_" .. player.UserId, dataToSave)
		end)

		if success then
			print("✅ Saved meta-progression data for", player.Name)
			return true
		else
			warn("❌ Failed to save data for", player.Name, "(attempt", attempt, "/", maxRetries, "):", err)
			if attempt < maxRetries then
				task.wait(retryDelay)
				retryDelay = retryDelay * 2 -- Exponential backoff
			end
		end
	end

	return false
end

-- Handle player death - Conversion Logic
local function onPlayerDeath(player: Player)
	if not playerData[player] then
		return
	end

	local sessionKills = playerData[player].SessionKills or 0
	
	-- Get Current Biomass (Size/XP) from Player Attributes
	local currentBiomass = player:GetAttribute("Biomass") or 0

	-- Calculate DNA from Kills (Small bonus)
	local dnaFromKills = sessionKills * MetaConfig.DNA_PER_KILL

	-- Calculate DNA from Biomass Conversion (20% retained)
	local dnaFromBiomass = math.floor(currentBiomass * MetaConfig.DEATH_BIOMASS_CONVERSION_PCT)

	local totalDnaEarned = dnaFromKills + dnaFromBiomass

	if totalDnaEarned > 0 then
		-- Add to Wallet (GlobalXP/DNA)
		playerData[player].GlobalXP = playerData[player].GlobalXP + totalDnaEarned

		-- Add to Lifetime Stats (Biomass/LifetimeDNA)
		playerData[player].Biomass = (playerData[player].Biomass or 0) + totalDnaEarned

		print(string.format("💀 %s Died. Converted %d Biomass -> %d DNA. Kills: %d (+%d DNA). Total Earned: %d DNA",
			player.Name, currentBiomass, dnaFromBiomass, sessionKills, dnaFromKills, totalDnaEarned))

		-- Save to DataStore
		savePlayerData(player)

		-- Notify client with death summary
		if showDeathSummaryRemote then
			showDeathSummaryRemote:FireClient(player, sessionKills, currentBiomass, totalDnaEarned)
		end

		-- Notify client with updated stats
		if updateMetaStatsRemote then
			updateMetaStatsRemote:FireClient(
				player,
				playerData[player].GlobalXP,
				playerData[player].Upgrades,
				playerData[player].Biomass
			)
		end
	end

	-- Notify client with death summary (ALWAYS show this, even if 0 GXP earned)
	if showDeathSummaryRemote then
		showDeathSummaryRemote:FireClient(player, sessionKills, currentBiomass, totalDnaEarned)
	end

	-- Reset session data
	playerData[player].SessionKills = 0
	
	-- CRITICAL: Reset player size/progress on death
	-- The "Reward" was calculated above based on current biomass. Now we must reset it.
	player:SetAttribute("Biomass", 0)
	player:SetAttribute("Level", 1)
end

-- Public API: Add GlobalXP (DNA) directly
function MetaProgressionManager.AddDNA(player: Player, amount: number)
	if not playerData[player] then
		return
	end
	
	amount = math.floor(amount)
	playerData[player].GlobalXP = (playerData[player].GlobalXP or 0) + amount
	playerData[player].Biomass = (playerData[player].Biomass or 0) + amount
	
	-- Save to DataStore
	savePlayerData(player)
	
	-- Notify client
	if updateMetaStatsRemote then
		updateMetaStatsRemote:FireClient(
			player,
			playerData[player].GlobalXP,
			playerData[player].Upgrades,
			playerData[player].Biomass
		)
	end
end

-- HARVEST FUNCTION (The "Bank" mechanic)
function MetaProgressionManager.Harvest(player: Player)
	if not playerData[player] then return false end

	-- 1. Validate State (Check if player is in Safe Zone? - Logic should be handled by caller or checked via attribute)
	-- For now, we trust the caller (Remote/Manager) to verify location.

	-- 2. Get Current Biomass
	local currentBiomass = player:GetAttribute("Biomass") or 0
	if currentBiomass <= 0 then
		return false
	end
	
	-- 3. Calculate DNA (100% Conversion)
	local dnaEarned = math.floor(currentBiomass)

	-- 4. Apply DNA
	MetaProgressionManager.AddDNA(player, dnaEarned)

	print(string.format("🌾 %s Harvested! Converted %d Biomass -> %d DNA.", player.Name, currentBiomass, dnaEarned))

	-- 5. Reset Player Stats
	-- We need to reset them to Level 1 / Biomass 0
	player:SetAttribute("Biomass", 0)
	player:SetAttribute("Level", 1)

	-- ProgressionManager listener will handle the physical resize on Level change

	return true
end

-- Handle kill event - increment session kills
local function onEliminated(_gameState, killerArg, _victimArg, _toolArg)
	-- Resolve killer
	local killer = nil
	if killerArg then
		if killerArg:IsA("Player") then
			killer = killerArg
		elseif killerArg:IsA("Model") then
			killer = Players:GetPlayerFromCharacter(killerArg)
		end
	end

	if killer and playerData[killer] then
		playerData[killer].SessionKills = (playerData[killer].SessionKills or 0) + 1
	end
end

-- Get stat multiplier for a player
function MetaProgressionManager.GetStatMultiplier(player: Player, statName: string): number
	if not playerData[player] then
		return 1
	end
	local level = playerData[player].Upgrades[statName] or 0
	return MetaConfig.GetMultiplier(statName, level)
end

-- Get flat stat value for a player
function MetaProgressionManager.GetStatValue(player: Player, statName: string): number
    if not playerData[player] then
        return 0
    end
    local level = playerData[player].Upgrades[statName] or 0
    return MetaConfig.GetValue(statName, level)
end

-- Handle purchase upgrade request
local function onPurchaseUpgrade(player: Player, statName: string): (boolean, string?)
	if not playerData[player] then
		return false, "Player data not loaded"
	end

	-- Get upgrade config
	local upgradeConfig = MetaConfig.GetUpgradeConfig(statName)
	if not upgradeConfig then
		return false, "Invalid stat name"
	end

	local currentLevel = playerData[player].Upgrades[statName] or 0

	-- Check MaxLevel
	if currentLevel >= upgradeConfig.MaxLevel then
		return false, "Max level reached"
	end

	-- Check tier unlock requirement
	local tierData = MetaConfig.Tiers[upgradeConfig.Tier]
	local lifetimeDNA = playerData[player].Biomass or 0
	if lifetimeDNA < tierData.UnlockAmount then
		return false, "Tier Locked"
	end

	local cost = MetaConfig.GetCost(statName, currentLevel)

	if playerData[player].GlobalXP < cost then
		return false, "Insufficient DNA"
	end

	-- Deduct cost and upgrade
	playerData[player].GlobalXP = playerData[player].GlobalXP - cost
	playerData[player].Upgrades[statName] = currentLevel + 1

	print(
		"🛒",
		player.Name,
		"purchased",
		statName,
		"upgrade (Level",
		currentLevel + 1,
		") for",
		cost,
		"DNA."
	)

	-- Save to DataStore
	savePlayerData(player)

	-- Notify client
	if updateMetaStatsRemote then
		updateMetaStatsRemote:FireClient(
			player,
			playerData[player].GlobalXP,
			playerData[player].Upgrades,
			playerData[player].Biomass
		)
	end

	return true, "Success"
end

-- Setup remotes
local function setupRemotes()
	local remotesFolder = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)

	if not remotesFolder then
		warn("MetaProgressionManager: Remotes folder not found")
		return
	end

	-- PurchaseUpgrade RemoteFunction
	purchaseUpgradeRemote = remotesFolder:FindFirstChild("PurchaseUpgrade")
	if not purchaseUpgradeRemote then
		purchaseUpgradeRemote = Instance.new("RemoteFunction")
		purchaseUpgradeRemote.Name = "PurchaseUpgrade"
		purchaseUpgradeRemote.Parent = remotesFolder
	end

	purchaseUpgradeRemote.OnServerInvoke = function(player: Player, statName: string)
		local success, message = onPurchaseUpgrade(player, statName)
		return success, message
	end

	-- UpdateMetaStats RemoteEvent
	updateMetaStatsRemote = remotesFolder:FindFirstChild("UpdateMetaStats")
	if not updateMetaStatsRemote then
		updateMetaStatsRemote = Instance.new("RemoteEvent")
		updateMetaStatsRemote.Name = "UpdateMetaStats"
		updateMetaStatsRemote.Parent = remotesFolder
	end

	-- RequestMetaData RemoteFunction
	requestMetaDataRemote = remotesFolder:FindFirstChild("RequestMetaData")
	if not requestMetaDataRemote then
		requestMetaDataRemote = Instance.new("RemoteFunction")
		requestMetaDataRemote.Name = "RequestMetaData"
		requestMetaDataRemote.Parent = remotesFolder
	end

	requestMetaDataRemote.OnServerInvoke = function(player: Player)
		if not playerData[player] then
			return 0, {}, 0
		end
		return playerData[player].GlobalXP, playerData[player].Upgrades, playerData[player].Biomass
	end

	-- ShowDeathSummary RemoteEvent
	showDeathSummaryRemote = remotesFolder:FindFirstChild("ShowDeathSummary")
	if not showDeathSummaryRemote then
		showDeathSummaryRemote = Instance.new("RemoteEvent")
		showDeathSummaryRemote.Name = "ShowDeathSummary"
		showDeathSummaryRemote.Parent = remotesFolder
	end

	-- Harvest RemoteFunction
	harvestRemote = remotesFolder:FindFirstChild("Harvest")
	if not harvestRemote then
		harvestRemote = Instance.new("RemoteFunction")
		harvestRemote.Name = "Harvest"
		harvestRemote.Parent = remotesFolder
	end

	harvestRemote.OnServerInvoke = function(player: Player)
		-- Check if safe
		local isSafe = player:GetAttribute("SafeZone") == true
		if not isSafe then
			return false, "Not in Safe Zone"
		end

		local success = MetaProgressionManager.Harvest(player)
		return success
	end

	-- RequestRespawn RemoteEvent
	requestRespawnRemote = remotesFolder:FindFirstChild("RequestRespawn")
	if not requestRespawnRemote then
		requestRespawnRemote = Instance.new("RemoteEvent")
		requestRespawnRemote.Name = "RequestRespawn"
		requestRespawnRemote.Parent = remotesFolder
		print("✅ Created RequestRespawn RemoteEvent")
	end
	
	requestRespawnRemote.OnServerEvent:Connect(function(player)
		print("🔄 Respawn requested for", player.Name)
		player:LoadCharacter()
	end)
end

function MetaProgressionManager.Start()
	print("--- Starting MetaProgressionManager (Refactored) ---")

	-- Setup remotes
	setupRemotes()

	-- Load data for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		loadPlayerData(player)
		if updateMetaStatsRemote and playerData[player] then
			updateMetaStatsRemote:FireClient(
				player,
				playerData[player].GlobalXP,
				playerData[player].Upgrades,
				playerData[player].Biomass
			)
		end
	end

	-- Handle new players
	Players.PlayerAdded:Connect(function(player)
		loadPlayerData(player)
		if updateMetaStatsRemote and playerData[player] then
			updateMetaStatsRemote:FireClient(
				player,
				playerData[player].GlobalXP,
				playerData[player].Upgrades,
				playerData[player].Biomass
			)
		end

		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.Died:Connect(function()
					onPlayerDeath(player)
				end)
			end
		end)
	end)

	-- Handle existing players' characters
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				humanoid.Died:Connect(function()
					onPlayerDeath(player)
				end)
			end
		end
		player.CharacterAdded:Connect(function(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if humanoid then
				humanoid.Died:Connect(function()
					onPlayerDeath(player)
				end)
			end
		end)
	end

	-- Listen to Eliminated event for kill tracking
	task.spawn(function()
		local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
		if not blasterFolder then return end

		local eliminatedEvent = blasterFolder:WaitForChild("Events"):WaitForChild("Eliminated", 10)
		if eliminatedEvent then
			eliminatedEvent.Event:Connect(onEliminated)
		end
	end)

	-- Save data on player removal
	Players.PlayerRemoving:Connect(function(player)
		if playerData[player] then
			savePlayerData(player)
			playerData[player] = nil
		end
	end)

	local function saveAllPlayerData()
		local promises = {}
		for player, data in pairs(playerData) do
			table.insert(promises, task.spawn(function()
				savePlayerData(player)
			end))
		end
		for _, promise in ipairs(promises) do
			task.wait()
		end
	end

	game:BindToClose(function()
		saveAllPlayerData()
		task.wait(3)
	end)
end

return MetaProgressionManager
