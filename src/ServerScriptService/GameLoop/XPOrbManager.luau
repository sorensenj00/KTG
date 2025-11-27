--[[
    Module: XPOrbManager
    Description: Manages spawning and lifecycle of XP orbs.
                 Refactored for "Explosion" loot drops and Client-Side Vacuum pickup.
    Description: Manages spawning and lifecycle of Biomass orbs using object pooling.
    
    Dependencies:
    - Workspace
    - ServerScriptService.GameLoop.ProgressionManager
    - ReplicatedStorage.GameLoop.Remotes
    
    Author: System
    Last Updated: 2025-01-28
]]

local Workspace = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")

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
local SPAWN_INTERVAL = 3 -- Slower natural spawn interval
local ORB_LIFETIME = 60
local MAX_ORBS_PER_DROP = 20 -- Max physical parts per kill
local MAX_TOTAL_ORBS = 400
local VACUUM_DISTANCE = 15 -- Max distance for server validation

-- Remotes
local remotesFolder = ReplicatedStorage:WaitForChild("GameLoop"):WaitForChild("Remotes")
local collectOrbRemote = remotesFolder:FindFirstChild("CollectOrb")
if not collectOrbRemote then
	collectOrbRemote = Instance.new("RemoteEvent")
	collectOrbRemote.Name = "CollectOrb"
	collectOrbRemote.Parent = remotesFolder
end

-- Collision Group
-- We want orbs to collide with Map but not Players (so players walk through them)
-- Assuming "Debris" or similar group exists, otherwise use CanCollide=false for now (handled via filtering)
-- Better: Set CollisionGroup if you have them. For now, we rely on CanCollide=true initially for physics,
-- then Client sets CanCollide=false when vacuuming.
-- ACTUALLY: If CanCollide=true, players will trip.
-- We will use PhysicsService if needed, but for now, small spherical parts are usually okay if we make them CanQuery=false CanTouch=false?
-- No, we need CanTouch=false (handled by client raycast/magnitude) and CanCollide=true (for ground)
-- but filter players.
-- Simplest approach: Use collision groups or just small size + non-collidable with players.
-- For this implementation, we will make them CanCollide=true so they roll, but use a CollisionGroup if possible.
-- If no groups defined, players might kick them. That's actually fun.

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

-- Orb Tiers (Descending XP order for greedy algorithm)
local ORB_TIERS = {
	{ Name = "Legendary", XP = 2000, Size = Vector3.new(2.5, 2.5, 2.5), Color = Color3.fromRGB(197, 209, 28) },
	{ Name = "Rare", XP = 500, Size = Vector3.new(1.8, 1.8, 1.8), Color = Color3.fromRGB(163, 35, 35) },
	{ Name = "Uncommon", XP = 250, Size = Vector3.new(1.4, 1.4, 1.4), Color = Color3.fromRGB(0, 255, 255) },
	{ Name = "Common", XP = 100, Size = Vector3.new(1.0, 1.0, 1.0), Color = Color3.fromRGB(255, 215, 0) },
}

-- Tracking
local activeOrbs = {} -- { [part] = xpValue }

-- Helper: Create a physical orb
local function createOrb(tier, position)
	local orb = Instance.new("Part")
	orb.Name = "XPOrb"
	orb.Shape = Enum.PartType.Ball
	orb.Material = Enum.Material.Neon
	orb.Size = tier.Size
	orb.Color = tier.Color
	orb.Position = position
	orb.Anchored = false
	orb.CanCollide = true
	orb.CastShadow = false

	-- Physical properties for nice rolling/bouncing
	orb.CustomPhysicalProperties = PhysicalProperties.new(
		0.7, -- Density
		0.3, -- Friction (slippery)
		0.5, -- Elasticity (bouncy)
		1,   -- FrictionWeight
		1    -- ElasticityWeight
	)

	-- Add Tag for Client Finder
	CollectionService:AddTag(orb, "XPOrb")

	-- Register
	orb.Parent = getOrbsFolder()
	activeOrbs[orb] = tier.XP

	-- Cleanup
	task.delay(ORB_LIFETIME, function()
		if orb.Parent then
			activeOrbs[orb] = nil
			orb:Destroy()
		end
	end)

	return orb
