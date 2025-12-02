--[[
    Service: SafeZoneService
    Description: Manages safe zone attributes on players.

    Refactor Goals:
    - Decoupled from View (No GUI creation).
    - Optimized detection (Interval checks + Spatial Query).
    - Single Responsibility: Logic Only.

    Author: System (Refactored)
    Last Updated: 2025-01-20
]]

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SafeZoneConfig = require(ReplicatedStorage.GameLoop.SafeZoneConfig)

local SafeZoneService = {}

-- State
local safeZoneRegions = {} -- {CFrame, Size} for OBB checks
local nextCheckTime = 0
local CHECK_INTERVAL = 0.25 -- Check 4 times a second (instead of 60)

local function initializeRegions()
    for _, pos in ipairs(SafeZoneConfig.SAFE_ZONE_LOCATIONS) do
        table.insert(safeZoneRegions, {
            CFrame = CFrame.new(pos),
            Size = SafeZoneConfig.SAFE_ZONE_SIZE
        })
    end
end

-- Efficient OBB (Oriented Bounding Box) Check
-- Since zones are currently Axis Aligned (Rotation 0), we can use simple AABB
local function isPointInZone(point: Vector3): boolean
    for _, zone in ipairs(safeZoneRegions) do
        local relPos = zone.CFrame:PointToObjectSpace(point)
        local size = zone.Size

        if math.abs(relPos.X) <= size.X/2 and
           math.abs(relPos.Y) <= size.Y/2 and
           math.abs(relPos.Z) <= size.Z/2 then
            return true
        end
    end
    return false
end

local function updateSafeZones()
    -- Only run logic periodically
    local now = tick()
    if now < nextCheckTime then return end
    nextCheckTime = now + CHECK_INTERVAL

    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if not character then continue end

        local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
        if not root then continue end

        -- Level Cap Check first (Cheapest)
        local level = player:GetAttribute("Level") or 1
        local isSafe = false

        if level <= SafeZoneConfig.MAX_LEVEL then
            -- Spatial Check
            if isPointInZone(root.Position) then
                isSafe = true
            end
        end

        -- State Update
        local wasSafe = player:GetAttribute("SafeZone") == true

        if isSafe ~= wasSafe then
            player:SetAttribute("SafeZone", isSafe)

            -- ForceField Logic (Server-side Authority)
            -- While Client visuals are nice, Server FF prevents standard Roblox damage
            if isSafe then
                local ff = Instance.new("ForceField")
                ff.Name = "SafeZoneFF"
                ff.Visible = false -- Client handles visuals
                ff.Parent = character
            else
                local ff = character:FindFirstChild("SafeZoneFF")
                if ff then ff:Destroy() end
            end
        end
    end
end

function SafeZoneService.Start()
    print("--- Starting SafeZoneService (Logic Only) ---")

    initializeRegions()

    RunService.Heartbeat:Connect(updateSafeZones)
end

function SafeZoneService.IsPlayerInSafeZone(player: Player): boolean
    return player:GetAttribute("SafeZone") == true
end

return SafeZoneService
