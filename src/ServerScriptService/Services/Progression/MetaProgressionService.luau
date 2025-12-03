--[[
    Module: MetaProgressionManager
    Description: Handles persistent "DNA" currency and permanent upgrades (Mutations).
                 Saves/Loads data using DataStoreService.
                 Handles Gacha mechanics.

    Dependencies:
    - ReplicatedStorage.GameLoop.MetaConfig

    Author: System
    Last Updated: 2025-01-20
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local MetaConfig = require(ReplicatedStorage.GameLoop.MetaConfig)

local MetaProgressionManager = {}

-- Constants
local DATA_STORE_KEY = "PlayerData_v1"
local Store = DataStoreService:GetDataStore(DATA_STORE_KEY)

-- State
-- PlayerMeta[Player] = { DNA = 0, Upgrades = { ["Dense Muscle"] = 0, ... } }
local PlayerMeta = {}

-- Draft State: { [Player] = { MutationName1, MutationName2, MutationName3 } }
local PlayerDrafts = {}

-- Pending Saves: { [Player] = true }
local pendingSaves = {}

-- Draft Purchases: { [Player] = { [Index] = true } }
local PlayerDraftPurchases = {}

-- Shop Rotation State
local ShopRotation = {
    Items = {}, -- { "MutationName1", "MutationName2", ... }
    NextRotationTime = 0,
    Seed = 0,
    RerollCounts = {} -- { [UserId] = count }
}
local ROTATION_INTERVAL = 600 -- 10 Minutes

-- Signals
local UpdateMetaEvent = Instance.new("RemoteEvent")
UpdateMetaEvent.Name = "UpdateMetaEvent"
UpdateMetaEvent.Parent = ReplicatedStorage

local MutationShopEvent = Instance.new("RemoteEvent")
MutationShopEvent.Name = "MutationShopEvent"
MutationShopEvent.Parent = ReplicatedStorage

local HarvestFunc = Instance.new("RemoteFunction")
HarvestFunc.Name = "Harvest"
-- HarvestFunc.Parent = ReplicatedStorage

-- Default Data
local function getDefaultData()
    return {
        DNA = 0,
        Upgrades = {} -- Dynamic now
    }
end

-- === Internal Logic ===

local function performSave(player)
    local data = PlayerMeta[player]
    if not data then return end

    local success, err = pcall(function()
        Store:SetAsync(player.UserId, data)
    end)

    if not success then
        warn("Failed to save data for " .. player.Name .. ": " .. tostring(err))
    end
end

local function scheduleSave(player)
    pendingSaves[player] = true
end

-- Weighted Random Selection
local function getRandomRarity(minRarity, randomGen)
    minRarity = minRarity or 1
    local totalWeight = 0
    local relevantWeights = {}
    
    for _, entry in ipairs(MetaConfig.RarityWeights) do
        if entry.Rarity >= minRarity then
            totalWeight = totalWeight + entry.Weight
            table.insert(relevantWeights, entry)
        end
    end

    local r = randomGen:NextNumber() * totalWeight
    local current = 0
    for _, entry in ipairs(relevantWeights) do
        current = current + entry.Weight
        if r <= current then
            return entry.Rarity
        end
    end
    return minRarity -- Default
end

local function getRandomMutationOfRarity(rarity, excludeList, randomGen)
    local candidates = {}
    for name, data in pairs(MetaConfig.Mutations) do
        if data.Rarity == rarity then
            -- Check if not excluded
            local excluded = false
            if excludeList then
                for _, ex in ipairs(excludeList) do
                    if ex == name then
                        excluded = true
                        break
                    end
                end
            end
            if not excluded then
                table.insert(candidates, name)
            end
        end
    end

    if #candidates == 0 then return nil end
    return candidates[randomGen:NextInteger(1, #candidates)]
end

-- Shop Rotation Logic
local function updateShopRotation()
    local now = os.time()
    if now < ShopRotation.NextRotationTime and #ShopRotation.Items > 0 then return end

    -- New Rotation
    ShopRotation.NextRotationTime = now + ROTATION_INTERVAL
    ShopRotation.NextRotationTime = now + ROTATION_INTERVAL
    ShopRotation.Seed = now
    ShopRotation.RerollCounts = {} -- Reset rerolls on rotation

    local rng = Random.new(ShopRotation.Seed)
    ShopRotation.Items = {}

    -- Generate 3 Flash Deals (Uncommon+)
    for i = 1, 3 do
        local rarity = getRandomRarity(2, rng)
        local mutation = getRandomMutationOfRarity(rarity, ShopRotation.Items, rng)
        if mutation then
            table.insert(ShopRotation.Items, mutation)
        end
    end

    print("🔄 Shop Rotated: ", table.concat(ShopRotation.Items, ", "))

    -- Notify all clients? (Or just let them pull on next open)
    -- MutationShopEvent:FireAllClients("UpdateTimer", ShopRotation.NextRotationTime)
end

-- === Public API ===

function MetaProgressionManager.Initialize(player)
    local success, data = pcall(function()
        return Store:GetAsync(player.UserId)
    end)

    if success and data then
        -- Merge with default to handle new fields
        local default = getDefaultData()
        for k, v in pairs(default) do
            if data[k] == nil then
                data[k] = v
            end
        end
        PlayerMeta[player] = data
    else
        PlayerMeta[player] = getDefaultData()
    end

    UpdateMetaEvent:FireClient(player, PlayerMeta[player])
end

function MetaProgressionManager.AddDNA(player, amount)
    local data = PlayerMeta[player]
    if not data then return end

    data.DNA = data.DNA + amount
    
    -- Fire UpdateMetaEvent (for MutationHUDController)
    UpdateMetaEvent:FireClient(player, data)
    
    -- Also fire UpdateMetaStats (for HUDController)
    task.spawn(function()
        local blaster = ReplicatedStorage:FindFirstChild("Blaster")
        if blaster then
            local remotes = blaster:FindFirstChild("Remotes")
            if remotes then
                local updateMetaRemote = remotes:FindFirstChild("UpdateMetaStats")
                if updateMetaRemote then
                    updateMetaRemote:FireClient(player, data.DNA, data.Upgrades, 0)
                end
            end
        end
    end)
end

-- Gacha: Start Draft
function MetaProgressionManager.RequestDraft(player)
    local data = PlayerMeta[player]
    if not data then return nil end

    -- Check cost
    -- Check cost (Initial roll is free/view only)
    -- if data.DNA < MetaConfig.ROLL_COST then
    --     return nil, "Not enough DNA"
    -- end

    updateShopRotation() -- Ensure valid rotation

    -- Generate 3 Cards from Rotation + Essentials
    -- Strategy:
    -- Slot 1 & 2: From Current Rotation (Flash Deals)
    -- Slot 3: Random Essential (Common/Uncommon) OR Rotation leftover

    local draft = {}
    local rng = Random.new(os.time() + player.UserId) -- Unique shuffle per player request

    -- 1. Try to fill from Shop Rotation (Flash Deals)
    for _, item in ipairs(ShopRotation.Items) do
        -- Verify Max Level
        local currentLvl = data.Upgrades[item] or 0
        local maxLvl = MetaConfig.Mutations[item].MaxLevel

        -- Check duplicate in draft
        local alreadyInDraft = false
        for _, d in ipairs(draft) do if d == item then alreadyInDraft = true break end end

        if currentLvl < maxLvl and not alreadyInDraft then
             table.insert(draft, item)
        end
        if #draft >= 3 then break end
    end

    -- 2. If slots remaining, fill with Random Essentials (Common/Uncommon)
    local attempts = 0
    while #draft < 3 and attempts < 50 do
        attempts = attempts + 1
        local rarity = getRandomRarity(2, rng) -- Exclude Commons (Min Rarity 2)
        local mutation = getRandomMutationOfRarity(rarity, draft, rng)

        if mutation then
            local currentLvl = data.Upgrades[mutation] or 0
            local maxLvl = MetaConfig.Mutations[mutation].MaxLevel
            if currentLvl < maxLvl then
                table.insert(draft, mutation)
            end
        end
    end

    -- 3. Fallback: If STILL empty (Maxed Out Everything), add a placeholder?
    -- Client handles empty drafts poorly.
    -- For now, if empty, we might return "DNA Cache" if we had one.
    -- Or we allow duplicates but convert them to DNA on purchase? (Requires Select logic change)

    -- Current fix: Just return what we have. Client loops through it.

    PlayerDrafts[player] = draft
    PlayerDraftPurchases[player] = {} -- Reset purchases for new draft

    -- Return draft AND the next rotation time for the timer
    -- Return draft AND the next rotation time for the timer
    local rerolls = ShopRotation.RerollCounts[player.UserId] or 0
    return draft, ShopRotation.NextRotationTime, rerolls
end

-- Gacha: Select
function MetaProgressionManager.SelectMutation(player, index)
    local draft = PlayerDrafts[player]
    if not draft or not draft[index] then return false end

    local data = PlayerMeta[player]
    if not data then return false, "No data" end

    -- Calculate Dynamic Cost
    local mutationName = draft[index]
    local currentLevel = data.Upgrades[mutationName] or 0
    local cost = MetaConfig.GetCost(mutationName, currentLevel)

    if data.DNA < cost then return false, "Not enough DNA" end

    -- Check if already purchased
    if PlayerDraftPurchases[player] and PlayerDraftPurchases[player][index] then
        return false, "Already purchased"
    end

    -- Deduct Cost
    data.DNA = data.DNA - cost
    data.Upgrades[mutationName] = currentLevel + 1

    -- Mark as Purchased
    if not PlayerDraftPurchases[player] then PlayerDraftPurchases[player] = {} end
    PlayerDraftPurchases[player][index] = true

    -- Save & Notify
    scheduleSave(player) -- Schedule save on purchase
    UpdateMetaEvent:FireClient(player, data)
    
    -- Also fire UpdateMetaStats for HUDController
    task.spawn(function()
        local blaster = ReplicatedStorage:FindFirstChild("Blaster")
        if blaster then
            local remotes = blaster:FindFirstChild("Remotes")
            if remotes then
                local updateMetaRemote = remotes:FindFirstChild("UpdateMetaStats")
                if updateMetaRemote then
                    updateMetaRemote:FireClient(player, data.DNA, data.Upgrades, 0)
                end
            end
        end
    end)

    print(player.Name .. " purchased mutation: " .. mutationName)

    return true
end

function MetaProgressionManager.PurchaseUpgrade(player, statName)
    local data = PlayerMeta[player]
    if not data then return false, "No data" end

    local upgradeConfig = MetaConfig.Upgrades[statName]
    if not upgradeConfig then return false, "Invalid upgrade" end

    local currentLevel = data.Upgrades[statName] or 0
    if currentLevel >= upgradeConfig.MaxLevel then
        return false, "Max level reached"
    end

    local cost = MetaConfig.GetCost(statName, currentLevel)
    if data.DNA < cost then
        return false, "Not enough DNA"
    end

    -- Deduct Cost
    data.DNA = data.DNA - cost

    -- Increment Level
    data.Upgrades[statName] = currentLevel + 1

    -- Save & Notify
    scheduleSave(player)
    UpdateMetaEvent:FireClient(player, data)
    
    -- Also fire UpdateMetaStats for HUDController
    task.spawn(function()
        local blaster = ReplicatedStorage:FindFirstChild("Blaster")
        if blaster then
            local remotes = blaster:FindFirstChild("Remotes")
            if remotes then
                local updateMetaRemote = remotes:FindFirstChild("UpdateMetaStats")
                if updateMetaRemote then
                    updateMetaRemote:FireClient(player, data.DNA, data.Upgrades, 0)
                end
            end
        end
    end)

    print(player.Name .. " purchased upgrade: " .. statName .. " (Lvl " .. (currentLevel + 1) .. ")")
    return true
end

function MetaProgressionManager.ResetUpgrades(player)
    local data = PlayerMeta[player]
    if not data then return false, "No data" end

    -- Reset Upgrades
    data.Upgrades = {}
    
    -- Reset DNA? (Optional, but "Reset Mutations" usually implies just mutations/upgrades)
    -- If we want a full wipe, we'd reset DNA too.
    -- User said "remove all mutations". Let's keep DNA for now or ask?
    -- "Remove all mutations" -> implies clearing the inventory.
    -- I'll just clear Upgrades.
    
    -- Save & Notify
    scheduleSave(player)
    UpdateMetaEvent:FireClient(player, data)
    
    -- Also fire UpdateMetaStats for HUDController
    task.spawn(function()
        local blaster = ReplicatedStorage:FindFirstChild("Blaster")
        if blaster then
            local remotes = blaster:FindFirstChild("Remotes")
            if remotes then
                local updateMetaRemote = remotes:FindFirstChild("UpdateMetaStats")
                if updateMetaRemote then
                    updateMetaRemote:FireClient(player, data.DNA, data.Upgrades, 0)
                end
            end
        end
    end)
    
    print(player.Name .. " reset all upgrades")
    return true
end

function MetaProgressionManager.GetStatValue(player, statName)
     local data = PlayerMeta[player]
    if not data then return 0 end

    local level = data.Upgrades[statName] or 0
    return MetaConfig.GetValue(statName, level)
end

function MetaProgressionManager.GetStatMultiplier(player, statName)
    local data = PlayerMeta[player]
    if not data then return 1 end

    local level = data.Upgrades[statName] or 0
    return MetaConfig.GetMultiplier(statName, level)
end

function MetaProgressionManager.GetDNA(player)
    return PlayerMeta[player] and PlayerMeta[player].DNA or 0
end

function MetaProgressionManager.Harvest(player)
    -- Validate Safe Zone
    if not player:GetAttribute("SafeZone") then
        return false, "Not in Safe Zone"
    end

    local biomass = player:GetAttribute("Biomass") or 0
    if biomass <= 0 then
        return false, "No Biomass to harvest"
    end

    -- Conversion Rate: 1 Biomass = 1 DNA
    local dnaGain = biomass

    -- Add DNA
    MetaProgressionManager.AddDNA(player, dnaGain)

    -- Reset Biomass
    player:SetAttribute("Biomass", 0)
    -- Also reset Level? Usually yes in this genre, but let's stick to Biomass for now.
    -- If we reset Biomass, we should probably reset Level to 1 to reflect size change.
    player:SetAttribute("Level", 1)
    player:SetAttribute("XP", 0) -- Reset partial XP too

    scheduleSave(player)
    
    return true, "Harvested " .. dnaGain .. " DNA"
end

function MetaProgressionManager.Start()
    -- Cleanup
    Players.PlayerRemoving:Connect(function(player)
        performSave(player) -- Immediate save on exit
        PlayerMeta[player] = nil
        PlayerDrafts[player] = nil
        pendingSaves[player] = nil
    end)

    -- Player Added
    Players.PlayerAdded:Connect(function(player)
        MetaProgressionManager.Initialize(player)
    end)
    
    -- Initialize existing players
    for _, player in ipairs(Players:GetPlayers()) do
        MetaProgressionManager.Initialize(player)
    end

    -- AutoSave Loop (Process Pending Saves)
    task.spawn(function()
        while true do
            task.wait(10) -- Check every 10 seconds
            for player, _ in pairs(pendingSaves) do
                performSave(player)
                pendingSaves[player] = nil
            end

            -- Check rotation
            updateShopRotation()
        end
    end)
    
    updateShopRotation() -- Initial
    print("MetaProgressionManager started")
end

function MetaProgressionManager.RequestReroll(player)
    local data = PlayerMeta[player]
    if not data then return nil end

    -- Check Reroll Limit
    local rerolls = ShopRotation.RerollCounts[player.UserId] or 0
    if rerolls >= 3 then
        return nil, "Max rerolls reached"
    end

    -- Check Cost
    if data.DNA < MetaConfig.REROLL_COST then
        return nil, "Not enough DNA"
    end

    -- Store previous draft to exclude from new roll
    local previousDraft = PlayerDrafts[player] or {}

    -- Deduct Cost
    data.DNA = data.DNA - MetaConfig.REROLL_COST
    
    -- Increment Count
    ShopRotation.RerollCounts[player.UserId] = rerolls + 1
    
    -- Clear current draft
    PlayerDrafts[player] = nil
    PlayerDraftPurchases[player] = {}
    
    -- Update Client DNA
    UpdateMetaEvent:FireClient(player, data)
    
    -- Generate new draft excluding previous mutations
    return MetaProgressionManager.RequestDraftWithExclusions(player, previousDraft)
end

-- Internal: Generate draft with exclusions (for rerolls)
function MetaProgressionManager.RequestDraftWithExclusions(player, excludeList)
    local data = PlayerMeta[player]
    if not data then return nil end

    updateShopRotation()

    local draft = {}
    local rng = Random.new(os.time() + player.UserId + (ShopRotation.RerollCounts[player.UserId] or 0) * 1000)
    
    -- Build combined exclusion list (previous draft items)
    local allExclusions = {}
    for _, item in ipairs(excludeList or {}) do
        allExclusions[item] = true
    end

    -- 1. Try to fill from Shop Rotation (Flash Deals) - but skip excluded items
    for _, item in ipairs(ShopRotation.Items) do
        if allExclusions[item] then continue end
        
        local currentLvl = data.Upgrades[item] or 0
        local maxLvl = MetaConfig.Mutations[item].MaxLevel

        local alreadyInDraft = false
        for _, d in ipairs(draft) do if d == item then alreadyInDraft = true break end end

        if currentLvl < maxLvl and not alreadyInDraft then
            table.insert(draft, item)
        end
        if #draft >= 3 then break end
    end

    -- 2. Fill remaining slots with random mutations (excluding previous draft)
    local attempts = 0
    while #draft < 3 and attempts < 50 do
        attempts = attempts + 1
        local rarity = getRandomRarity(2, rng)
        
        -- Build exclusion list for this pick: previous draft + current draft
        local pickExclusions = {}
        for _, d in ipairs(draft) do table.insert(pickExclusions, d) end
        for item, _ in pairs(allExclusions) do table.insert(pickExclusions, item) end
        
        local mutation = getRandomMutationOfRarity(rarity, pickExclusions, rng)

        if mutation then
            local currentLvl = data.Upgrades[mutation] or 0
            local maxLvl = MetaConfig.Mutations[mutation].MaxLevel
            if currentLvl < maxLvl then
                table.insert(draft, mutation)
            end
        end
    end

    PlayerDrafts[player] = draft
    PlayerDraftPurchases[player] = {}

    local rerolls = ShopRotation.RerollCounts[player.UserId] or 0
    return draft, ShopRotation.NextRotationTime, rerolls
end

-- Remote Functions
local DraftFunc = Instance.new("RemoteFunction")
DraftFunc.Name = "RequestDraft"
DraftFunc.Parent = ReplicatedStorage
DraftFunc.OnServerInvoke = function(player)
    return MetaProgressionManager.RequestDraft(player)
end

local RerollFunc = Instance.new("RemoteFunction")
RerollFunc.Name = "RequestReroll"
RerollFunc.Parent = ReplicatedStorage
RerollFunc.OnServerInvoke = function(player)
    return MetaProgressionManager.RequestReroll(player)
end

local SelectFunc = Instance.new("RemoteFunction")
SelectFunc.Name = "SelectMutation"
SelectFunc.Parent = ReplicatedStorage
SelectFunc.OnServerInvoke = function(player, index)
    return MetaProgressionManager.SelectMutation(player, index)
end

HarvestFunc.OnServerInvoke = function(player)
    return MetaProgressionManager.Harvest(player)
end

-- =====================================================
-- 🔗 BLASTER.REMOTES INTEGRATION
-- =====================================================
-- HUDController uses Blaster.Remotes.UpdateMetaStats and RequestMetaData
-- We need to hook these up to MetaProgressionManager

task.spawn(function()
    local blaster = ReplicatedStorage:WaitForChild("Blaster", 10)
    if blaster then
        local remotes = blaster:WaitForChild("Remotes", 10)
        if remotes then
            -- Parent HarvestFunc here so Client can find it
            HarvestFunc.Parent = remotes

            -- RequestMetaData: Client requests current DNA/mutations
            local requestMetaFunc = remotes:WaitForChild("RequestMetaData", 10)
            if requestMetaFunc then
                requestMetaFunc.OnServerInvoke = function(player)
                    local data = PlayerMeta[player]
                    if data then
                        -- Returns (dna, upgrades, biomass, nextRotationTime)
                        return data.DNA, data.Upgrades, 0, ShopRotation.NextRotationTime
                    end
                    return 0, {}, 0, 0
                end
                print("✅ MetaProgressionManager: RequestMetaData handler connected")
            end

            -- RerollFunc
            -- RerollFunc.Parent = remotes -- MOVED: Keep in ReplicatedStorage for MutationShopController
            
            -- PurchaseUpgrade: Client requests to buy an upgrade
            local purchaseUpgradeFunc = remotes:WaitForChild("PurchaseUpgrade", 10)
            if purchaseUpgradeFunc then
                purchaseUpgradeFunc.OnServerInvoke = function(player, statName)
                    return MetaProgressionManager.PurchaseUpgrade(player, statName)
                end
                print("✅ MetaProgressionManager: PurchaseUpgrade handler connected")
            end
        end
    end
end)

return MetaProgressionManager