end

-- Public: Drop Loot (Explosion)
function XPOrbManager.DropLoot(position: Vector3, totalXP: number)
	if totalXP <= 0 then return end

	local drops = {}
	local remainingXP = totalXP
	local count = 0

	-- Greedy algorithm to determine orb counts
	for _, tier in ipairs(ORB_TIERS) do
		if remainingXP >= tier.XP and count < MAX_ORBS_PER_DROP then
			local num = math.floor(remainingXP / tier.XP)
			-- Cap number of this tier to prevent flooding if huge XP
			local limit = math.ceil((MAX_ORBS_PER_DROP - count) / 2)
			-- If we are at the last tier (Common), take all we can
			if tier.Name == "Common" then limit = MAX_ORBS_PER_DROP - count end

			local take = math.clamp(num, 0, limit)

			for i = 1, take do
				table.insert(drops, tier)
			end

			remainingXP = remainingXP - (take * tier.XP)
			count = count + take
		end
	end

	-- Distribute drops with physics
	for _, tier in ipairs(drops) do
		local orb = createOrb(tier, position + Vector3.new(0, 2, 0))

		-- Random Explosion Velocity
		local angle = math.random() * 2 * math.pi
		local speed = math.random(15, 40) -- Explosion force
		local upForce = math.random(20, 50)

		local velocity = Vector3.new(math.cos(angle) * speed, upForce, math.sin(angle) * speed)
		orb.AssemblyLinearVelocity = velocity
	end

	-- Clean up overflow if needed
	local allOrbs = getOrbsFolder():GetChildren()
	if #allOrbs > MAX_TOTAL_ORBS then
		-- Remove oldest 10%
		for i = 1, math.floor(MAX_TOTAL_ORBS * 0.1) do
			if allOrbs[i] then
				activeOrbs[allOrbs[i]] = nil
				allOrbs[i]:Destroy()
			end
		end
	end
end

-- Public: Natural Spawns (Reduced rate)
local function spawnNaturalOrb()
	-- Simple logic to spawn random orbs around the map
	-- Similar to original but less frequent

	-- Get random tier (weighted)
	local r = math.random(100)
	local tier = ORB_TIERS[4] -- Common
	if r > 95 then tier = ORB_TIERS[1] -- Legendary
	elseif r > 85 then tier = ORB_TIERS[2] -- Rare
	elseif r > 60 then tier = ORB_TIERS[3] -- Uncommon
	end

	-- Random Position (Simplified map bounds)
	local x = math.random(-800, 800)
	local z = math.random(-800, 800)
	local rayOrigin = Vector3.new(x, 500, z)
	local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -1000, 0))

	if rayResult then
		createOrb(tier, rayResult.Position + Vector3.new(0, 5, 0))
	end
end

-- Secure Collection Handler
local function onCollectOrb(player, orb)
	if not orb or not orb.Parent then return end

	local xpValue = activeOrbs[orb]
	if not xpValue then return end -- Invalid orb

	-- Distance Check (Server Authority)
	if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		local dist = (player.Character.HumanoidRootPart.Position - orb.Position).Magnitude
		if dist > VACUUM_DISTANCE + 10 then -- Tolerance for latency
			-- warn(player.Name .. " tried to collect orb from too far: " .. dist)
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

		-- Award XP
		getProgressionManager().AddXP(player, xpValue)

		-- Cleanup
		activeOrbs[orb] = nil
		orb:Destroy()
	end
end

function XPOrbManager.Start()
	print("--- Starting Refactored XPOrbManager (Physics Loot) ---")

	-- Clean old orbs
	local folder = getOrbsFolder()
	folder:ClearAllChildren()

	-- Connect Remote
	collectOrbRemote.OnServerEvent:Connect(onCollectOrb)

	-- Start Natural Spawner
	task.spawn(function()
		while true do
			task.wait(SPAWN_INTERVAL)
			if #getOrbsFolder():GetChildren() < MAX_TOTAL_ORBS then
				spawnNaturalOrb()
			end
		end
	end)
end

return XPOrbManager
