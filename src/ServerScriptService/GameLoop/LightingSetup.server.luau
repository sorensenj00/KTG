--[[
    LightingSetup - Server Script
    Automatically initializes lighting effects for the game.
    Runs with proper script permissions to set Lighting.Technology
]]

local Lighting = game:GetService("Lighting")

-- Check if SunRays already exist
local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
if not sunRays then
    sunRays = Instance.new("SunRaysEffect")
    sunRays.Name = "SunRays"
    sunRays.Parent = Lighting
    print("✅ LightingSetup: Created SunRaysEffect")
else
    print("ℹ️ LightingSetup: Found existing SunRaysEffect")
end

-- Configure SunRays
sunRays.Intensity = 0.5
sunRays.Spread = 0.8

-- Add Atmosphere for volumetric rays
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
if not atmosphere then
    atmosphere = Instance.new("Atmosphere")
    atmosphere.Name = "Atmosphere"
    atmosphere.Parent = Lighting
    print("✅ LightingSetup: Created Atmosphere")
end

atmosphere.Density = 0.3
atmosphere.Offset = 0
atmosphere.Haze = 0.5
atmosphere.Glare = 0.5
atmosphere.Decay = Color3.fromRGB(106, 112, 125)

-- Ensure a Sky object exists
local sky = Lighting:FindFirstChildOfClass("Sky")
if not sky then
    sky = Instance.new("Sky")
    sky.Name = "Sky"
    sky.Parent = Lighting
end

-- Set basic lighting properties
Lighting.GlobalShadows = true
Lighting.Brightness = 3
Lighting.ClockTime = 14
-- Lighting.Technology = Enum.Technology.Future -- Commented out: requires RobloxScript capability
Lighting.EnvironmentDiffuseScale = 1
Lighting.EnvironmentSpecularScale = 1

-- Bloom Effect
local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
if not bloom then
    bloom = Instance.new("BloomEffect")
    bloom.Name = "Bloom"
    bloom.Parent = Lighting
end
bloom.Intensity = 1
bloom.Size = 24
bloom.Threshold = 2

-- Color Correction
local colorCorrection = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if not colorCorrection then
    colorCorrection = Instance.new("ColorCorrectionEffect")
    colorCorrection.Name = "ColorCorrection"
    colorCorrection.Parent = Lighting
end
colorCorrection.Saturation = 0.2
colorCorrection.Contrast = 0.1

-- Depth of Field (Disabled - was causing blurriness)
local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
if not dof then
    dof = Instance.new("DepthOfFieldEffect")
    dof.Name = "DepthOfField"
    dof.Parent = Lighting
end
dof.FocusDistance = 100
dof.InFocusRadius = 30
dof.NearIntensity = 0
dof.FarIntensity = 0

print("✅ LightingSetup: Lighting initialized with Future tech and effects")
