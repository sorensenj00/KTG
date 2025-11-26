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
local playerData = {} -- { [player] = { GlobalXP = 0, Biomass = 0, Upgrades = {...}, SessionKills = 0, SessionXP = 0 } }

-- Remotes
local purchaseUpgradeRemote
local updateMetaStatsRemote
local requestMetaDataRemote
local showDeathSummaryRemote
local requestRespawnRemote

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
		GlobalXP = 0,
		Biomass = 0,
		Upgrades = defaultUpgrades,
		SessionXP = 0,
	}
end

-- Load player data from DataStore
local function loadPlayerData(player: Player)
	-- Skip DataStore in Studio mode
	if IS_STUDIO then
		playerData[player] = getDefaultData()
		playerData[player].SessionKills = 0
		playerData[player].SessionXP = 0
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
				print("🔄 Migrating data for", player.Name, "- setting Biomass to", biomass)
			end

			-- Load all upgrade stats (handle old saves that might not have new stats)
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
				SessionXP = 0,
			}
			print(
				"✅ Loaded meta-progression data for",
				player.Name,
				"- GXP:",
				playerData[player].GlobalXP,
				"Biomass:",
				playerData[player].Biomass
			)
		else
			-- Invalid data, use defaults
			playerData[player] = getDefaultData()
			playerData[player].SessionKills = 0
			playerData[player].SessionXP = 0
			print("⚠️ Invalid data structure for", player.Name, "- using defaults")
		end
	else
		-- No data or error, use defaults
		playerData[player] = getDefaultData()
		playerData[player].SessionKills = 0
		playerData[player].SessionXP = 0
		if not success then
			warn("❌ Failed to load data for", player.Name, ":", data)
		else
			print("📝 New player", player.Name, "- initialized default meta-progression data")
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

-- Handle player death - award GXP and save
local function onPlayerDeath(player: Player)
	if not playerData[player] then
		return
	end

	local sessionKills = playerData[player].SessionKills or 0
	local sessionXP = playerData[player].SessionXP or 0

	-- Calculate GXP from kills (Kill Bonus)
	local gxpFromKills = sessionKills * MetaConfig.GXP_PER_KILL

	-- Note: Session XP is now converted to GXP in real-time via AddBiomassFromXP,
	-- so we don't convert it again here to avoid double-dipping.
	local gxpFromXP = 0 

	-- Total GXP earned (Just the kill bonus now)
	local totalGXPEarned = gxpFromKills
	
	-- We still want to show the Session XP on the death screen for info
	-- But the "Earned" amount will be just the kill bonus.

	if totalGXPEarned > 0 then
		playerData[player].GlobalXP = playerData[player].GlobalXP + totalGXPEarned
		playerData[player].Biomass = (playerData[player].Biomass or 0) + totalGXPEarned
		print(
			"💰",
			player.Name,
			"earned",
			totalGXPEarned,
			"GXP Bonus (",
			gxpFromKills,
			"from kills). Total GXP:",
			playerData[player].GlobalXP,
			"Biomass:",
			playerData[player].Biomass
		)

		-- Save to DataStore
		savePlayerData(player)

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
		showDeathSummaryRemote:FireClient(player, sessionKills, sessionXP, totalGXPEarned)
	end

	-- Reset session data
	playerData[player].SessionKills = 0
	playerData[player].SessionXP = 0
end

-- Public API: Add Session XP
function MetaProgressionManager.AddSessionXP(player: Player, amount: number)
	if not playerData[player] then
		return
	end
	playerData[player].SessionXP = (playerData[player].SessionXP or 0) + amount
end

-- Public API: Add Biomass from XP (Real-time)
function MetaProgressionManager.AddBiomassFromXP(player: Player, xpAmount: number)
	if not playerData[player] then
		return
	end
	
	local gxpAmount = math.floor(xpAmount * MetaConfig.SESSION_XP_TO_GXP_RATIO)
	if gxpAmount > 0 then
		playerData[player].GlobalXP = (playerData[player].GlobalXP or 0) + gxpAmount
		playerData[player].Biomass = (playerData[player].Biomass or 0) + gxpAmount
		
		-- Notify client immediately
		if updateMetaStatsRemote then
			updateMetaStatsRemote:FireClient(
				player,
				playerData[player].GlobalXP,
				playerData[player].Upgrades,
				playerData[player].Biomass
			)
		end
	end
end

