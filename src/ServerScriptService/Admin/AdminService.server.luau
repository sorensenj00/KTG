local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local Services = ServerScriptService.Services
local ProgressionManager = require(Services.Progression.ProgressionService)
local ScalingEngine = require(Services.World.ScalingEngineService)
local MetaProgressionManager = require(Services.Progression.MetaProgressionService)

-- 1. Setup Remotes
local adminRemotes = ReplicatedStorage:FindFirstChild("AdminRemotes") or Instance.new("Folder")
adminRemotes.Name = "AdminRemotes"
adminRemotes.Parent = ReplicatedStorage

local function createEvent(name)
	local event = adminRemotes:FindFirstChild(name) or Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = adminRemotes
	return event
end

local setLevelEvent = createEvent("SetLevel")
local setBotLevelEvent = createEvent("SetBotLevel")
local addXPEvent = createEvent("AddXP")
local addGlobalXPEvent = createEvent("AddGlobalXP")
local toggleGodModeEvent = createEvent("ToggleGodMode")
local toggleInfiniteAmmoEvent = createEvent("ToggleInfiniteAmmo")
local setSpeedEvent = createEvent("SetSpeed")
local addMutationEvent = createEvent("AddMutation")
local removeMutationEvent = createEvent("RemoveMutation")
local resetMutationsEvent = createEvent("ResetMutations")

print("👮 AdminService: Started")

-- 2. Handlers

-- Set Level
setLevelEvent.OnServerEvent:Connect(function(player, targetLevel)
	if typeof(targetLevel) ~= "number" then return end
	targetLevel = math.clamp(math.floor(targetLevel), 1, 999)

	print("👮 Admin:", player.Name, "set level to", targetLevel)
	
	player:SetAttribute("Level", targetLevel)
	player:SetAttribute("XP", 0) -- Reset XP on manual level set
	
	if player.Character then
		ScalingEngine.ResizeCharacter(player.Character, targetLevel)
	end
end)

-- Set Bot Level
setBotLevelEvent.OnServerEvent:Connect(function(player, targetBot, targetLevel)
	if typeof(targetLevel) ~= "number" then return end
	if not targetBot or not targetBot:IsA("Model") then
		warn("❌ Invalid bot")
		return
	end
	
	targetLevel = math.clamp(math.floor(targetLevel), 1, 999)
	
	print("👮 Admin:", player.Name, "set bot", targetBot.Name, "to level", targetLevel)
	
	targetBot:SetAttribute("Level", targetLevel)
	targetBot:SetAttribute("XP", 0)
	
	ScalingEngine.ResizeCharacter(targetBot, targetLevel)
end)

-- Add XP
addXPEvent.OnServerEvent:Connect(function(player, amount)
	if typeof(amount) ~= "number" then return end
	print("👮 Admin:", player.Name, "added", amount, "XP")
	ProgressionManager.AddBiomass(player, amount)
end)

-- Add GlobalXP (and Biomass)
addGlobalXPEvent.OnServerEvent:Connect(function(player, amount)
	if typeof(amount) ~= "number" then return end
	print("👮 Admin:", player.Name, "added", amount, "GlobalXP")
	MetaProgressionManager.AddDNA(player, amount)
end)

-- God Mode
toggleGodModeEvent.OnServerEvent:Connect(function(player, state)
	print("👮 Admin:", player.Name, "toggled God Mode:", state)
	player:SetAttribute("GodMode", state)
	
	if player.Character then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			if state then
				humanoid.MaxHealth = 1000000
				humanoid.Health = 1000000
			else
				-- Reset to normal based on level
				local level = player:GetAttribute("Level") or 1
				ScalingEngine.ResizeCharacter(player.Character, level) -- This resets health
			end
		end
	end
end)

-- Infinite Ammo
toggleInfiniteAmmoEvent.OnServerEvent:Connect(function(player, state)
	print("👮 Admin:", player.Name, "toggled Infinite Ammo:", state)
	player:SetAttribute("InfiniteAmmo", state)
	-- Tool logic is handled in Blaster scripts by checking this attribute
end)

-- Set Speed
setSpeedEvent.OnServerEvent:Connect(function(player, speed)
	if typeof(speed) ~= "number" then return end
	speed = math.clamp(speed, 0, 500) -- Allow up to 500 for testing
	
	print("👮 Admin:", player.Name, "set speed to", speed)
	
	if player.Character then
		local humanoid = player.Character:FindFirstChild("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = speed
		end
	end
end)

-- Add Mutation
addMutationEvent.OnServerEvent:Connect(function(player, mutationName)
	if typeof(mutationName) ~= "string" then return end
	
	print("👮 Admin:", player.Name, "adding mutation:", mutationName)
	
	-- Get current mutations
	local mutationsData = player:GetAttribute("Mutations") or "{}"
	local mutations = {}
	
	-- Parse JSON (simple approach - in production use HttpService:JSONDecode)
	local success, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(mutationsData)
	end)
	
	if success then
		mutations = decoded
	else
		mutations = {}
	end
	
	-- Add or increment mutation level
	if mutations[mutationName] then
		mutations[mutationName] = mutations[mutationName] + 1
	else
		mutations[mutationName] = 1
	end
	
	-- Encode and save
	local encoded = game:GetService("HttpService"):JSONEncode(mutations)
	player:SetAttribute("Mutations", encoded)
	
	-- Fire update event
	local updateEvent = ReplicatedStorage:FindFirstChild("UpdateMetaEvent")
	if updateEvent then
		updateEvent:FireClient(player)
	end
end)

-- Remove Mutation
removeMutationEvent.OnServerEvent:Connect(function(player, mutationName)
	if typeof(mutationName) ~= "string" then return end
	
	print("👮 Admin:", player.Name, "removing mutation:", mutationName)
	
	-- Get current mutations
	local mutationsData = player:GetAttribute("Mutations") or "{}"
	local mutations = {}
	
	-- Parse JSON
	local success, decoded = pcall(function()
		return game:GetService("HttpService"):JSONDecode(mutationsData)
	end)
	
	if success then
		mutations = decoded
	else
		mutations = {}
	end
	
	-- Remove or decrement mutation level
	if mutations[mutationName] then
		if mutations[mutationName] > 1 then
			mutations[mutationName] = mutations[mutationName] - 1
		else
			mutations[mutationName] = nil
		end
	end
	
	-- Encode and save
	local encoded = game:GetService("HttpService"):JSONEncode(mutations)
	player:SetAttribute("Mutations", encoded)
	
	-- Fire update event
	local updateEvent = ReplicatedStorage:FindFirstChild("UpdateMetaEvent")
	if updateEvent then
		updateEvent:FireClient(player)
	end
end)

-- Reset Mutations
resetMutationsEvent.OnServerEvent:Connect(function(player)
	print("👮 Admin:", player.Name, "reset all mutations")
	MetaProgressionManager.ResetUpgrades(player)
end)

-- God Mode Protection (Heal if damaged while active)
local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end
	
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	
	humanoid.HealthChanged:Connect(function(health)
		if player:GetAttribute("GodMode") then
			if health < humanoid.MaxHealth then
				humanoid.Health = humanoid.MaxHealth
			end
		end
	end)
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end)

-- Handle existing players
for _, player in ipairs(Players:GetPlayers()) do
	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

