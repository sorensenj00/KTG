local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local GameLoop = ServerScriptService.GameLoop
local ProgressionManager = require(GameLoop.ProgressionManager)
local ScalingEngine = require(GameLoop.ScalingEngine)
local MetaProgressionManager = require(GameLoop.MetaProgressionManager)

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
local addXPEvent = createEvent("AddXP")
local addGlobalXPEvent = createEvent("AddGlobalXP")
local toggleGodModeEvent = createEvent("ToggleGodMode")
local toggleInfiniteAmmoEvent = createEvent("ToggleInfiniteAmmo")

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

-- Add XP
addXPEvent.OnServerEvent:Connect(function(player, amount)
	if typeof(amount) ~= "number" then return end
	print("👮 Admin:", player.Name, "added", amount, "XP")
	ProgressionManager.AddXP(player, amount)
end)

-- Add GlobalXP (and Biomass)
addGlobalXPEvent.OnServerEvent:Connect(function(player, amount)
	if typeof(amount) ~= "number" then return end
	print("👮 Admin:", player.Name, "added", amount, "GlobalXP")
	MetaProgressionManager.AddGlobalXP(player, amount)
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

