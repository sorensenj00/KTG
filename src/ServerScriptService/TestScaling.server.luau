local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MetaConfig = require(ReplicatedStorage.GameLoop.MetaConfig)
local MutationConfig = require(ReplicatedStorage.GameLoop.MutationConfig)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

print("----- SCALING ANALYSIS -----")

print("\n[SHOP COSTS]")
local upgrade = "Damage"
for _, level in ipairs({0, 1, 10, 20, 49}) do
    local cost = MetaConfig.GetCost(upgrade, level)
    print(string.format("Lvl %d -> %d: %s", level, level+1, tostring(cost)))
end

print("\n[MUTATION COSTS]")
for _, level in ipairs({1, 2, 3, 4}) do
    local cost = MutationConfig.GetUpgradeCost(1, level)
    print(string.format("Lvl %d -> %d: %s", level, level+1, tostring(cost)))
end

print("\n[KILL REWARDS]")
for _, level in ipairs({1, 10, 30, 50}) do
    local reward = ScalingConfig.GetXPReward(level)
    local req = ScalingConfig.GetXPRequired(level)
    local ratio = reward / req
    print(string.format("Victim Lvl %d: Reward %d | Req for next lvl: %d | %% of Level: %.2f%%", level, reward, req, ratio * 100))
end

print("\n[ORB REWARDS (Static)]")
-- Orbs are defined in XPOrbService, hard to require directly if it's a service script.
-- We'll just rely on the code analysis for Orbs.
