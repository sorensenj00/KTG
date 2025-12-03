local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
local ProgressionManager = require(ServerScriptService.Services.Progression.ProgressionService)

local MutationManager = {}

-- Reference to Eliminated event for kill credit
local eliminatedEvent = nil

-- Helper to deal damage with kill credit
local function dealDamageWithCredit(attacker, victimHumanoid, damage, _sourceName)
	if not victimHumanoid or victimHumanoid.Health <= 0 then return end
	
	local willKill = (victimHumanoid.Health - damage) <= 0
	
	if willKill and eliminatedEvent then
		-- Fire kill event - attacker can be Player or Character (for bots)
		local attackerEntity = attacker
		if typeof(attacker) == "Instance" and attacker:IsA("Model") then
			-- It's a character, try to get player
			attackerEntity = Players:GetPlayerFromCharacter(attacker) or attacker
		end
		eliminatedEvent:Fire(nil, attackerEntity, victimHumanoid.Parent, nil)
	end
	
	victimHumanoid:TakeDamage(damage)
end

-- =====================================================
-- ORBITALS SYSTEM
-- =====================================================
local ORBITAL_BASE_RADIUS = 5 -- Base orbit radius
local ORBITAL_DAMAGE = 15 -- Damage per hit
local ORBITAL_SPEED = 2 -- Rotations per second
local ORBITAL_HIT_COOLDOWN = 0.5 -- Seconds between damage ticks per target
local ORBITAL_COUNT = 2 -- Number of orbitals

-- State: { [Player] = { orbitals = {Part, Part}, hitCooldowns = {[Humanoid] = lastHitTime} } }
local orbitalState = {}

local function createOrbitalPart()
    local part = Instance.new("Part")
    part.Name = "Orbital"
    part.Shape = Enum.PartType.Ball
    part.Size = Vector3.new(2, 2, 2)
    part.Material = Enum.Material.Neon
    part.Color = Color3.fromRGB(255, 100, 50) -- Orange/Red
    part.CanCollide = false
    part.Anchored = true
    part.CastShadow = false
    
    -- Add spiky appearance with mesh
    local mesh = Instance.new("SpecialMesh")
    mesh.MeshType = Enum.MeshType.Sphere
    mesh.Scale = Vector3.new(1, 1, 1)
    mesh.Parent = part
    
    -- Add glow effect
    local light = Instance.new("PointLight")
    light.Brightness = 2
    light.Range = 8
    light.Color = Color3.fromRGB(255, 100, 50)
    light.Parent = part
    
    return part
end

local function updateOrbitals()
    local currentTime = tick()
    
    for player, state in pairs(orbitalState) do
        if not player.Parent then
            -- Player left, clean up
            for _, orbital in ipairs(state.orbitals) do
                orbital:Destroy()
            end
            orbitalState[player] = nil
            continue
        end
        
        local character = player.Character
        if not character then continue end
        
        local root = character:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        
        local scale = character:GetAttribute("Scale") or 1
        local radius = ORBITAL_BASE_RADIUS * scale
        local orbitalLevel = MetaProgressionManager.GetStatValue(player, "Orbitals") or 0
        
        if orbitalLevel <= 0 then
            -- Lost mutation, clean up
            for _, orbital in ipairs(state.orbitals) do
                orbital:Destroy()
            end
            orbitalState[player] = nil
            continue
        end
        
        -- Update orbital positions
        local numOrbitals = #state.orbitals
        for i, orbital in ipairs(state.orbitals) do
            local angle = (currentTime * ORBITAL_SPEED * math.pi * 2) + ((i - 1) / numOrbitals * math.pi * 2)
            local offsetX = math.cos(angle) * radius
            local offsetZ = math.sin(angle) * radius
            local targetPos = root.Position + Vector3.new(offsetX, 0, offsetZ)
            
            orbital.Position = targetPos
            orbital.Size = Vector3.new(2 * scale, 2 * scale, 2 * scale)
            
            -- Check for enemies in range
            local params = OverlapParams.new()
            params.FilterDescendantsInstances = {character, orbital}
            params.FilterType = Enum.RaycastFilterType.Exclude
            
            local touchingParts = workspace:GetPartBoundsInRadius(orbital.Position, orbital.Size.X, params)
            
			for _, part in ipairs(touchingParts) do
                local model = part.Parent
                local humanoid = model and model:FindFirstChild("Humanoid")
                
                if humanoid and humanoid.Health > 0 and model ~= character then
                    -- Check cooldown
                    local lastHit = state.hitCooldowns[humanoid] or 0
                    if currentTime - lastHit >= ORBITAL_HIT_COOLDOWN then
                        -- Deal damage (scaled with level) with kill credit
                        local damage = ORBITAL_DAMAGE * orbitalLevel
                        dealDamageWithCredit(player, humanoid, damage, "Orbitals")
                        state.hitCooldowns[humanoid] = currentTime
                    end
                end
            end
        end
        
        -- Clean up old cooldown entries
        for hum, _ in pairs(state.hitCooldowns) do
            if not hum.Parent then
                state.hitCooldowns[hum] = nil
            end
        end
    end
