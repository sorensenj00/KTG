--[[
    Module: LaserSystem
    Description: Creates high-quality, instant laser beam effects.
    
    Configuration:
    - Defaults to Red Core + Glow for high visibility.
    - Uncomment the "Retro Style" block below to restore Green/Purple.
    
    Author: System
    Last Updated: 2025-01-20
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage.Blaster.Constants)

-- === VISUAL CONFIGURATION ===

-- STYLE 1: MODERN RED LASER (Default)
local BEAM_TEXTURE = "rbxassetid://446111271" 
local COLOR_CORE = ColorSequence.new(Color3.new(1, 1, 1))
local COLOR_GLOW = ColorSequence.new(Color3.fromRGB(255, 0, 0))

-- STYLE 2: RETRO GREEN/PURPLE (Uncomment to use)
--[[ 
local BEAM_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local COLOR_CORE = ColorSequence.new(Color3.fromRGB(200, 255, 200))
local COLOR_GLOW = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 255, 100)), -- Neon Green
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 0, 255)), -- Purple
    ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 100)) -- Neon Green
})
]]

local function createLaserBeam(startPosition: Vector3, endPosition: Vector3)
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

	-- 3. Create Core Beam
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
	coreBeam.Width0 = 0.1
	coreBeam.Width1 = 0.1
	coreBeam.FaceCamera = true
	coreBeam.Segments = 1
	coreBeam.Parent = container

	-- 4. Create Glow Beam
	local glowBeam = Instance.new("Beam")
	glowBeam.Name = "GlowBeam"
	glowBeam.Attachment0 = att0
	glowBeam.Attachment1 = att1
	glowBeam.Texture = "rbxasset://textures/particles/smoke_main.dds"
	glowBeam.TextureMode = Enum.TextureMode.Wrap
	glowBeam.TextureSpeed = 2
	glowBeam.TextureLength = 10
	glowBeam.LightEmission = 1
	glowBeam.LightInfluence = 0
	glowBeam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0.5)
	})
	glowBeam.Color = COLOR_GLOW
	glowBeam.Width0 = 0.4
	glowBeam.Width1 = 0.4
	glowBeam.FaceCamera = true
	glowBeam.Segments = 10
	glowBeam.Parent = container

	-- 5. Lights
	local startFlash = Instance.new("PointLight")
	startFlash.Color = Color3.fromRGB(255, 50, 50) -- Matches Red default
	startFlash.Brightness = 5
	startFlash.Range = 8
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
	endFlash.Brightness = 5
	endFlash.Range = 6
	endFlash.Parent = endPart

	-- 6. Animation
	local fadeTime = 0.2
	TweenService:Create(startFlash, TweenInfo.new(fadeTime), {Brightness = 0, Range = 0}):Play()
	TweenService:Create(endFlash, TweenInfo.new(fadeTime), {Brightness = 0, Range = 0}):Play()

	local startTime = tick()
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local alpha = math.clamp(elapsed / fadeTime, 0, 1)
		
		if alpha >= 1 then
			connection:Disconnect()
			container:Destroy()
			return
		end

		coreBeam.Transparency = NumberSequence.new(alpha)
		local glowAlpha = 0.5 + (0.5 * alpha)
		glowBeam.Transparency = NumberSequence.new(glowAlpha)
		
		coreBeam.Width0 = 0.1 * (1 - alpha)
		coreBeam.Width1 = 0.1 * (1 - alpha)
	end)
end

return createLaserBeam

