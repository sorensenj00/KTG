--[[
    Service: XPOrbService
    Description: Server-authoritative management of XP Orbs using data-only replication.

    Refactor Goals (Gold Standard):
    - Strict Typing via `XPOrbConfig`
    - Removed Logic-View Coupling (Networking handled cleanly)
    - Performance: Bucket-based Heartbeat for Magnetism
    - Config-driven logic

    Author: System (Refactored)
    Last Updated: 2025-01-20
]]

--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local XPOrbConfig = require(ReplicatedStorage.GameLoop.XPOrbConfig)
local ServiceBus = require(ServerScriptService.Services.ServiceBus)

-- Remotes (Created/Fetched internally)
local NetworkingFolder = ReplicatedStorage:FindFirstChild("Networking")
if not NetworkingFolder then
    NetworkingFolder = Instance.new("Folder")
    NetworkingFolder.Name = "Networking"
    NetworkingFolder.Parent = ReplicatedStorage
end

local OrbEvents = NetworkingFolder:FindFirstChild("OrbEvents") or Instance.new("RemoteEvent")
OrbEvents.Name = "OrbEvents"
OrbEvents.Parent = NetworkingFolder

local CollectOrbRemote = NetworkingFolder:FindFirstChild("CollectOrb") or Instance.new("RemoteEvent")
CollectOrbRemote.Name = "CollectOrb"
CollectOrbRemote.Parent = NetworkingFolder

-- Types
type OrbData = XPOrbConfig.OrbData

local XPOrbService = {}

-- State
local activeOrbs: { [number]: OrbData } = {}
local nextOrbId: number = 1

-- Bucket Scheduler State
local magnetBucketIndex = 1
local MAGNET_BUCKET_COUNT = 10 -- Split processing into 10 frames
local orbKeys = {} -- Cache keys for iteration to avoid pairs() overhead in buckets if possible,
                   -- but pairs() is generally fine. We'll iterate all but skip based on ID % Buckets

--[[
    -------------------------------------------------------------------------
    PRIVATE METHODS
    -------------------------------------------------------------------------
]]

local function getRandomSpawnPosition(): Vector3
    local baseplate = Workspace:FindFirstChild("Baseplate")
        or Workspace:FindFirstChild("Map")
        or Workspace:FindFirstChild("Ground")

    local centerX, centerZ = 0, 0
    local sizeX, sizeZ = 2048, 2048

    if baseplate then
        if baseplate:IsA("Model") then
            local cf, s = baseplate:GetBoundingBox()
            centerX, centerZ = cf.Position.X, cf.Position.Z
            sizeX, sizeZ = s.X, s.Z
        elseif baseplate:IsA("BasePart") then
            centerX, centerZ = baseplate.Position.X, baseplate.Position.Z
            sizeX, sizeZ = baseplate.Size.X, baseplate.Size.Z
        end
    end

    local halfSizeX = sizeX / 2
    local halfSizeZ = sizeZ / 2

    local x = math.random(-halfSizeX + 20, halfSizeX - 20)
    local z = math.random(-halfSizeZ + 20, halfSizeZ - 20)

    local targetX = centerX + x
    local targetZ = centerZ + z

    -- Raycast to find floor height
    local rayOrigin = Vector3.new(targetX, 500, targetZ)
    local rayDirection = Vector3.new(0, -1000, 0)

    local raycastParams = RaycastParams.new()
    raycastParams.FilterType = Enum.RaycastFilterType.Exclude
    raycastParams.FilterDescendantsInstances = {Players}
    raycastParams.RespectCanCollide = true

    local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)

    local yPos = 10
    if rayResult then
        yPos = rayResult.Position.Y
    end

    return Vector3.new(targetX, yPos, targetZ)
end

local function getCollectionRange(entity: Instance): number
    local scale = entity:GetAttribute("Scale") or 1.0
    return XPOrbConfig.BASE_COLLECTION_RANGE + (scale * XPOrbConfig.SCALE_FACTOR)
end

--[[
    -------------------------------------------------------------------------
    CORE LOGIC
    -------------------------------------------------------------------------
]]

local function despawnOrb(orbId: number)
    if activeOrbs[orbId] then
        activeOrbs[orbId] = nil
        OrbEvents:FireAllClients({Action = "Despawn", Id = orbId})
    end
end