end

local function setupOrbitals(player)
    local orbitalLevel = MetaProgressionManager.GetStatValue(player, "Orbitals") or 0
    if orbitalLevel <= 0 then return end
    
    local character = player.Character
    if not character then return end
    
    -- Clean up existing orbitals
    if orbitalState[player] then
        for _, orbital in ipairs(orbitalState[player].orbitals) do
            orbital:Destroy()
        end
    end
    
    -- Create new orbitals
    local orbitals = {}
    for i = 1, ORBITAL_COUNT do
        local orbital = createOrbitalPart()
        orbital.Parent = workspace
        table.insert(orbitals, orbital)
    end
    
    orbitalState[player] = {
        orbitals = orbitals,
        hitCooldowns = {}
    }
end

-- =====================================================
-- EARTHQUAKE SYSTEM
-- =====================================================
local EARTHQUAKE_STUN_DURATION = 1 -- Seconds
local EARTHQUAKE_RADIUS_BASE = 15
local earthquakeState = {} -- { [Player] = { wasAirborne = false, lastY = 0 } }

local function applyStun(humanoid, duration)
    if not humanoid or humanoid.Health <= 0 then return end
    
    local originalSpeed = humanoid.WalkSpeed
    local originalJump = humanoid.JumpHeight
    
    humanoid.WalkSpeed = 0
    humanoid.JumpHeight = 0
    
    -- Visual effect - brief color flash
    local character = humanoid.Parent
    if character then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                local originalColor = part.Color
                part.Color = Color3.fromRGB(100, 100, 150)
                task.delay(duration, function()
                    if part and part.Parent then
                        part.Color = originalColor
                    end
                end)
            end
        end
    end
    
    task.delay(duration, function()
        if humanoid and humanoid.Parent then
            humanoid.WalkSpeed = originalSpeed
            humanoid.JumpHeight = originalJump
        end
    end)
end

