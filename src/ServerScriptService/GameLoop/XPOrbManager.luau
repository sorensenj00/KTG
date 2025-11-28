--[[
    Module: XPOrbManager
    Description: Manages spawning and lifecycle of Biomass orbs using object pooling.
    
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
local SPAWN_INTERVAL = 1
local ORB_LIFETIME = 30
local MAX_ORBS = 100
local POOL_SIZE = 50
local MAGNET_RADIUS = 50
local MIN_MAGNET_SPEED = 10
local MAX_MAGNET_SPEED = 80
local FLOAT_AMPLITUDE = 1.5 -- Max height deviation
local FLOAT_SPEED = 2 -- Speed of floating animation

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
    
    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {getOrbsFolder(), game:GetService("Players")}
    raycastParams.RespectCanCollide = true -- Ignore invisible/non-collidable triggers

	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	local yPos = 10 -- Default height
	if rayResult then
		yPos = rayResult.Position.Y -- Return exact ground height
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
		orb.Material = Enum.Material.Glass -- Changed to Glass for better visuals
		orb.Transparency = 0.4 -- Translucent
		orb.Reflectance = 0.3 -- Shiny
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
	local spawnPos = getRandomSpawnPosition()
	-- Adjust Y to sit perfectly on top of the ground
	orb.Position = Vector3.new(spawnPos.X, spawnPos.Y + (orb.Size.Y / 2), spawnPos.Z)
	orb.Parent = getOrbsFolder()

	-- Add PointLight for glow
	local light = Instance.new("PointLight")
	light.Color = selectedTier.Color
	light.Range = selectedTier.Size.Y * 1.5
	light.Brightness = 2
	light.Parent = orb

	-- Add Sparkle Particles
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Sparkles"
	particles.Texture = "rbxassetid://1266170131" -- Generic sparkle texture
	particles.Color = ColorSequence.new(selectedTier.Color)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0)
	})
	particles.Lifetime = NumberRange.new(0.5, 1)
	particles.Rate = 20
	particles.Speed = NumberRange.new(2, 5)
	particles.SpreadAngle = Vector2.new(360, 360)
	particles.Drag = 2
	particles.LightEmission = 1
	particles.Parent = orb

	-- Add to active list
	table.insert(activeOrbs, orb)

	-- Simplified animation
	-- Base Y is ground + half size + amplitude (so lowest point is touching ground)
	local groundY = spawnPos.Y
	local currentBaseY = groundY + (orb.Size.Y / 2) + FLOAT_AMPLITUDE
	
	task.spawn(function()
		local elapsed = 0
		local connection
		local upgradeCount = 0
		connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
			elapsed = elapsed + dt
			
			if not orb.Parent then
				connection:Disconnect()
				local index = table.find(activeOrbs, orb)
				if index then
					table.remove(activeOrbs, index)
				end
				returnOrb(orb)
				return
			end

			-- Check for upgrade
			if elapsed > ORB_LIFETIME * (upgradeCount + 1) then
				upgradeCount += 1
				
				-- Upgrade stats
				orb.Size = orb.Size * 1.5
				
				-- Recalculate base Y for new size
				currentBaseY = groundY + (orb.Size.Y / 2) + FLOAT_AMPLITUDE

				if hitbox then
					hitbox.Size = hitbox.Size * 1.5
				end
				
				-- Update light
				local light = orb:FindFirstChild("PointLight")
				if light then
					light.Range = orb.Size.Y * 1.5
				end
				
				local currentXP = orb:GetAttribute("XPValue") or 100
				orb:SetAttribute("XPValue", currentXP * 2)
			end

			-- Magnet Effect
			local closestPlayer = nil
			local closestDist = MAGNET_RADIUS
			
			for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
				if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
					local dist = (player.Character.HumanoidRootPart.Position - orb.Position).Magnitude
					if dist < closestDist then
						closestDist = dist
						closestPlayer = player
					end
				end
			end

			if closestPlayer and closestPlayer.Character then
				-- Move towards player
				local targetPos = closestPlayer.Character.HumanoidRootPart.Position
				local direction = (targetPos - orb.Position).Unit
				
				-- Variable speed based on distance (closer = faster)
				local speedAlpha = 1 - math.clamp(closestDist / MAGNET_RADIUS, 0, 1)
				local currentSpeed = MIN_MAGNET_SPEED + (MAX_MAGNET_SPEED - MIN_MAGNET_SPEED) * speedAlpha
				
				orb.Position = orb.Position + direction * currentSpeed * dt
				orb.Orientation = Vector3.new(0, elapsed * 360, 0) -- Spin faster when magnetized
				
				-- Update hitbox
				if hitbox and hitbox.Parent then
					hitbox.CFrame = orb.CFrame
				end
			else
				-- Floating animation
				local floatOffset = math.sin(elapsed * FLOAT_SPEED) * FLOAT_AMPLITUDE
				orb.Position = Vector3.new(orb.Position.X, currentBaseY + floatOffset, orb.Position.Z)
				orb.Orientation = Vector3.new(0, elapsed * 60, 0) -- Rotate
				-- Keep hitbox centered on orb
				if hitbox and hitbox.Parent then
					hitbox.CFrame = orb.CFrame
				end
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
				getProgressionManager().AddBiomass(player, xpValue)
			else
				-- Check for bot
				local CollectionService = game:GetService("CollectionService")
				if CollectionService:HasTag(character, "BotAI") then
					getProgressionManager().AddBiomass(character, xpValue)
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

-- PUBLIC API: Spawn specific number of orbs at a location (for death drops)
function XPOrbManager.SpawnDrop(position: Vector3, totalXP: number)
	if totalXP <= 0 then return end

	-- Determine orb count/size based on totalXP
	-- Instead of 1 giant orb, spawn a cluster of smaller ones for satisfaction
	local orbCount = math.clamp(math.ceil(totalXP / 100), 1, 10)
	local xpPerOrb = math.floor(totalXP / orbCount)

	for i = 1, orbCount do
		if countOrbs() >= MAX_ORBS then
			local oldest = table.remove(activeOrbs, 1)
			if oldest then returnOrb(oldest) end
		end

		local orb = getOrb()
		-- Determine visual tier based on value
		local tier = ORB_TIERS[1]
		if xpPerOrb >= 2000 then tier = ORB_TIERS[4]
		elseif xpPerOrb >= 500 then tier = ORB_TIERS[3]
		elseif xpPerOrb >= 250 then tier = ORB_TIERS[2]
		end

		orb.Size = tier.Size
		orb.Color = tier.Color
		orb:SetAttribute("XPValue", xpPerOrb)

		-- Explosion/Scatter effect
		local offset = Vector3.new(math.random(-10, 10), math.random(5, 15), math.random(-10, 10))
		orb.Position = position + Vector3.new(0, 5, 0) -- Start high
		orb.Parent = getOrbsFolder()

		-- Create hitbox
		local hitbox = Instance.new("Part")
		hitbox.Name = "Hitbox"
		hitbox.Size = tier.Size * 3
		hitbox.Transparency = 1
		hitbox.CanCollide = false
		hitbox.Anchored = true
		hitbox.CastShadow = false
		hitbox.Parent = orb

		table.insert(activeOrbs, orb)

		-- Physics-like scatter animation (manual tween/lerp since anchored)
		local targetPos = position + Vector3.new(math.random(-15, 15), 1, math.random(-15, 15))

		-- Simple parabola animation
		task.spawn(function()
			local t = 0
			local duration = 0.5
			local startPos = orb.Position

			while t < 1 and orb.Parent do
				t = t + 0.1
				local linear = startPos:Lerp(targetPos, t)
				local height = math.sin(t * math.pi) * 10 -- Arc
				orb.Position = linear + Vector3.new(0, height, 0)
				if hitbox.Parent then hitbox.CFrame = orb.CFrame end
				task.wait(0.03)
			end

			-- Start lifetime timer after landing
			task.delay(ORB_LIFETIME, function()
				if orb.Parent then
					local index = table.find(activeOrbs, orb)
					if index then table.remove(activeOrbs, index) end
					returnOrb(orb)
				end
			end)

			-- Start floating animation
			local floatY = orb.Position.Y
			local elapsed = 0
			local connection
			connection = game:GetService("RunService").Heartbeat:Connect(function(dt)
				elapsed = elapsed + dt
				if not orb.Parent then connection:Disconnect() return end
				orb.Position = Vector3.new(orb.Position.X, floatY + math.sin(elapsed*2), orb.Position.Z)
				orb.Orientation = Vector3.new(0, elapsed*60, 0)
				if hitbox.Parent then hitbox.CFrame = orb.CFrame end
			end)
		end)

		-- Touch Logic (Copied from spawnOrb to ensure consistency)
		local collected = false
		hitbox.Touched:Connect(function(hit)
			if collected or not orb.Parent then return end
			local character = hit.Parent
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				collected = true

				-- Award XP
				local player = game:GetService("Players"):GetPlayerFromCharacter(character)
				local xpValue = orb:GetAttribute("XPValue") or 100

				if player then
					getProgressionManager().AddBiomass(player, xpValue)
				else
					local CollectionService = game:GetService("CollectionService")
					if CollectionService:HasTag(character, "BotAI") then
						getProgressionManager().AddBiomass(character, xpValue)
					end
				end

				local index = table.find(activeOrbs, orb)
				if index then table.remove(activeOrbs, index) end
				returnOrb(orb)
			end
		end)
	end
end

function XPOrbManager.Start()
	print("--- Starting Optimized XPOrbManager ---")

	-- Pre-populate pool
	for _ = 1, POOL_SIZE do
		local orb = Instance.new("Part")
		orb.Name = "XPOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Glass
		orb.Transparency = 0.4
		orb.Reflectance = 0.3
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
