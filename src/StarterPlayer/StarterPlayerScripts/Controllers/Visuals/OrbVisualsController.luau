--[[
	Controller: OrbVisualsController
	Description: Client-side rendering of XP Orbs with pooling and smooth animations.
	
	Performance Features:
	- Part pooling (reuse instances)
	- Single RenderStepped loop for all orbs
	- Local visual-only rendering
	
	Author: System (Phase 3)
	Last Updated: 2025-11-29
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
-- local Debris = game:GetService("Debris")

local OrbVisualsController = {}

local player = Players.LocalPlayer

-- Configuration
local POOL_SIZE = 50
local FLOAT_AMPLITUDE =1.5
local FLOAT_SPEED = 2

local MAGNET_RADIUS = 50
local MIN_MAGNET_SPEED = 10
local MAX_MAGNET_SPEED = 80

-- Part Pool
local orbPool = {}
local activeOrbs = {} -- [orbId] = {part, hitbox, data, startTime}

-- OrbsFolder
local orbsFolder

-- Remotes
local orbEvents
local collectOrbRemote

-- Get orb folder
local function getOrbsFolder()
	if not orbsFolder then
		orbsFolder = Workspace:FindFirstChild("Orbs")
		if not orbsFolder then
			orbsFolder = Instance.new("Folder")
			orbsFolder.Name = "Orbs"
			orbsFolder.Parent = Workspace
		end
	end
	return orbsFolder
end

-- Get orb from pool or create new
local function getOrbPart()
	local orb = table.remove(orbPool)
	if not orb then
		orb = Instance.new("Part")
		orb.Name = "XPOrb"
		orb.Shape = Enum.PartType.Ball
		orb.Material = Enum.Material.Glass
		orb.Transparency = 0.4
		orb.Reflectance = 0.3
		orb.Anchored = true
		orb.CanCollide = false
		orb.CastShadow = false
	end
	return orb
end

-- Return orb to pool
local function returnOrbPart(orb)
	if orb and orb.Parent then
		orb.Parent = nil
		-- Clean up children
		for _, child in ipairs(orb:GetChildren()) do
			child:Destroy()
		end
		table.insert(orbPool, orb)
	end
end

-- Spawn orb visual
local function spawnOrbVisual(orbData)
	local orb = getOrbPart()
	
	-- Set properties
	orb.Size = orbData.Tier.Size
	orb.Color = orbData.Tier.Color
	orb.Position = orbData.Position
	
	-- Create hitbox (3x size for easier pickup)
	local hitbox = Instance.new("Part")
	hitbox.Name = "Hitbox"
	hitbox.Size = orbData.Tier.Size * 3
	hitbox.Transparency = 1
	hitbox.CanCollide = false -- Don't block movement
	hitbox.CanTouch = true -- But DO detect touches
	hitbox.Anchored = true
	hitbox.CastShadow = false
	hitbox.Parent = orb
	
	-- Add PointLight
	local light = Instance.new("PointLight")
	light.Color = orbData.Tier.Color
	light.Range = orbData.Tier.Size.Y * 1.5
	light.Brightness = 2
	light.Parent = orb
	
	-- Add Particles
	local particles = Instance.new("ParticleEmitter")
	particles.Name = "Sparkles"
	particles.Texture = "rbxassetid://1266170131"
	particles.Color = ColorSequence.new(orbData.Tier.Color)
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
	
	-- Parent to workspace
	orb.Parent = getOrbsFolder()
	
	-- Store active orb data
	activeOrbs[orbData.Id] = {
		part = orb,
		hitbox = hitbox,
		data = orbData,
		startTime = tick(),
		baseY = orbData.Position.Y,
		isDrop = orbData.IsDrop or false
	}
	
	-- Touch detection
	local collected = false
	hitbox.Touched:Connect(function(hit)
		if collected then return end
		
		local character = hit.Parent
		if character == player.Character then
			local humanoid = character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				collected = true
				-- Request collection from server
				collectOrbRemote:FireServer(orbData.Id)
			end
		end
	end)
	
	-- Drop animation (if death drop)
	if orbData.IsDrop then
		-- Target is the actual spawn position (on ground)
		local targetPos = orbData.Position
		
		task.spawn(function()
			local t = 0
			-- local duration = 0.5
			-- Start from above
			local startPos = orbData.Position + Vector3.new(0, 10, 0)
			orb.Position = startPos
			
			while t < 1 and orb.Parent and activeOrbs[orbData.Id] do
				t = t + 0.1
				local linear = startPos:Lerp(targetPos, t)
				local height = math.sin(t * math.pi) * 10
				orb.Position = linear + Vector3.new(0, height, 0)
				hitbox.CFrame = orb.CFrame
				task.wait(0.03)
			end
			
			if activeOrbs[orbData.Id] then
				activeOrbs[orbData.Id].baseY = orb.Position.Y
			end
		end)
	end
end

-- Despawn orb visual
local function despawnOrbVisual(orbId)
	local orbData = activeOrbs[orbId]
	if orbData then
		returnOrbPart(orbData.part)
		activeOrbs[orbId] = nil
	end
end

-- Animation loop (single RenderStepped for all orbs)
local function updateOrbVisuals(dt)
	local currentTime = tick()
	
	for orbId, orbData in pairs(activeOrbs) do
		local orb = orbData.part
		local hitbox = orbData.hitbox
		
		if not orb.Parent then
			-- Orb was destroyed externally
			activeOrbs[orbId] = nil
			continue
		end
		
		local elapsed = currentTime - orbData.startTime

		-- Magnetism (Client Prediction)
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local root = character.HumanoidRootPart
			local dist = (root.Position - orb.Position).Magnitude
			
			if dist < MAGNET_RADIUS then
				local direction = (root.Position - orb.Position).Unit
				local speedAlpha = 1 - math.clamp(dist / MAGNET_RADIUS, 0, 1)
				local currentSpeed = MIN_MAGNET_SPEED + (MAX_MAGNET_SPEED - MIN_MAGNET_SPEED) * speedAlpha
				
				local moveVec = direction * currentSpeed * dt
				
				-- Update base position (X/Z are in part, Y is in baseY)
				orb.Position = orb.Position + moveVec
				orbData.baseY = orbData.baseY + moveVec.Y
			end
		end
		
		-- Floating animation
		local floatOffset = math.sin(elapsed * FLOAT_SPEED) * FLOAT_AMPLITUDE
		orb.Position = Vector3.new(orb.Position.X, orbData.baseY + floatOffset, orb.Position.Z)
		
		-- Rotation
		orb.Orientation = Vector3.new(0, elapsed * 60, 0)
		
		-- Update hitbox (FIX: This was missing!)
		if hitbox and hitbox.Parent then
			hitbox.CFrame = orb.CFrame
		end
	end
end

-- Handle server events
local function onOrbEvent(eventData)
	if eventData.Action == "Spawn" then
		spawnOrbVisual(eventData)
	elseif eventData.Action == "Despawn" then
		despawnOrbVisual(eventData.Id)
	end
end

function OrbVisualsController.Start()
	print("🌟 OrbVisualsController: Starting client-side orb rendering...")
	
	-- Get remotes
	local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
	orbEvents = remotes:WaitForChild("OrbEvents", 30)
	collectOrbRemote = remotes:WaitForChild("CollectOrb", 30)
	
	if not orbEvents or not collectOrbRemote then
		warn("❌ OrbVisualsController: Failed to find orb remotes!")
		return
	end
	
	-- Pre-populate pool
	for i = 1, POOL_SIZE do
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
	
	-- Listen for orb events
	orbEvents.OnClientEvent:Connect(onOrbEvent)
	
	-- Start animation loop
	RunService.RenderStepped:Connect(updateOrbVisuals)
	
	print("✅ OrbVisualsController: Ready (Pool size:", POOL_SIZE, ")")
end

return OrbVisualsController
