--[[
	Controller: OrbVisualsController
	Description: Client-side rendering of XP Orbs using strict types and config.
	
	Refactor Goals:
	- Use `XPOrbConfig` for constants.
	- Decouple from legacy 'Blaster' remotes.
	- Maintain efficient pooling.
	
	Author: System (Refactored)
	Last Updated: 2025-01-20
]]

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local XPOrbConfig = require(ReplicatedStorage.GameLoop.XPOrbConfig)

-- Types
type OrbData = XPOrbConfig.OrbData
type OrbVisual = {
    part: Part,
    hitbox: Part,
    data: XPOrbConfig.OrbEvent, -- Using Event data which is partial OrbData
    startTime: number,
    baseY: number,
    isDrop: boolean
}

local OrbVisualsController = {}

local player = Players.LocalPlayer

-- Part Pool
local orbPool: {Part} = {}
local activeOrbs: { [number]: OrbVisual } = {}

-- OrbsFolder
local orbsFolder

-- Remotes
local orbEvents: RemoteEvent
local collectOrbRemote: RemoteEvent

--[[
    -------------------------------------------------------------------------
    POOLING
    -------------------------------------------------------------------------
]]

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

local function createOrbTemplate(): Part
    local orb = Instance.new("Part")
    orb.Name = "XPOrb"
    orb.Shape = Enum.PartType.Ball
    orb.Material = Enum.Material.Glass
    orb.Transparency = 0.4
    orb.Reflectance = 0.3
    orb.Anchored = true
    orb.CanCollide = false
    orb.CastShadow = false
    return orb
end

local function getOrbPart(): Part
	local orb = table.remove(orbPool)
	if not orb then
		orb = createOrbTemplate()
	end
	return orb
end

local function returnOrbPart(orb: Part)
	if orb and orb.Parent then
		orb.Parent = nil
		-- Clean up children
		for _, child in ipairs(orb:GetChildren()) do
			child:Destroy()
		end
		table.insert(orbPool, orb)
	end
end

--[[
    -------------------------------------------------------------------------
    RENDERING
    -------------------------------------------------------------------------
]]

local function spawnOrbVisual(orbData: XPOrbConfig.OrbEvent)
    if not orbData.Position or not orbData.Tier then return end

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
	hitbox.CanCollide = false
	hitbox.CanTouch = true
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
	
	orb.Parent = getOrbsFolder()
	
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
				collectOrbRemote:FireServer(orbData.Id)
			end
		end
	end)
	
	-- Drop animation
	if orbData.IsDrop then
		local targetPos = orbData.Position
		
		task.spawn(function()
			local t = 0
			local startPos = orbData.Position + Vector3.new(0, 10, 0)
			orb.Position = startPos
			
			while t < 1 and orb.Parent and activeOrbs[orbData.Id] do
				t += 0.1
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

local function despawnOrbVisual(orbId: number)
	local orbData = activeOrbs[orbId]
	if orbData then
		returnOrbPart(orbData.part)
		activeOrbs[orbId] = nil
	end
end

local function growOrbVisual(orbId: number, newSize: Vector3?)
	local orbData = activeOrbs[orbId]
	if orbData and newSize then
		local orb = orbData.part
		local hitbox = orbData.hitbox
		
		-- Tween size
		local info = TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out)
		
		TweenService:Create(orb, info, {Size = newSize}):Play()
		if hitbox then
			TweenService:Create(hitbox, info, {Size = newSize * 3}):Play()
		end
		
		-- Update light range
		local light = orb:FindFirstChildOfClass("PointLight")
		if light then
			light.Range = newSize.Y * 1.5
		end
	end
end

--[[
    -------------------------------------------------------------------------
    LOOP
    -------------------------------------------------------------------------
]]

local function updateOrbVisuals(dt: number)
	local currentTime = tick()
	
	for orbId, orbData in pairs(activeOrbs) do
		local orb = orbData.part
		local hitbox = orbData.hitbox
		
		if not orb.Parent then
			activeOrbs[orbId] = nil
			continue
		end
		
		local elapsed = currentTime - orbData.startTime

		-- Magnetism (Client Prediction)
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local root = character.HumanoidRootPart :: BasePart
			local dist = (root.Position - orb.Position).Magnitude
			
			if dist < XPOrbConfig.MAGNET_RADIUS then
				local direction = (root.Position - orb.Position).Unit
				local speedAlpha = 1 - math.clamp(dist / XPOrbConfig.MAGNET_RADIUS, 0, 1)
				local currentSpeed = XPOrbConfig.MIN_MAGNET_SPEED + (XPOrbConfig.MAX_MAGNET_SPEED - XPOrbConfig.MIN_MAGNET_SPEED) * speedAlpha
				
				local moveVec = direction * currentSpeed * dt
				
				orb.Position += moveVec
				orbData.baseY += moveVec.Y
			end
		end
		
		-- Floating
		local floatOffset = math.sin(elapsed * XPOrbConfig.FLOAT_SPEED) * XPOrbConfig.FLOAT_AMPLITUDE
		orb.Position = Vector3.new(orb.Position.X, orbData.baseY + floatOffset + XPOrbConfig.FLOAT_AMPLITUDE, orb.Position.Z)
		
		-- Rotation
		orb.Orientation = Vector3.new(0, elapsed * 60, 0)
		
		if hitbox and hitbox.Parent then
			hitbox.CFrame = orb.CFrame
		end
	end
end

local function onOrbEvent(eventData: XPOrbConfig.OrbEvent)
	if eventData.Action == "Spawn" then
		spawnOrbVisual(eventData)
	elseif eventData.Action == "Despawn" then
		despawnOrbVisual(eventData.Id)
	elseif eventData.Action == "Grow" then
		growOrbVisual(eventData.Id, eventData.NewSize)
	end
end

--[[
    -------------------------------------------------------------------------
    INIT
    -------------------------------------------------------------------------
]]

function OrbVisualsController.Start()
	print("🌟 OrbVisualsController: Starting client-side orb rendering...")
	
	-- Remote Discovery - Match XPOrbService which uses Blaster.Remotes
	local blaster = ReplicatedStorage:WaitForChild("Blaster", 10)
	if not blaster then 
		warn("❌ OrbVisualsController: Missing ReplicatedStorage.Blaster") 
		return 
	end
	
	local remotes = blaster:WaitForChild("Remotes", 10)
	if not remotes then 
		warn("❌ OrbVisualsController: Missing Blaster.Remotes") 
		return 
	end

	orbEvents = remotes:WaitForChild("OrbEvents", 10) :: RemoteEvent
	collectOrbRemote = remotes:WaitForChild("CollectOrb", 10) :: RemoteEvent
	
	if not orbEvents or not collectOrbRemote then
		warn("❌ OrbVisualsController: Failed to find orb remotes in Blaster.Remotes!")
		return
	end
	
	-- Pre-populate pool
	for i = 1, XPOrbConfig.POOL_SIZE do
		table.insert(orbPool, createOrbTemplate())
	end
	
	-- Listeners
	orbEvents.OnClientEvent:Connect(onOrbEvent)
	RunService.RenderStepped:Connect(updateOrbVisuals)
	
	print("✅ OrbVisualsController: Ready (Pool size:", XPOrbConfig.POOL_SIZE, ")")
end

return OrbVisualsController
