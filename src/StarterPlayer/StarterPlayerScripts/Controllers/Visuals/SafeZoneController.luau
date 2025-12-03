--[[
    Controller: SafeZoneController
    Description: Handles client-side visuals for Safe Zones (Notifications, ForceFields, Labels).

    Refactor Goals:
    - Handle BillboardGui creation locally.
    - React to SafeZone attribute changes for visuals.

    Author: System (Refactored)
    Last Updated: 2025-01-20
]]

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")


local SafeZoneConfig = require(ReplicatedStorage.GameLoop.SafeZoneConfig)

local SafeZoneController = {}

local player = Players.LocalPlayer

-- Visual Assets
local zoneVisuals = {}

local function createZoneVisuals()
    for i, pos in ipairs(SafeZoneConfig.SAFE_ZONE_LOCATIONS) do
        local part = Instance.new("Part")
        part.Name = "SafeZoneVisual_" .. i
        part.Size = SafeZoneConfig.SAFE_ZONE_SIZE
        part.Position = pos
        part.Anchored = true
        part.CanCollide = false
        part.Transparency = 0.5
        part.Color = Color3.fromRGB(0, 255, 100)
        part.Material = Enum.Material.ForceField
        part.CastShadow = false
        part.Parent = Workspace

        -- Create label
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "SafeZoneLabel"
        billboard.Size = UDim2.fromScale(60, 12)
        billboard.StudsOffset = Vector3.new(0, SafeZoneConfig.SAFE_ZONE_SIZE.Y/2 + 15, 0)
        billboard.AlwaysOnTop = true
        billboard.MaxDistance = 1000
        billboard.Parent = part

        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Text = "SAFE ZONE (HARVEST)"
        label.TextColor3 = Color3.fromRGB(0, 255, 100)
        label.TextStrokeTransparency = 0
        label.TextScaled = true
        label.Font = Enum.Font.GothamBlack
        label.Parent = billboard

        table.insert(zoneVisuals, part)
    end
end

local function onAttributeChanged(attribute: string)
    if attribute == "SafeZone" then
        local isSafe = player:GetAttribute("SafeZone")

        if isSafe then
            -- Enable Visuals
            -- Could add a screen notification here
            print("Entered Safe Zone")

            -- Optional: Client-side Highlight visual if Server one is invisible
            local char = player.Character
            if char then
                local hl = char:FindFirstChild("VisualHighlight") or Instance.new("Highlight")
                hl.Name = "VisualHighlight"
                hl.FillColor = Color3.fromRGB(0, 255, 100)
                hl.FillTransparency = 0.9
                hl.OutlineTransparency = 0.9
                hl.Parent = char
            end
        else
            -- Disable Visuals
            print("Left Safe Zone")
             local char = player.Character
            if char then
                local hl = char:FindFirstChild("VisualHighlight")
                if hl then hl:Destroy() end
            end
        end
    end
end

function SafeZoneController.Start()
    print("--- Starting SafeZoneController (Visuals) ---")

    createZoneVisuals()

    player.AttributeChanged:Connect(onAttributeChanged)

    -- Initial Check
    if player:GetAttribute("SafeZone") then
        onAttributeChanged("SafeZone")
    end
end

return SafeZoneController
