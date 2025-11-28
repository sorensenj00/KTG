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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
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

-- Signals
local UpdateMetaEvent = Instance.new("RemoteEvent")
UpdateMetaEvent.Name = "UpdateMetaEvent"
UpdateMetaEvent.Parent = ReplicatedStorage

local MutationShopEvent = Instance.new("RemoteEvent")
MutationShopEvent.Name = "MutationShopEvent"
MutationShopEvent.Parent = ReplicatedStorage

local HarvestFunc = Instance.new("RemoteFunction")
HarvestFunc.Name = "Harvest"
HarvestFunc.Parent = ReplicatedStorage

-- Default Data
local function getDefaultData()
    return {
        DNA = 0,
        Upgrades = {} -- Dynamic now
    }
end

-- === Internal Logic ===

local function savePlayer(player)
    local data = PlayerMeta[player]
    if not data then return end

    local success, err = pcall(function()
        Store:SetAsync(player.UserId, data)
    end)

    if not success then
        warn("Failed to save data for " .. player.Name .. ": " .. tostring(err))
    end
end

-- Weighted Random Selection
local function getRandomRarity()
    local totalWeight = 0
    for _, entry in ipairs(MetaConfig.RarityWeights) do
        totalWeight = totalWeight + entry.Weight
    end

    local r = math.random() * totalWeight
    local current = 0
    for _, entry in ipairs(MetaConfig.RarityWeights) do
        current = current + entry.Weight
        if r <= current then
            return entry.Rarity
        end
    end
    return 1 -- Default Common
end

local function getRandomMutationOfRarity(rarity, excludeList)
    local candidates = {}
    for name, data in pairs(MetaConfig.Mutations) do
        if data.Rarity == rarity then
            -- Check if not excluded
            local excluded = false
            if excludeList then
                for _, ex in ipairs(excludeList) do
                    if ex == name then excluded = true break end
                end
            end
            if not excluded then
                table.insert(candidates, name)
            end
        end
    end

    if #candidates == 0 then return nil end
    return candidates[math.random(1, #candidates)]
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
    UpdateMetaEvent:FireClient(player, data)
end

-- Gacha: Start Draft
function MetaProgressionManager.RequestDraft(player)
    local data = PlayerMeta[player]
    if not data then return nil end

    -- Check cost
    if data.DNA < MetaConfig.ROLL_COST then
        return nil, "Not enough DNA"
    end

    -- Generate 3 Cards
    local draft = {}
    local attempts = 0
    while #draft < 3 and attempts < 100 do
        attempts = attempts + 1
        local rarity = getRandomRarity()
        local mutationName = getRandomMutationOfRarity(rarity, draft)

        if mutationName then
            -- Verify Max Level
            local currentLvl = data.Upgrades[mutationName] or 0
            local maxLvl = MetaConfig.Mutations[mutationName].MaxLevel
            if currentLvl < maxLvl then
                table.insert(draft, mutationName)
            end
        end
    end

    if #draft < 3 then
         -- Fill with randoms if we ran out of unique valid options (unlikely unless maxed out)
         -- For now, just return what we have
    end

    PlayerDrafts[player] = draft
    return draft
end

-- Gacha: Select
function MetaProgressionManager.SelectMutation(player, index)
    local draft = PlayerDrafts[player]
    if not draft or not draft[index] then return false end

    local data = PlayerMeta[player]
    if data.DNA < MetaConfig.ROLL_COST then return false end

    -- Deduct Cost
    data.DNA = data.DNA - MetaConfig.ROLL_COST

    -- Award Mutation
    local mutationName = draft[index]
    local currentLevel = data.Upgrades[mutationName] or 0
    data.Upgrades[mutationName] = currentLevel + 1

    -- Clear Draft
    PlayerDrafts[player] = nil

    -- Save & Notify
    savePlayer(player) -- Save immediately on purchase
    UpdateMetaEvent:FireClient(player, data)

    print(player.Name .. " purchased mutation: " .. mutationName)

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

    savePlayer(player)
    
    return true, "Harvested " .. dnaGain .. " DNA"
end

function MetaProgressionManager.Start()
    -- Cleanup
    Players.PlayerRemoving:Connect(function(player)
        savePlayer(player)
        PlayerMeta[player] = nil
        PlayerDrafts[player] = nil
    end)

    -- AutoSave
    task.spawn(function()
        while true do
            task.wait(60)
            for player, _ in pairs(PlayerMeta) do
                savePlayer(player)
            end
        end
    end)
    
    print("MetaProgressionManager started")
end

-- Remote Functions
local DraftFunc = Instance.new("RemoteFunction")
DraftFunc.Name = "RequestDraft"
DraftFunc.Parent = ReplicatedStorage
DraftFunc.OnServerInvoke = function(player)
    return MetaProgressionManager.RequestDraft(player)
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

return MetaProgressionManager