local function spawnOrbInternal(position: Vector3, isDrop: boolean?, forcedXP: number?)
    -- Limit Check
    local count = 0
    for _ in pairs(activeOrbs) do count += 1 end

    if count >= XPOrbConfig.MAX_ORBS then
        local oldestId, oldestOrb = next(activeOrbs)
        if oldestId then
            despawnOrb(oldestId)
        end
    end

    -- Determine Tier
    local selectedTier = XPOrbConfig.TIERS.Common

    if forcedXP then
        -- Find appropriate tier for forced XP
        if forcedXP >= XPOrbConfig.TIERS.Legendary.XP then selectedTier = XPOrbConfig.TIERS.Legendary
        elseif forcedXP >= XPOrbConfig.TIERS.Rare.XP then selectedTier = XPOrbConfig.TIERS.Rare
        elseif forcedXP >= XPOrbConfig.TIERS.Uncommon.XP then selectedTier = XPOrbConfig.TIERS.Uncommon
        end
    else
        -- Random Tier
        local randomValue = math.random(1, 100)
        local accumulatedChance = 0

        for _, tier in ipairs(XPOrbConfig.TIER_LIST) do
            accumulatedChance += tier.Chance
            if randomValue <= accumulatedChance then
                selectedTier = tier
                break
            end
        end
    end

    -- Scaling Logic (Average Level)
    local xpValue = forcedXP or selectedTier.XP
    if not forcedXP then
        local totalLevel = 0
        local playerCount = 0
        for _, p in ipairs(Players:GetPlayers()) do
            totalLevel += (p:GetAttribute("Level") or 1)
            playerCount += 1
        end
        local avgLevel = playerCount > 0 and (totalLevel / playerCount) or 1
        -- Only 10% bonus per average level, capped at 5x (anti-inflation)
        local scalingMult = math.min(5, 1 + (avgLevel * 0.1))
        xpValue = math.floor(selectedTier.XP * scalingMult)
    end

    local orbId = nextOrbId
    nextOrbId += 1

    -- Ensure spawn is slightly above ground based on tier size
    local adjustedPos = position + Vector3.new(0, selectedTier.Size.Y / 2, 0)

    local newOrb: OrbData = {
        Id = orbId,
        Position = adjustedPos,
        Tier = selectedTier,
        CurrentSize = selectedTier.Size,
        XP = xpValue,
        SpawnTime = tick(),
        GrowthStage = 0,
        MagnetTarget = nil,
        IsDrop = isDrop
    }

    activeOrbs[orbId] = newOrb

    OrbEvents:FireAllClients({
        Action = "Spawn",
        Id = orbId,
        Position = adjustedPos,
        Tier = selectedTier,
        XP = xpValue,
        IsDrop = isDrop
    })
end

--[[
    -------------------------------------------------------------------------
    UPDATE LOOPS
    -------------------------------------------------------------------------
]]

local function updateOrbs(dt: number)
    local currentTime = tick()

    -- Increment Bucket
    magnetBucketIndex = (magnetBucketIndex % MAGNET_BUCKET_COUNT) + 1

    for orbId, orb in pairs(activeOrbs) do
        -- 1. Lifetime & Growth (Check infrequently?)
        -- Since growth is every 10s, we can check it every frame or bucket. Checking every frame is cheap math.
        local age = currentTime - orb.SpawnTime

        if age > XPOrbConfig.MAX_LIFETIME then
            despawnOrb(orbId)
            continue
        end

        -- Growth
        local currentStage = math.floor(age / XPOrbConfig.ORB_GROWTH_INTERVAL)
        if currentStage > orb.GrowthStage and orb.GrowthStage < XPOrbConfig.MAX_GROWTH_STAGES then
            orb.GrowthStage = currentStage
            orb.XP = math.floor(orb.XP * 1.5)
            orb.CurrentSize = orb.CurrentSize * 1.25
        end

        -- 2. Magnet Logic (BUCKETED)
        -- Only process if (orbId % BUCKET_COUNT) + 1 == currentIndex
        -- This ensures we process 1/10th of orbs per frame
        if (orbId % MAGNET_BUCKET_COUNT) + 1 == magnetBucketIndex then
            local closestPlayer = nil
            local closestDist = XPOrbConfig.MAGNET_RADIUS

            -- Optimization: Only check players?
            -- If we have 50 players, 100 orbs, checking 10 orbs * 50 players = 500 checks/frame. Acceptable.
            for _, player in ipairs(Players:GetPlayers()) do
                if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
                    local root = player.Character.HumanoidRootPart :: BasePart
                    local dist = (root.Position - orb.Position).Magnitude

                    if dist < closestDist then
                        closestDist = dist
                        closestPlayer = player
                    end
                end
            end

            if closestPlayer then
                 orb.MagnetTarget = closestPlayer.UserId
            else
                 orb.MagnetTarget = nil
            end
        end

        -- 3. Movement Integration
        -- If magnet target exists, move towards them
        if orb.MagnetTarget then
             local targetPlayer = Players:GetPlayerByUserId(orb.MagnetTarget)
             if targetPlayer and targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                 local root = targetPlayer.Character.HumanoidRootPart :: BasePart
                 local dist = (root.Position - orb.Position).Magnitude

                 local direction = (root.Position - orb.Position).Unit
                 local speedAlpha = 1 - math.clamp(dist / XPOrbConfig.MAGNET_RADIUS, 0, 1)
                 local currentSpeed = XPOrbConfig.MIN_MAGNET_SPEED + (XPOrbConfig.MAX_MAGNET_SPEED - XPOrbConfig.MIN_MAGNET_SPEED) * speedAlpha

                 -- Move
                 orb.Position = orb.Position + (direction * currentSpeed * dt)
             else
                 orb.MagnetTarget = nil
             end
        end
    end
