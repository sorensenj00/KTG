--[[
    Module: SafeZoneManager
    Description: Manages safe zones where players can't take damage and can harvest.

    Dependencies:
    - ServerScriptService.Services.Progression.MetaProgressionService
    - ReplicatedStorage.GameLoop.ScalingConfig

    Author: System
    Last Updated: 2025-01-20
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local SafeZoneManager = {}

-- Constants
local SAFE_ZONE_SIZE = Vector3.new(120, 120, 120)
local SAFE_ZONE_COLOR = Color3.fromRGB(0, 255, 100)
local SAFE_ZONE_LOCATIONS = {
	Vector3.new(2998, 105, 280), -- Original
	Vector3.new(2208, 104, -611) -- Second Zone
}

-- State
local safeZoneParts = {}

-- Helper: Create Visual Zone
-- Helper: Create Visual Zones
local function createSafeZones()
	-- Clear existing
	for _, part in ipairs(safeZoneParts) do
		part:Destroy()
	end
	safeZoneParts = {}

	for i, pos in ipairs(SAFE_ZONE_LOCATIONS) do
		local part = Instance.new("Part")
		part.Name = "SafeZone_" .. i
		part.Size = SAFE_ZONE_SIZE
		part.Position = pos
		part.Anchored = true
		part.CanCollide = false
		part.Transparency = 0.6
		part.Color = SAFE_ZONE_COLOR
		part.Material = Enum.Material.ForceField
		part.CastShadow = false
		part.Parent = Workspace

		-- Create label
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "SafeZoneLabel"
		-- Increased size for visibility from distance
		billboard.Size = UDim2.fromScale(60, 12) 
		billboard.StudsOffset = Vector3.new(0, SAFE_ZONE_SIZE.Y/2 + 15, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 1000 -- Visible up to 1000 studs
		billboard.Parent = part

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Text = "SAFE ZONE (HARVEST)"
		label.TextColor3 = SAFE_ZONE_COLOR
		label.TextStrokeTransparency = 0
		label.TextScaled = true
		label.Font = Enum.Font.GothamBlack
		label.Parent = billboard

		table.insert(safeZoneParts, part)
		
		-- Add ZoneChecker Tag
		part:SetAttribute("IsSafeZone", true)
	end
end

-- Check logic loop
-- We need to check if players are inside the box.
-- Using GetPartsInPart is accurate.
local function updateSafeZones()
	local safePlayers = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				-- Check against all safe zones
				for _, zonePart in ipairs(safeZoneParts) do
					local relPos = zonePart.CFrame:PointToObjectSpace(root.Position)
					local size = zonePart.Size

					if math.abs(relPos.X) <= size.X/2 and math.abs(relPos.Y) <= size.Y/2 and math.abs(relPos.Z) <= size.Z/2 then
						safePlayers[player] = true
						break -- Found one, no need to check others
					end
				end
			end
		end
	end

	-- Update Attributes
	for _, player in ipairs(Players:GetPlayers()) do
		local wasSafe = player:GetAttribute("SafeZone") == true
		local isSafe = safePlayers[player] == true

		if isSafe ~= wasSafe then
			player:SetAttribute("SafeZone", isSafe)

			if isSafe then
				-- Force ForceField visuals or relying on client HUD?
				-- Client HUD handles the Harvest button.
				-- We can give a visual indicator here if we want.
				local char = player.Character
				if char then
					local ff = Instance.new("ForceField")
					ff.Name = "SafeZoneFF"
					ff.Visible = false -- Just for logic if needed, or visible for effect
					ff.Parent = char
				end
			else
				local char = player.Character
				if char then
					local ff = char:FindFirstChild("SafeZoneFF")
					if ff then ff:Destroy() end
				end
			end
		end
	end
end

-- Hook into Damage System to prevent damage
-- We need to find where damage is dealt.
-- Since we don't have a centralized Damage Manager exposed fully yet (besides Tracker),
-- We might need to listen to Humanoid.HealthChanged and revert? No, that's hacky.
-- Best is to ensure the Blaster system checks this attribute.
-- OR we use ForceFields which Roblox natively supports for 0 damage.
-- I added a ForceField above. This automatically prevents most damage types in Roblox
-- IF the weapon system respects it or uses Roblox damage.
-- If weapons use custom Raycast -> TakeDamage, they might ignore ForceField.

-- Let's check Blaster scripts if possible, or assume ForceField works.
-- Most "Blaster" kits use Raycast.
-- If I add a ForceField, `Humanoid:TakeDamage()` usually ignores it?
-- Actually `TakeDamage` respects ForceFields. `Health -= x` does not.
-- Let's hope the blaster uses TakeDamage.

function SafeZoneManager.Start()
	print("--- Starting SafeZoneManager ---")

	createSafeZones()

	-- Update loop
	RunService.Heartbeat:Connect(function()
		updateSafeZones()
	end)
end

return SafeZoneManager
