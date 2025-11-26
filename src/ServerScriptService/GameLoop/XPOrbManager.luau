--[[
    Module: XPOrbManager
    Description: Manages spawning and lifecycle of XP orbs using object pooling.
    
    Dependencies:
    - Workspace
    - ServerScriptService.GameLoop.ProgressionManager
    
    Author: System
    Last Updated: 2025-01-20
]]

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")

-- Lazy load ProgressionManager
local ProgressionManager = nil
local function getProgressionManager()
	if not ProgressionManager then
		ProgressionManager = require(ServerScriptService.GameLoop.ProgressionManager)
	end
	return ProgressionManager
end

local XPOrbManager = {}

-- Configuration
local SPAWN_INTERVAL = 0.5
local ORB_LIFETIME = 45
local MAX_ORBS = 300
local POOL_SIZE = 50

-- Helper to ensure Orbs folder exists in Workspace
local function getOrbsFolder()
	local folder = Workspace:FindFirstChild("Orbs")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Orbs"
		folder.Parent = Workspace
	end
	return folder
end

-- Object Pool
local orbPool = {}
local activeOrbs = {}

-- Orb Tiers
local ORB_TIERS = {
	{ Name = "Common", XP = 100, Size = Vector3.new(2, 2, 2), Color = Color3.fromRGB(255, 215, 0), Chance = 70 },
	{ Name = "Uncommon", XP = 250, Size = Vector3.new(5, 5, 5), Color = Color3.fromRGB(0, 255, 255), Chance = 20 },
	{ Name = "Rare", XP = 500, Size = Vector3.new(12, 12, 12), Color = Color3.fromRGB(163, 35, 35), Chance = 8 },
	{ Name = "Legendary", XP = 2000, Size = Vector3.new(25, 25, 25), Color = Color3.fromRGB(197, 209, 28), Chance = 2 },
}

-- Helper to get random spawn position on Baseplate
local function getRandomSpawnPosition()
	-- Attempt to find the map/baseplate by common names
	local baseplate = Workspace:FindFirstChild("Baseplate")
		or Workspace:FindFirstChild("Map")
		or Workspace:FindFirstChild("Ground")

	local centerX, centerZ = 0, 0
	local sizeX, sizeZ = 2048, 2048 -- Default to large map size

	if baseplate then
		if baseplate:IsA("Model") then
			local cf, s = baseplate:GetBoundingBox()
			centerX, centerZ = cf.Position.X, cf.Position.Z
			sizeX, sizeZ = s.X, s.Z
		elseif baseplate:IsA("BasePart") then
			centerX, centerZ = baseplate.Position.X, baseplate.Position.Z
			sizeX, sizeZ = baseplate.Size.X, baseplate.Size.Z
		end
	end

	local halfSizeX = sizeX / 2
	local halfSizeZ = sizeZ / 2

	-- Random offset within baseplate (leaving a margin)
	local x = math.random(-halfSizeX + 20, halfSizeX - 20)
	local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)

	local targetX = centerX + x
	local targetZ = centerZ + z

	-- Raycast to find floor height
	local rayOrigin = Vector3.new(targetX, 500, targetZ)
	local rayDirection = Vector3.new(0, -1000, 0)
	local rayResult = Workspace:Raycast(rayOrigin, rayDirection)

	local yPos = 10 -- Default height
	if rayResult then
		yPos = rayResult.Position.Y + 1 -- 1 stud above ground (easier to collect)
	end

	return Vector3.new(targetX, yPos, targetZ)
end

-- Get orb from pool or create new
local function getOrb()
	local orb = table.remove(orbPool)
	if not orb then
		orb = Instance.new("Part")
		orb.Name = "XPOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Neon
		orb.Anchored = true
		orb.CanCollide = false
		orb.CastShadow = false
	end
	return orb
end