end

--[[
    -------------------------------------------------------------------------
    EVENT HANDLERS
    -------------------------------------------------------------------------
]]

local function onCollectOrb(player: Player, orbId: number)
    local orb = activeOrbs[orbId]
    if not orb then return end -- Already collected

    local character = player.Character
    if not character then return end

    local root = character:FindFirstChild("HumanoidRootPart") :: BasePart
    if not root then return end

    local dist = (root.Position - orb.Position).Magnitude
    local maxDist = getCollectionRange(character)

    if orb.MagnetTarget == player.UserId then
        maxDist += XPOrbConfig.MAGNET_TOLERANCE
    end

    if dist > maxDist then
        -- Anti-cheat warning could go here
        return
    end

    -- Success
    ServiceBus.Get("AwardBiomass"):Fire(player, orb.XP)
    despawnOrb(orbId)
end

--[[
    -------------------------------------------------------------------------
    PUBLIC API
    -------------------------------------------------------------------------
]]

function XPOrbService.Start()
    print("--- Starting XPOrbService (Gold Standard) ---")

    -- Listeners
    ServiceBus.Get("SpawnXPOrbs").Event:Connect(function(position: Vector3, amount: number)
        XPOrbService.SpawnDrop(position, amount)
    end)

    CollectOrbRemote.OnServerEvent:Connect(onCollectOrb)

    -- Loops
    RunService.Heartbeat:Connect(updateOrbs)

    task.spawn(function()
        while true do
            spawnOrbInternal(getRandomSpawnPosition())
            task.wait(XPOrbConfig.SPAWN_INTERVAL)
        end
    end)
end

function XPOrbService.SpawnDrop(position: Vector3, totalXP: number)
    if totalXP <= 0 then return end

    local orbCount = math.clamp(math.ceil(totalXP / 100), 1, 10)
    local xpPerOrb = math.floor(totalXP / orbCount)

    for i = 1, orbCount do
        local offset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
        local targetX = position.X + offset.X
        local targetZ = position.Z + offset.Z

        -- Raycast floor
        local rayOrigin = Vector3.new(targetX, position.Y + 20, targetZ)
        local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0))
        local yPos = rayResult and rayResult.Position.Y or position.Y

        spawnOrbInternal(Vector3.new(targetX, yPos, targetZ), true, xpPerOrb)
    end
end

-- For Bots
function XPOrbService.CollectOrb(entity: Model, orbId: number): boolean
    local orb = activeOrbs[orbId]
    if not orb then return false end

    local root = entity:FindFirstChild("HumanoidRootPart") :: BasePart
    if not root then return false end

    local dist = (root.Position - orb.Position).Magnitude
    if dist > getCollectionRange(entity) then return false end

    ServiceBus.Get("AwardBiomass"):Fire(entity, orb.XP)
    despawnOrb(orbId)
    return true
end

function XPOrbService.GetNearestOrb(position: Vector3, maxRange: number?, excludeList: {[number]: boolean}?): {ID: number, Position: Vector3, XP: number}?
    local bestOrb = nil
    local bestDist = maxRange or math.huge

    for id, orb in pairs(activeOrbs) do
        if excludeList and excludeList[id] then continue end

        local dist = (orb.Position - position).Magnitude
        if dist < bestDist then
            bestDist = dist
            bestOrb = {
                ID = orb.Id,
                Position = orb.Position,
                XP = orb.XP
            }
        end
    end

    return bestOrb
end

return XPOrbService
