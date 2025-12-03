--[[
    Module: LaserSystem
    Description: Creates high-quality, instant laser beam effects with object pooling.
    
    Configuration:
    - Modern Red Laser style.
    - High visibility and smooth fade out.
    - Object pooling to prevent GC thrashing.
    - Single update loop for ALL lasers (prevents connection spam during rapid fire).
    
    Author: System
    Last Updated: 2025-12-02
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local PartPool = require(ReplicatedStorage.Utility.PartPool)

-- === VISUAL CONFIGURATION ===

local BEAM_TEXTURE = "rbxassetid://446111271" -- Soft beam texture
local COLOR_CORE = ColorSequence.new(Color3.fromRGB(255, 255, 255)) -- White core
local COLOR_GLOW = ColorSequence.new(Color3.fromRGB(255, 0, 0))     -- Red glow

local FADE_TIME = 0.5 -- Seconds (Increased from 0.2 for better visibility)
local CORE_WIDTH = 0.15
local GLOW_WIDTH = 0.6

-- === ACTIVE LASERS TRACKING ===
-- Single update loop manages all active lasers instead of per-laser connections
local activeLasers = {} -- {container, startTime, coreBeam, glowBeam}
local updateLoopRunning = false

-- === OBJECT POOL SETUP ===

-- Create template laser container
local function createLaserTemplate()
	local container = Instance.new("Part")
	container.Name = "LaserFX"
	container.Transparency = 1
	container.CanCollide = false
	container.Anchored = true
	container.Size = Vector3.new(0.1, 0.1, 0.1)

	-- Attachments
	local att0 = Instance.new("Attachment")
	att0.Name = "Att0"
	att0.Position = Vector3.new(0, 0, 0)
	att0.Parent = container

	local att1 = Instance.new("Attachment")
	att1.Name = "Att1"
	att1.Parent = container

	-- Core Beam
	local coreBeam = Instance.new("Beam")
	coreBeam.Name = "CoreBeam"
	coreBeam.Attachment0 = att0
	coreBeam.Attachment1 = att1
	coreBeam.Texture = BEAM_TEXTURE
	coreBeam.TextureMode = Enum.TextureMode.Stretch
	coreBeam.TextureSpeed = 0
	coreBeam.LightEmission = 1
	coreBeam.LightInfluence = 0
	coreBeam.Color = COLOR_CORE
	coreBeam.Width0 = CORE_WIDTH
	coreBeam.Width1 = CORE_WIDTH
	coreBeam.FaceCamera = true
	coreBeam.Segments = 1
	coreBeam.ZOffset = 0.1
	coreBeam.Parent = container

	-- Glow Beam
	local glowBeam = Instance.new("Beam")
	glowBeam.Name = "GlowBeam"
	glowBeam.Attachment0 = att0
	glowBeam.Attachment1 = att1
	glowBeam.Texture = BEAM_TEXTURE
	glowBeam.TextureMode = Enum.TextureMode.Stretch
	glowBeam.TextureSpeed = 0
	glowBeam.LightEmission = 1
	glowBeam.LightInfluence = 0
	glowBeam.Color = COLOR_GLOW
	glowBeam.Width0 = GLOW_WIDTH
	glowBeam.Width1 = GLOW_WIDTH
	glowBeam.FaceCamera = true
	glowBeam.Segments = 1
	glowBeam.Parent = container

	-- Start Light
	local startFlash = Instance.new("PointLight")
	startFlash.Name = "StartFlash"
	startFlash.Color = Color3.fromRGB(255, 100, 100)
	startFlash.Parent = container

	-- End Flash Part
	local endPart = Instance.new("Part")
	endPart.Name = "EndFlash"
	endPart.Transparency = 1
	endPart.CanCollide = false
	endPart.Anchored = true
	endPart.Size = Vector3.new(0.1, 0.1, 0.1)
	endPart.Parent = container

	local endFlash = Instance.new("PointLight")
	endFlash.Name = "EndLight"
	endFlash.Color = Color3.fromRGB(255, 50, 50)
	endFlash.Parent = endPart

	return container
end

-- Initialize pool
local laserPool = PartPool.new(createLaserTemplate(), 20)

-- Single update loop for ALL active lasers
local function updateAllLasers()
	local currentTime = tick()
	
	-- Iterate backwards to safely remove completed lasers
	for i = #activeLasers, 1, -1 do
		local laserData = activeLasers[i]
		local elapsed = currentTime - laserData.startTime
		local alpha = math.clamp(elapsed / FADE_TIME, 0, 1)
		
		if alpha >= 1 then
			-- Laser complete - return to pool and remove from tracking
			laserPool:Return(laserData.container)
			table.remove(activeLasers, i)
		else
			-- Update fade
			local coreBeam = laserData.coreBeam
			local glowBeam = laserData.glowBeam
			
			coreBeam.Transparency = NumberSequence.new(alpha)
			
			local glowAlpha = 0.4 + (0.6 * alpha)
			glowBeam.Transparency = NumberSequence.new(glowAlpha)
			
			-- Shrink width slightly
			local widthScale = 1 - (alpha * 0.5)
			coreBeam.Width0 = CORE_WIDTH * widthScale
			coreBeam.Width1 = CORE_WIDTH * widthScale
			glowBeam.Width0 = GLOW_WIDTH * widthScale
			glowBeam.Width1 = GLOW_WIDTH * widthScale
		end
	end
	
	-- Stop the loop if no active lasers (saves CPU when not shooting)
	if #activeLasers == 0 then
		updateLoopRunning = false
		return true -- Signal to disconnect
	end
	
	return false
end

-- Start update loop if not already running
local updateConnection = nil
local function ensureUpdateLoopRunning()
	if updateLoopRunning then return end
	
	updateLoopRunning = true
	updateConnection = RunService.Heartbeat:Connect(function()
		local shouldStop = updateAllLasers()
		if shouldStop and updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
		end
	end)
end

local function createLaserBeam(startPosition, endPosition)
	-- Get pooled instance
	local container = laserPool:Get()
	
	-- Position container
	container.Position = startPosition
	container.Parent = Workspace

	-- Get references to children (cached for update loop)
	local att1 = container:FindFirstChild("Att1")
	local coreBeam = container:FindFirstChild("CoreBeam")
	local glowBeam = container:FindFirstChild("GlowBeam")
	local startFlash = container:FindFirstChild("StartFlash")
	local endPart = container:FindFirstChild("EndFlash")
	local endFlash = endPart and endPart:FindFirstChild("EndLight")

	-- Update positions
	local relativeEnd = endPosition - startPosition
	att1.Position = relativeEnd
	if endPart then
		endPart.Position = endPosition
	end

	-- Reset visuals
	coreBeam.Transparency = NumberSequence.new(0)
	glowBeam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.4)
	})
	coreBeam.Width0 = CORE_WIDTH
	coreBeam.Width1 = CORE_WIDTH
	glowBeam.Width0 = GLOW_WIDTH
	glowBeam.Width1 = GLOW_WIDTH

	-- Reset lights
	startFlash.Brightness = 8
	startFlash.Range = 6
	if endFlash then
		endFlash.Brightness = 8
		endFlash.Range = 8
	end

	-- Fade out lights quickly (tweens are fine - they're managed by TweenService)
	TweenService:Create(startFlash, TweenInfo.new(0.2), {Brightness = 0, Range = 0}):Play()
	if endFlash then
		TweenService:Create(endFlash, TweenInfo.new(0.2), {Brightness = 0, Range = 0}):Play()
	end

	-- Add to active lasers list (single loop handles all)
	table.insert(activeLasers, {
		container = container,
		startTime = tick(),
		coreBeam = coreBeam,
		glowBeam = glowBeam,
	})
	
	-- Ensure the update loop is running
	ensureUpdateLoopRunning()
end

return createLaserBeam
