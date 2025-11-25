local Lighting = game:GetService("Lighting")

local LightingSetup = {}

function LightingSetup.Start()
	print(">> Configuring Competitive FPS Lighting...")

	-- 1. Technology: ShadowMap is standard for FPS (Performance + Looks), Future is heavier.
	-- If you want max FPS, use ShadowMap. If you want best graphics, use Future.
	pcall(function()
		Lighting.Technology = Enum.Technology.ShadowMap
	end)

	-- 2. "Big Game" Lighting Settings
	-- Neutral lighting helps players spot enemies quickly.
	Lighting.Ambient = Color3.fromRGB(50, 50, 50) -- Dark grey for crisp shadows (not pitch black)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 120, 120) -- Light grey to bounce light into shadows
	Lighting.Brightness = 2.5 -- Bright and sunny
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.2 -- Sharper shadows look more competitive/modern
	Lighting.ClockTime = 12 -- High noon (prevents long shadows hiding enemies)
	Lighting.ExposureCompensation = 0 -- Keep it standard
	Lighting.ColorShift_Top = Color3.fromRGB(255, 255, 255) -- Pure white sunlight
	Lighting.ColorShift_Bottom = Color3.fromRGB(0, 0, 0)

	-- 3. ColorCorrection: The "Pop" Factor
	local cc = Lighting:FindFirstChild("ColorCorrection") or Instance.new("ColorCorrectionEffect")
	cc.Name = "ColorCorrection"
	cc.Parent = Lighting
	cc.Saturation = 0.2 -- Slightly vibrant, but not blinding
	cc.Contrast = 0.1 -- Slight contrast to make textures stand out
	cc.Brightness = 0 -- Let Lighting.Brightness handle the heavy lifting

	-- 4. Bloom: Toned DOWN
	-- FPS games keep bloom low so the UI and reticle don't glow/blur.
	local bloom = Lighting:FindFirstChild("Bloom") or Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Parent = Lighting
	bloom.Intensity = 0.3 -- Subtle glow
	bloom.Size = 24
	bloom.Threshold = 2 -- Only very bright things (like neon) will glow

	-- 5. SunRays: Adds that "High Quality" feel
	local rays = Lighting:FindFirstChild("SunRays") or Instance.new("SunRaysEffect")
	rays.Name = "SunRays"
	rays.Parent = Lighting
	rays.Intensity = 0.1
	rays.Spread = 0.8

	-- 6. Atmosphere: The modern replacement for Fog
	local atmos = Lighting:FindFirstChild("Atmosphere") or Instance.new("Atmosphere")
	atmos.Name = "Atmosphere"
	atmos.Parent = Lighting
	atmos.Density = 0.3 -- Clear visibility
	atmos.Offset = 0
	atmos.Haze = 0
	atmos.Color = Color3.fromRGB(199, 199, 199)
	atmos.Decay = Color3.fromRGB(106, 112, 125)
	atmos.Glare = 0

	-- 7. Blue Skybox (Standard FPS Look)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end

	-- This is a clean, realistic blue sky with white clouds
	-- Much better for visibility than the pink/purple one
	local skyID = 14493324197 -- Clean Blue Sky ID

	sky.SkyboxBk = "rbxassetid://" .. skyID
	sky.SkyboxDn = "rbxassetid://" .. skyID
	sky.SkyboxFt = "rbxassetid://" .. skyID
	sky.SkyboxLf = "rbxassetid://" .. skyID
	sky.SkyboxRt = "rbxassetid://" .. skyID
	sky.SkyboxUp = "rbxassetid://" .. skyID

	-- Set sun texture to match
	sky.SunTextureId = "rbxassetid://6196665106"

	print("✅ Competitive Lighting Configured")
end

return LightingSetup