local function checkEarthquake(player, character)
    local hasEarthquake = MetaProgressionManager.GetStatValue(player, "Earthquake")
    if not hasEarthquake or hasEarthquake == 0 then return end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root then return end
    
    -- Initialize state
    if not earthquakeState[player] then
        earthquakeState[player] = { wasAirborne = false, lastY = root.Position.Y }
    end
    
    local state = earthquakeState[player]
    local currentY = root.Position.Y
    local floorState = humanoid.FloorMaterial
    
    local isGrounded = floorState ~= Enum.Material.Air
    local wasAirborne = state.wasAirborne
    
    -- Detect landing
    if isGrounded and wasAirborne then
        -- Player just landed!
        local scale = character:GetAttribute("Scale") or 1
        local radius = EARTHQUAKE_RADIUS_BASE * scale
        
        -- Find nearby enemies
        local params = OverlapParams.new()
        params.FilterDescendantsInstances = {character}
        params.FilterType = Enum.RaycastFilterType.Exclude
        
        local parts = workspace:GetPartBoundsInRadius(root.Position, radius, params)
        local stunnedModels = {}
        
        for _, part in ipairs(parts) do
            local model = part.Parent
            if model and not stunnedModels[model] then
                local targetHum = model:FindFirstChild("Humanoid")
                if targetHum and targetHum.Health > 0 and model ~= character then
                    -- Only stun smaller enemies
                    local targetScale = model:GetAttribute("Scale") or 1
                    if targetScale < scale then
                        applyStun(targetHum, EARTHQUAKE_STUN_DURATION)
                        stunnedModels[model] = true
                    end
                end
            end
        end
        
        -- Visual shockwave effect
        local shockwave = Instance.new("Part")
        shockwave.Name = "EarthquakeShockwave"
        shockwave.Shape = Enum.PartType.Cylinder
        shockwave.Size = Vector3.new(0.5, radius * 2, radius * 2)
        shockwave.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, 0, math.rad(90))
        shockwave.Anchored = true
        shockwave.CanCollide = false
        shockwave.Material = Enum.Material.Plastic
        shockwave.Color = Color3.fromRGB(255, 200, 100)
        shockwave.Transparency = 0.8
        shockwave.Parent = workspace
        
        Debris:AddItem(shockwave, 0.3)
    end
    
    state.wasAirborne = not isGrounded
    state.lastY = currentY
end

-- =====================================================
-- TITAN'S REACH
-- =====================================================
local function updateTitansReach(player, character)
    local reachLevel = MetaProgressionManager.GetStatValue(player, "Titan's Reach") or 0
    -- Store as attribute for other systems to use (e.g., tool range, interaction range)
    character:SetAttribute("ReachMultiplier", 1 + reachLevel)
end

-- Helper to find nearby enemies
local function getNearbyEnemies(position, radius, ignoreChar)
    local enemies = {}
    for _, char in ipairs(CollectionService:GetTagged("Character")) do
        if char ~= ignoreChar and char.PrimaryPart then
            local dist = (char.PrimaryPart.Position - position).Magnitude
            if dist <= radius then
                table.insert(enemies, char)
            end
        end
    end
    -- Also check bots
    for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
        if bot ~= ignoreChar and bot.PrimaryPart then
             local dist = (bot.PrimaryPart.Position - position).Magnitude
            if dist <= radius then
                table.insert(enemies, bot)
            end
        end
    end
    return enemies
end

function MutationManager.OnDamage(victimChar, damageAmount, attackerPlayer)
    local player = Players:GetPlayerFromCharacter(victimChar)
    if not player then return end

    -- 1. Shedding (Speed Boost + Biomass Drop)
    -- Description: "Taking damage drops Biomass but gives a speed boost for 3s."
    local sheddingVal = MetaProgressionManager.GetStatValue(player, "Shedding")
    if sheddingVal and sheddingVal > 0 then
        -- Speed Boost (Handled by Attribute change, MovementController should listen or we modify WalkSpeed)
        -- Assuming MovementController listens to "SpeedMult" or similar, or we just modify Humanoid
        local hum = victimChar:FindFirstChild("Humanoid")
        if hum then
            local oldSpeed = hum.WalkSpeed
            hum.WalkSpeed = oldSpeed * (1 + sheddingVal) -- e.g. 1.2x
            
            -- Visual Effect?
            
            task.delay(3, function()
                if hum and hum.Parent then
                    hum.WalkSpeed = oldSpeed
                end
            end)
        end
        
        -- Drop Biomass (Optional, maybe skip for now or spawn orb)
    end
    
    -- 2. Thorns (Reflect Damage)
    -- Description: "Enemies take damage when they shoot you."
    if attackerPlayer and attackerPlayer.Character then
        local thornsDmg = MetaProgressionManager.GetStatValue(player, "Thorns")
        if thornsDmg and thornsDmg > 0 then
            local attackerHum = attackerPlayer.Character:FindFirstChild("Humanoid")
            if attackerHum then
                -- Credit kill to the victim (thorns reflect)
                dealDamageWithCredit(player, attackerHum, thornsDmg, "Thorns")
            end
        end
    end