-- Return orb to pool
local function returnOrb(orb)
	if orb and orb.Parent then
		orb.Parent = nil
		-- Clean up any attachments/particles
		for _, child in ipairs(orb:GetChildren()) do
			child:Destroy()
		end
		table.insert(orbPool, orb)
	end
end

-- Count active orbs efficiently
local function countOrbs()
	return #activeOrbs
end

-- Spawn orb with pooling
local function spawnOrb()
	if countOrbs() >= MAX_ORBS then
		-- Remove oldest orb
		local oldest = table.remove(activeOrbs, 1)
		if oldest then
			returnOrb(oldest)
		end
	end

	-- Select tier
	local randomValue = math.random(1, 100)
	local accumulatedChance = 0
	local selectedTier = ORB_TIERS[1]

	for _, tier in ipairs(ORB_TIERS) do
		accumulatedChance = accumulatedChance + tier.Chance
		if randomValue <= accumulatedChance then
			selectedTier = tier
			break
		end
	end

	local orb = getOrb()
	orb.Size = selectedTier.Size
	orb.Color = selectedTier.Color
	orb:SetAttribute("XPValue", selectedTier.XP)

	-- Create invisible hitbox for easier pickup (3x the orb size)
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = selectedTier.Size * 3 -- 3x larger for forgiving pickup
	hitbox.Transparency = 1 -- Invisible
	hitbox.CanCollide = false
	hitbox.Anchored = true
	hitbox.CastShadow = false
	hitbox.Parent = orb

	-- Position using helper
	orb.Position = getRandomSpawnPosition()
	orb.Parent = getOrbsFolder()

	-- Add to active list
	table.insert(activeOrbs, orb)

	-- Simplified animation
	local startY = orb.Position.Y
	task.spawn(function()
		local elapsed = 0
		local connection
		connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed = elapsed + dt
			if elapsed > ORB_LIFETIME or not orb.Parent then
				connection:Disconnect()
				local index = table.find(activeOrbs, orb)
				if index then
					table.remove(activeOrbs, index)
				end
				returnOrb(orb)
				return
			end
			-- Simple float animation
			local floatOffset = math.sin(elapsed * 2) * 1
			orb.Position = Vector3.new(orb.Position.X, startY + floatOffset, orb.Position.Z)
			orb.Orientation = Vector3.new(0, elapsed * 60, 0) -- Rotate
			-- Keep hitbox centered on orb
			if hitbox and hitbox.Parent then
				hitbox.CFrame = orb.CFrame
			end
		end)
	end)

	-- Touch detection on the larger hitbox for easier pickup
	local collected = false
	hitbox.Touched:Connect(function(hit)
		if collected or not orb.Parent then
			return
		end
		local character = hit.Parent
		local humanoid = character:FindFirstChild("Humanoid")
		if humanoid and humanoid.Health > 0 then
			collected = true

			-- Award XP
			local player = game:GetService("Players"):GetPlayerFromCharacter(character)
			local xpValue = orb:GetAttribute("XPValue") or 100

			if player then
				getProgressionManager().AddXP(player, xpValue)
			else
				-- Check for bot
				local CollectionService = game:GetService("CollectionService")
				if CollectionService:HasTag(character, "BotAI") then
					getProgressionManager().AddXP(character, xpValue)
				end
			end

			local index = table.find(activeOrbs, orb)
			if index then
				table.remove(activeOrbs, index)
			end
			returnOrb(orb)
		end
	end)
end

function XPOrbManager.Start()
	print("--- Starting Optimized XPOrbManager ---")

	-- Pre-populate pool
	for _ = 1, POOL_SIZE do
		local orb = Instance.new("Part")
		orb.Name = "XPOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Neon
		orb.Anchored = true
		orb.CanCollide = false
		orb.CastShadow = false
		table.insert(orbPool, orb)
	end

	task.spawn(function()
		while true do
			spawnOrb()
			task.wait(SPAWN_INTERVAL)
		end
	end)
end

return XPOrbManager
