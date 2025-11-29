local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local LightingService = {}

function LightingService.Init()
	print("Initializing Realistic Lighting...")
	
	-- Note: Unified Lighting is active. Ensure "LightingStyle" is set to "Realistic" 
	-- in Lighting properties for the best visual quality.

	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.5 -- Softer shadows
	Lighting.Ambient = Color3.fromRGB(30, 30, 30) -- Darker ambient (Skybox light provides fill)
	Lighting.OutdoorAmbient = Color3.fromRGB(50, 50, 50) -- Darker outdoor (Skybox light provides fill)
	Lighting.Brightness = 2 -- Balanced sunlight with PBR
	Lighting.ColorShift_Top = Color3.fromRGB(255, 248, 230) -- Subtle warm sunlight
	Lighting.EnvironmentDiffuseScale = 1 -- Enable PBR Environment Lighting
	Lighting.EnvironmentSpecularScale = 1 -- Enable PBR Reflections
	Lighting.ClockTime = 17 -- Slightly earlier for better angle? Or keep 17.5. Let's try 17.2
	Lighting.GeographicLatitude = 45

	-- Atmosphere
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmosphere.Density = 0.35 -- Slightly clearer air
	atmosphere.Offset = 0
	atmosphere.Color = Color3.fromRGB(180, 180, 180) -- Neutral horizon
	atmosphere.Decay = Color3.fromRGB(100, 100, 100)
	atmosphere.Glare = 0.4
	atmosphere.Haze = 1.5
	atmosphere.Parent = Lighting

	-- SunRays (Global)
	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect") or Instance.new("SunRaysEffect")
	sunRays.Intensity = 0.3 -- Balanced rays
	sunRays.Spread = 0.5
	sunRays.Parent = Lighting

	-- Bloom (Glow)
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect") or Instance.new("BloomEffect")
	bloom.Intensity = 0.1
	bloom.Size = 24
	bloom.Threshold = 0.8
	bloom.Parent = Lighting
	
	-- ColorCorrection (Contrast & Saturation)
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.2 -- Vibrant
	cc.Contrast = 0.2 -- High contrast
	cc.Parent = Lighting
	
	-- Blur (Optional, maybe for depth)
	-- local blur = Lighting:FindFirstChildOfClass("BlurEffect") or Instance.new("BlurEffect")
	-- blur.Size = 2
	-- blur.Parent = Lighting
end

function LightingService.Start()
	-- Enhance Window Sunrays
	task.spawn(function()
		task.wait(3) -- Wait for map load
		
		print("Searching for Window Sunrays...")
		-- Find the window glass and ensure it lets light through
		for _, descendant in ipairs(Workspace:GetDescendants()) do
			if descendant.Name == "Glass" and descendant:IsA("Model") then
				print("Found Glass Model in " .. descendant:GetFullName())
				
				-- Check for GiantSunRays
				local beams = {}
				local attachments = {}
				
				for _, child in ipairs(descendant:GetChildren()) do
					if child:IsA("Attachment") then
						table.insert(attachments, child)
					elseif child.Name == "GiantSunRays" and child:IsA("Beam") then
						table.insert(beams, child)
					elseif child:IsA("BasePart") then
						-- Glass parts
						child.CastShadow = false -- CRITICAL for sunrays to pass through
						child.Material = Enum.Material.Glass
						child.Transparency = 0.7
					end
				end
				
				-- Configure Beams (Respect user settings, just ensure they work)
				for _, beam in ipairs(beams) do
					-- Only auto-assign attachments if completely missing
					if (not beam.Attachment0 or not beam.Attachment1) and #attachments >= 2 then
						beam.Attachment0 = attachments[1]
						beam.Attachment1 = attachments[2]
						print("Auto-assigned attachments to beam")
					end
					
					beam.Enabled = true
				end
				
				if #beams > 0 then
					print("Enhanced " .. #beams .. " GiantSunRays beams.")
				end
			end
		end
	end)
end

return LightingService
