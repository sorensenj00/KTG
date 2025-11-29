local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

local MetaProgressionManager = require(ServerScriptService.Services.Progression.MetaProgressionService)
local ProgressionManager = require(ServerScriptService.Services.Progression.ProgressionService)

local MutationManager = {}

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
                attackerHum:TakeDamage(thornsDmg)
                -- Visual feedback?
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
                    hum:TakeDamage(damage)
                end
            end)
        end
    end
end

-- Passive Loop
task.spawn(function()
    while true do
        task.wait(1)
        for _, player in ipairs(Players:GetPlayers()) do
            if player.Character and player.Character:FindFirstChild("Humanoid") then
                local hum = player.Character.Humanoid
                if hum.Health > 0 then
                    -- Regeneration
                    local regen = MetaProgressionManager.GetStatValue(player, "Regeneration")
                    if regen and regen > 0 then
                        hum.Health = math.min(hum.Health + regen, hum.MaxHealth)
                    end
                    
                    -- Photosynthesis
                    local photo = MetaProgressionManager.GetStatValue(player, "Photosynthesis")
                    if photo and photo > 0 then
                        ProgressionManager.AddBiomass(player, photo)
                    end
                    
                    -- Toxic Aura
                    local toxicDmg = MetaProgressionManager.GetStatValue(player, "Toxic Aura")
                    if toxicDmg and toxicDmg > 0 then
                        local root = player.Character:FindFirstChild("HumanoidRootPart")
                        if root then
                            local enemies = getNearbyEnemies(root.Position, 15, player.Character)
                            for _, enemy in ipairs(enemies) do
                                local eHum = enemy:FindFirstChild("Humanoid")
                                if eHum then
                                    eHum:TakeDamage(toxicDmg)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

return MutationManager