end

function MutationManager.OnDeath(victimChar)
    local player = Players:GetPlayerFromCharacter(victimChar)
    if not player then return end
    
    -- Supernova
    local supernovaMult = MetaProgressionManager.GetStatValue(player, "Supernova")
    if supernovaMult and supernovaMult > 0 then
        local biomass = player:GetAttribute("Biomass") or 0
        local damage = biomass * supernovaMult
        local radius = 20 + (player:GetAttribute("Scale") or 1) * 5
        
        local root = victimChar:FindFirstChild("HumanoidRootPart")
        if root then
            local explosion = Instance.new("Explosion")
            explosion.Position = root.Position
            explosion.BlastRadius = radius
            explosion.BlastPressure = 0 -- Don't fling physics too hard
            explosion.Parent = workspace
            
            -- Custom damage logic to avoid friendly fire if needed, or just let Explosion.Hit handle it?
            -- Roblox Explosion.Hit is simple but indiscriminate.
            -- Let's use custom overlap for control.
            explosion.Hit:Connect(function(part, dist)
                local hum = part.Parent:FindFirstChild("Humanoid")
                if hum and hum.Parent ~= victimChar then
                    -- Credit kill to the player who died (posthumous kill)
                    dealDamageWithCredit(player, hum, damage, "Supernova")
                end
            end)
        end
    end
end

-- NOTE: Passive effects (Regeneration, Photosynthesis, Toxic Aura) are handled by PassiveService.luau
-- Do NOT duplicate them here to avoid double-application of effects.

-- =====================================================
-- START / INIT
-- =====================================================
function MutationManager.Start()
    print("--- Starting MutationManager ---")
    
    -- Get reference to Eliminated event for kill credit
    task.spawn(function()
        local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
        if blasterFolder then
            local eventsFolder = blasterFolder:WaitForChild("Events", 10)
            if eventsFolder then
                eliminatedEvent = eventsFolder:WaitForChild("Eliminated", 10)
                if eliminatedEvent then
                    print("✅ MutationManager: Connected to Eliminated event for kill credit")
                end
            end
        end
    end)
    
    -- Setup orbitals for existing players
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            setupOrbitals(player)
        end
    end
    
    -- Setup orbitals when player spawns
    Players.PlayerAdded:Connect(function(player)
        player.CharacterAdded:Connect(function(character)
            task.wait(0.5) -- Wait for character to be fully loaded
            setupOrbitals(player)
        end)
    end)
    
    -- Handle existing players' character spawns
    for _, player in ipairs(Players:GetPlayers()) do
        player.CharacterAdded:Connect(function(character)
            task.wait(0.5)
            setupOrbitals(player)
        end)
    end
    
    -- Cleanup on player leaving
    Players.PlayerRemoving:Connect(function(player)
        if orbitalState[player] then
            for _, orbital in ipairs(orbitalState[player].orbitals) do
                orbital:Destroy()
            end
            orbitalState[player] = nil
        end
        earthquakeState[player] = nil
    end)
    
    -- Main update loop
    RunService.Heartbeat:Connect(function(dt)
        -- Update orbitals
        updateOrbitals()
        
        -- Check earthquake and update reach for all players
        for _, player in ipairs(Players:GetPlayers()) do
            local character = player.Character
            if character and character:FindFirstChild("Humanoid") then
                checkEarthquake(player, character)
                updateTitansReach(player, character)
            end
        end
    end)
    
    print("✅ MutationManager: Active mutations - Orbitals, Earthquake, Titan's Reach")
end

return MutationManager
