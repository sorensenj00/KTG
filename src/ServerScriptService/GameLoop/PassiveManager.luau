--[[
    Module: PassiveManager
    Description: Handles passive/idle mechanics like Regeneration, Photosynthesis, and Toxic Aura.

    Dependencies:
    - ServerScriptService.GameLoop.MetaProgressionManager
    - ServerScriptService.GameLoop.ProgressionManager
    - ReplicatedStorage.GameLoop.MetaConfig

    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local MetaProgressionManager = require(ServerScriptService.GameLoop.MetaProgressionManager)
local ProgressionManager = require(ServerScriptService.GameLoop.ProgressionManager)
local MetaConfig = require(ReplicatedStorage.GameLoop.MetaConfig)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local PassiveManager = {}

-- Constants
local TICK_RATE = 1.0 -- Run passives every 1 second
local SCAVENGER_UPDATE_RATE = 0.2 -- Run scavenger every 0.2 seconds
local AURA_RANGE_BASE = 15
local SCAVENGER_RANGE_BASE = 10
local SCAVENGER_SPEED = 15 -- Studs per second attraction

-- State
local scavengerAccumulator = 0

-- Helper: Get Nearby Enemies
local function getNearbyEnemies(centerPos, range, ignorePlayer)
    local params = OverlapParams.new()
    params.FilterDescendantsInstances = {ignorePlayer.Character}
    params.FilterType = Enum.RaycastFilterType.Exclude

    local parts = workspace:GetPartBoundsInRadius(centerPos, range, params)
    local enemiesHit = {}

    for _, part in ipairs(parts) do
        local model = part.Parent
        if model and model:FindFirstChild("Humanoid") and model ~= ignorePlayer.Character then
            -- Avoid double hitting the same model
            if not enemiesHit[model] then
                enemiesHit[model] = true
            end
        end
    end

    return enemiesHit
end

-- Helper: Apply Toxic Aura Damage
local function applyToxicAura(player, character, level)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local dps = MetaConfig.GetValue("ToxicAura", level)
    if dps <= 0 then return end

    -- Visuals (Optional: Client side would be better, but simple particle here for now or just logic)
    -- Ideally, we fire a remote to show the aura effect on clients.

    local enemies = getNearbyEnemies(root.Position, AURA_RANGE_BASE + (level * 1), player)

    for enemyModel, _ in pairs(enemies) do
        local humanoid = enemyModel:FindFirstChild("Humanoid")
        if humanoid and humanoid.Health > 0 then
            humanoid:TakeDamage(dps)
        end
    end
end

-- Helper: Scavenger / Magnetism Logic
local function updateScavenger(player, character, rangeBoost, dt)
    local root = character:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local range = SCAVENGER_RANGE_BASE + rangeBoost

    -- Find Orbs
    local orbFolder = workspace:FindFirstChild("Orbs")
    if not orbFolder then return end

    -- Optimization: Only check if Orbs exist
    if #orbFolder:GetChildren() == 0 then return end

    local params = OverlapParams.new()
    params.FilterDescendantsInstances = {orbFolder}
    params.FilterType = Enum.RaycastFilterType.Include

    local nearbyOrbs = workspace:GetPartBoundsInRadius(root.Position, range, params)

    -- We track processed orbs to avoid moving the hitbox AND the orb part twice
    local processedOrbs = {}

    for _, part in ipairs(nearbyOrbs) do
        local orb = nil
        if part.Name == "XPOrb" then
            orb = part
        elseif part.Name == "Hitbox" then
            orb = part.Parent
        end

        if orb and orb:IsA("BasePart") and not processedOrbs[orb] then
            processedOrbs[orb] = true

            -- Pull orb towards player using smooth CFrame interpolation
            local currentPos = orb.Position
            local targetPos = root.Position
            local dir = (targetPos - currentPos).Unit

            -- Move based on speed * dt (but slightly faster to feel 'magnetic')
            local moveStep = dir * (SCAVENGER_SPEED * 1.5 * dt)

            -- Don't overshoot
            local dist = (targetPos - currentPos).Magnitude
            if moveStep.Magnitude >= dist then
                orb.Position = targetPos
            else
                orb.Position = currentPos + moveStep
            end

            -- Ensure touch triggers if very close
            if dist < 4 then
                -- Teleport into player to force touch event
                orb.Position = root.Position
            end
        end
    end
end


-- Main Loop Function (Slow Tick)
local function onTick()
    for _, player in ipairs(Players:GetPlayers()) do
        local character = player.Character
        if character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0 then

            -- 1. Regeneration
            local regenLevel = MetaProgressionManager.GetStatValue(player, "Regeneration")
            if regenLevel > 0 then
                local hum = character.Humanoid
                if hum.Health < hum.MaxHealth then
                    hum.Health = math.min(hum.Health + regenLevel, hum.MaxHealth)
                end
            end

            -- 2. Photosynthesis (Passive Biomass)
            local photoLevel = MetaProgressionManager.GetStatValue(player, "Photosynthesis")
            if photoLevel > 0 then
                ProgressionManager.AddBiomass(player, photoLevel)
            end

            -- 3. Toxic Aura
            local auraLevel = MetaProgressionManager.GetStatValue(player, "ToxicAura")
            if auraLevel > 0 then
                applyToxicAura(player, character, auraLevel)
            end

        end
    end
end

-- Scavenger Loop (Fast Heartbeat)
local function onHeartbeat(dt)
    -- Accumulator logic for reliable timing
    scavengerAccumulator = scavengerAccumulator + dt

    if scavengerAccumulator >= SCAVENGER_UPDATE_RATE then
        -- Process one step
        -- We pass 'scavengerAccumulator' as the delta time for the movement to keep it smooth relative to the update rate
        -- actually, it's better to run it every frame for smooth movement, but we can throttle the QUERY.
        -- But since we are moving Parts directly (server-side), 5-10Hz is fine.

        local stepDt = scavengerAccumulator
        scavengerAccumulator = 0

        for _, player in ipairs(Players:GetPlayers()) do
             local character = player.Character
             if character then
                 local magRange = MetaProgressionManager.GetStatValue(player, "Magnetism")
                 if magRange > 0 then
                     updateScavenger(player, character, magRange, stepDt)
                 end
             end
        end
    end
end


function PassiveManager.Start()
    print("--- Starting PassiveManager ---")

    -- Start the Tick Loop
    task.spawn(function()
        while true do
            onTick()
            task.wait(TICK_RATE)
        end
    end)

    -- Start Scavenger Loop
    RunService.Heartbeat:Connect(onHeartbeat)
end

return PassiveManager
