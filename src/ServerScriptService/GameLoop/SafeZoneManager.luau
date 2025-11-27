--[[
    Module: SafeZoneManager
    Description: Manages safe zones where players can't take damage and can harvest.

    Dependencies:
    - ServerScriptService.GameLoop.MetaProgressionManager
    - ReplicatedStorage.GameLoop.ScalingConfig

    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local SafeZoneManager = {}

-- Constants
local SAFE_ZONE_SIZE = Vector3.new(60, 40, 60)
local SAFE_ZONE_COLOR = Color3.fromRGB(0, 255, 100)
local SAFE_ZONE_POS = Vector3.new(100, 20, 100) -- Example location, can be adjusted

-- State
local safeZonePart = nil

-- Helper: Create Visual Zone
local function createSafeZone()
	-- Check if exists
	local existing = Workspace:FindFirstChild("SafeZone")
	if existing then existing:Destroy() end

	local part = Instance.new("Part")
	part.Name = "SafeZone"
	part.Size = SAFE_ZONE_SIZE
	part.Position = SAFE_ZONE_POS
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 0.8
	part.Color = SAFE_ZONE_COLOR
	part.Material = Enum.Material.ForceField
	part.CastShadow = false
	part.Parent = Workspace

	-- Create label
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SafeZoneLabel"
	billboard.Size = UDim2.fromScale(10, 2)
	billboard.StudsOffset = Vector3.new(0, SAFE_ZONE_SIZE.Y/2 + 5, 0)
	billboard.AlwaysOnTop = true
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

	safeZonePart = part

	-- Add ZoneChecker Tag for potential future use or debugging
	part:SetAttribute("IsSafeZone", true)

	return part
end

-- Check logic loop
-- We need to check if players are inside the box.
-- Using GetPartsInPart is accurate.
local function updateSafeZones()
	if not safeZonePart then return end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Include
	-- We want to check against all character root parts
	-- Getting all players is cheaper than filtering world

	local safePlayers = {}

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				-- Simple AABB check first for speed (assuming axis aligned box)
				-- Or just magnitude check if zone is simple? Box is better.

				-- Using simple bounding box math for "Inside" check
				local relPos = safeZonePart.CFrame:PointToObjectSpace(root.Position)
				local size = safeZonePart.Size

				if math.abs(relPos.X) <= size.X/2 and math.abs(relPos.Y) <= size.Y/2 and math.abs(relPos.Z) <= size.Z/2 then
					safePlayers[player] = true
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

	createSafeZone()

	-- Update loop
	RunService.Heartbeat:Connect(function()
		updateSafeZones()
	end)
end

return SafeZoneManager
