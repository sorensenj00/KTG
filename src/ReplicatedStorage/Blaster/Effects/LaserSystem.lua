--[[
    Module: LaserSystem
    Description: Creates high-quality, instant laser beam effects.
    
    Configuration:
    - Modern Red Laser style.
    - High visibility and smooth fade out.
    
    Author: System
    Last Updated: 2025-11-26
]]


local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- === VISUAL CONFIGURATION ===

local BEAM_TEXTURE = "rbxassetid://446111271" -- Soft beam texture
local COLOR_CORE = ColorSequence.new(Color3.fromRGB(255, 255, 255)) -- White core
local COLOR_GLOW = ColorSequence.new(Color3.fromRGB(255, 0, 0))     -- Red glow

local FADE_TIME = 0.5 -- Seconds (Increased from 0.2 for better visibility)
local CORE_WIDTH = 0.15
local GLOW_WIDTH = 0.6

local function createLaserBeam(startPosition, endPosition)
	-- 1. Create Container
	local container = Instance.new("Part")
	container.Name = "LaserFX"
	container.Transparency = 1
	container.CanCollide = false
	container.Anchored = true
	container.Size = Vector3.new(0.1, 0.1, 0.1)
	container.Position = startPosition
	container.Parent = Workspace

	-- 2. Create Attachments
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0, 0)
	att0.Parent = container

	local att1 = Instance.new("Attachment")
	local relativeEnd = endPosition - startPosition
	att1.Position = relativeEnd
	att1.Parent = container

	-- 3. Create Core Beam (The bright center)
	local coreBeam = Instance.new("Beam")
	coreBeam.Name = "CoreBeam"
	coreBeam.Attachment0 = att0
	coreBeam.Attachment1 = att1
	coreBeam.Texture = BEAM_TEXTURE
	coreBeam.TextureMode = Enum.TextureMode.Stretch
	coreBeam.TextureSpeed = 0
	coreBeam.LightEmission = 1
	coreBeam.LightInfluence = 0
	coreBeam.Transparency = NumberSequence.new(0)
	coreBeam.Color = COLOR_CORE
	coreBeam.Width0 = CORE_WIDTH
	coreBeam.Width1 = CORE_WIDTH
	coreBeam.FaceCamera = true
	coreBeam.Segments = 1
	coreBeam.ZOffset = 0.1 -- Render on top of glow
	coreBeam.Parent = container

	-- 4. Create Glow Beam (The outer color)
	local glowBeam = Instance.new("Beam")
	glowBeam.Name = "GlowBeam"
	glowBeam.Attachment0 = att0
	glowBeam.Attachment1 = att1
	glowBeam.Texture = BEAM_TEXTURE
	glowBeam.TextureMode = Enum.TextureMode.Stretch
	glowBeam.TextureSpeed = 0
	glowBeam.LightEmission = 1
	glowBeam.LightInfluence = 0
	glowBeam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.4)
	})
	glowBeam.Color = COLOR_GLOW
	glowBeam.Width0 = GLOW_WIDTH
	glowBeam.Width1 = GLOW_WIDTH
	glowBeam.FaceCamera = true
	glowBeam.Segments = 1
	glowBeam.Parent = container

	-- 5. Lights (Impact/Muzzle Flash)
	local startFlash = Instance.new("PointLight")
	startFlash.Color = Color3.fromRGB(255, 100, 100)
	startFlash.Brightness = 8
	startFlash.Range = 6
	startFlash.Parent = container

	local endPart = Instance.new("Part")
	endPart.Name = "EndFlash"
	endPart.Transparency = 1
	endPart.CanCollide = false
	endPart.Anchored = true
	endPart.Size = Vector3.new(0.1, 0.1, 0.1)
	endPart.Position = endPosition
	endPart.Parent = container

	local endFlash = Instance.new("PointLight")
	endFlash.Color = Color3.fromRGB(255, 50, 50)
	endFlash.Brightness = 8
	endFlash.Range = 8
	endFlash.Parent = endPart

	-- 6. Animation
	-- Fade out lights quickly
	TweenService:Create(startFlash, TweenInfo.new(0.2), {Brightness = 0, Range = 0}):Play()
	TweenService:Create(endFlash, TweenInfo.new(0.2), {Brightness = 0, Range = 0}):Play()

	local startTime = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.clamp(elapsed / FADE_TIME, 0, 1)
		
		if alpha >= 1 then
			connection:Disconnect()
			container:Destroy()
			return
		end

		-- Fade out beams
		-- Core fades to transparent
		coreBeam.Transparency = NumberSequence.new(alpha)
		
		-- Glow fades but stays slightly visible longer
		local glowAlpha = 0.4 + (0.6 * alpha)
		glowBeam.Transparency = NumberSequence.new(glowAlpha)
		
		-- Shrink width slightly
		local widthScale = 1 - (alpha * 0.5)
		coreBeam.Width0 = CORE_WIDTH * widthScale
		coreBeam.Width1 = CORE_WIDTH * widthScale
		glowBeam.Width0 = GLOW_WIDTH * widthScale
		glowBeam.Width1 = GLOW_WIDTH * widthScale
	end)
end

return createLaserBeam

