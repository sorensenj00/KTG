--[[
    Module: BotSpawner
    Description: Spawns bots, applies attributes, and handles respawning.
    Fixes: Unanchors ALL parts and improves raycast filtering.
    
    Dependencies:
    - ServerScriptService.GameLoop.ScalingEngine
    - ReplicatedStorage.GameLoop.GameConfig
    
    Author: System
    Last Updated: 2025-01-20
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local ScalingEngine = require(ServerScriptService.GameLoop.ScalingEngine)
local GameConfig = require(game:GetService("ReplicatedStorage").GameLoop.GameConfig)

local BotSpawner = {}

local SPAWN_COUNT = GameConfig.Performance.MaxBots
local RESPAWN_DELAY = 3

-- Helper to ensure Bots folder exists in Workspace
local function getBotsFolder()
	local folder = Workspace:FindFirstChild("Bots")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Bots"
		folder.Parent = Workspace
	end
	return folder
end

-- Helper to get random X/Z coordinates on Baseplate
local function getRandomSpawnXZ()
	-- Attempt to find the map/baseplate by common names
	local baseplate = Workspace:FindFirstChild("Baseplate")
		or Workspace:FindFirstChild("Map")
		or Workspace:FindFirstChild("Ground")

	local targetX, targetZ = 0, 0
	local size = Vector3.new(2048, 1, 2048) -- Default to standard map size (fixes "small square" issue)

	if baseplate then
		if baseplate:IsA("Model") then
			local cf, s = baseplate:GetBoundingBox()
			targetX, targetZ = cf.Position.X, cf.Position.Z
			size = s
		elseif baseplate:IsA("BasePart") then
			targetX, targetZ = baseplate.Position.X, baseplate.Position.Z
			size = baseplate.Size
		end
	else
		warn("BotSpawner: Baseplate/Map not found, using default 2048x2048 bounds")
	end

	local halfSizeX = size.X / 2
	local halfSizeZ = size.Z / 2

	-- Keep them slightly away from the absolute edge
	local x = math.random(-halfSizeX + 20, halfSizeX - 20)
	local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)

	return targetX + x, targetZ + z
end

local function spawnBot()
	local template = ServerStorage:FindFirstChild("TrainingBot")
	if not template then
		warn("No TrainingBot in ServerStorage")
		return
	end

	local bot = template:Clone()
	bot.Name = "Bot_" .. math.random(1000, 9999)

	local level = math.random(1, 5) -- Start at lower levels to prevent giant bots immediately
	bot:SetAttribute("Level", level)
	bot:SetAttribute("XP", 0)
	bot:SetAttribute("SpawnTime", Workspace:GetServerTimeNow())

	CollectionService:AddTag(bot, "BotAI")

	-- Give Weapon
	local weapon = ServerStorage:FindFirstChild("AutoBlaster")
	if weapon then
		local w = weapon:Clone()
		w.Parent = bot
	end

	local humanoid = bot:WaitForChild("Humanoid", 5)
	local rootPart = bot:WaitForChild("HumanoidRootPart", 5)

	if not humanoid or not rootPart then
		bot:Destroy()
		return
	end

	bot.PrimaryPart = rootPart

	-- === FIX 1: Unanchor EVERYTHING ===
	-- Just unanchoring rootPart isn't enough if the template has anchored Head/Limbs
	for _, desc in ipairs(bot:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = false
			desc.CanCollide = true
		end
	end

	bot.Parent = getBotsFolder()

	-- Apply Scaling
	ScalingEngine.ResizeCharacter(bot, level)
	task.wait() -- Allow scaling to apply

	-- Calculate Position
	local targetX, targetZ = getRandomSpawnXZ()

	-- === FIX 2: Improved Raycast Filtering ===
	-- Ignore Orbs, Visuals, and other Bots to prevent spawning on top of them
	local rayOrigin = Vector3.new(targetX, 500, targetZ) -- Lowered from 1000 to save perf
	local rayDirection = Vector3.new(0, -1000, 0)

	local ignoreList = { bot }
	if Workspace:FindFirstChild("Orbs") then
		table.insert(ignoreList, Workspace.Orbs)
	end
	if Workspace:FindFirstChild("MapVisuals") then
		table.insert(ignoreList, Workspace.MapVisuals)
	end
	if Workspace:FindFirstChild("MapInteractables") then
		table.insert(ignoreList, Workspace.MapInteractables)
	end
	if Workspace:FindFirstChild("Bots") then
		table.insert(ignoreList, Workspace.Bots)
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)

	if rayResult then
		local hipHeight = humanoid.HipHeight
		-- Spawn slightly above the hit position
		local spawnPos = rayResult.Position + Vector3.new(0, hipHeight + 2, 0)
		bot:SetPrimaryPartCFrame(CFrame.new(spawnPos))
	else
		-- Fallback: Reset to center if void
		local hipHeight = humanoid.HipHeight
		bot:SetPrimaryPartCFrame(CFrame.new(targetX, 50 + hipHeight, targetZ))
	end

	-- === FIX 3: Force Physics Wakeup ===
	-- Sometimes parts sleep in the air. This forces them to react to gravity.
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	task.delay(0.5, function()
		if rootPart and rootPart:IsA("BasePart") then
			rootPart:SetNetworkOwner(nil)
		end
		-- Reset to running so they can move
		humanoid:ChangeState(Enum.HumanoidStateType.Running)
	end)

	-- Respawn Logic
	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			if bot then
				bot:Destroy()
			end
			spawnBot()
		end)
	end)
end

function BotSpawner.Start()
	print("--- Starting BotSpawner ---")
	for _ = 1, SPAWN_COUNT do
		spawnBot()
		task.wait(0.1)
	end
end

return BotSpawner