-- Public API: Add GlobalXP (and Biomass)
function MetaProgressionManager.AddGlobalXP(player: Player, amount: number)
	if not playerData[player] then
		return
	end
	
	amount = math.floor(amount)
	playerData[player].GlobalXP = (playerData[player].GlobalXP or 0) + amount
	playerData[player].Biomass = (playerData[player].Biomass or 0) + amount
	
	-- Save to DataStore
	savePlayerData(player)
	
	-- Notify client with updated stats
	if updateMetaStatsRemote then
		updateMetaStatsRemote:FireClient(
			player,
			playerData[player].GlobalXP,
			playerData[player].Upgrades,
			playerData[player].Biomass
		)
	end
	
	print("💰 Admin added", amount, "GlobalXP to", player.Name, "- Total GXP:", playerData[player].GlobalXP, "Biomass:", playerData[player].Biomass)
end

-- Handle kill event - increment session kills
local function onEliminated(_gameState, killerArg, _victimArg, _toolArg)
	-- Resolve killer (similar to ProgressionManager pattern)
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
		print("📊", killer.Name, "session kills:", playerData[killer].SessionKills)
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

-- Get the unlock tier for a player based on their Biomass
function MetaProgressionManager.GetUnlockTier(player: Player): number
	if not playerData[player] then
		return 1
	end

	local biomass = playerData[player].Biomass or 0

	-- Check tiers in reverse order (highest to lowest)
	for tierNumber = 4, 1, -1 do
		local tierData = MetaConfig.Tiers[tierNumber]
		if tierData and biomass >= tierData.UnlockBiomass then
			return tierNumber
		end
	end

	return 1
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
	local playerBiomass = playerData[player].Biomass or 0
	if playerBiomass < tierData.UnlockBiomass then
		return false, "Tier Locked"
	end

	local cost = MetaConfig.GetCost(statName, currentLevel)

	if playerData[player].GlobalXP < cost then
		return false, "Insufficient Global XP"
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
		"GXP. Remaining:",
		playerData[player].GlobalXP
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
		print("✅ Created PurchaseUpgrade RemoteFunction")
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
		print("✅ Created UpdateMetaStats RemoteEvent")
	end

	-- RequestMetaData RemoteFunction (for immediate data fetch on client start)
	requestMetaDataRemote = remotesFolder:FindFirstChild("RequestMetaData")
	if not requestMetaDataRemote then
		requestMetaDataRemote = Instance.new("RemoteFunction")
		requestMetaDataRemote.Name = "RequestMetaData"
		requestMetaDataRemote.Parent = remotesFolder
		print("✅ Created RequestMetaData RemoteFunction")
	end

	requestMetaDataRemote.OnServerInvoke = function(player: Player)
		if not playerData[player] then
			-- Data not loaded yet, return defaults
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
		print("✅ Created ShowDeathSummary RemoteEvent")
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
	print("--- Starting MetaProgressionManager ---")

	-- Setup remotes
	setupRemotes()

	-- Load data for existing players
	for _, player in ipairs(Players:GetPlayers()) do
		loadPlayerData(player)
		-- Send initial data to client
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
		-- Send initial data to client
		if updateMetaStatsRemote and playerData[player] then
			updateMetaStatsRemote:FireClient(
				player,
				playerData[player].GlobalXP,
				playerData[player].Upgrades,
				playerData[player].Biomass
			)
		end

		-- Setup death tracking
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
		if not blasterFolder then
			warn("MetaProgressionManager: Blaster folder not found")
			return
		end

		local eliminatedEvent = blasterFolder:WaitForChild("Events"):WaitForChild("Eliminated", 10)

		if eliminatedEvent then
			print("✅ MetaProgressionManager: Hooked into Blaster System!")
			eliminatedEvent.Event:Connect(onEliminated)
		else
			warn("⚠️ MetaProgressionManager: EliminatedEvent not found")
		end
	end)

	-- Save data on player removal
	Players.PlayerRemoving:Connect(function(player)
		if playerData[player] then
			savePlayerData(player)
			playerData[player] = nil
		end
	end)

	-- ✅ IMPROVED: Use BindToClose for guaranteed save
	local function saveAllPlayerData()
		local promises = {}
		for player, data in pairs(playerData) do
			table.insert(promises, task.spawn(function()
				savePlayerData(player)
			end))
		end
		-- Wait for all saves
		for _, promise in ipairs(promises) do
			task.wait()
		end
	end

	game:BindToClose(function()
		saveAllPlayerData()
		task.wait(3) -- Give time for saves
	end)
end

return MetaProgressionManager

