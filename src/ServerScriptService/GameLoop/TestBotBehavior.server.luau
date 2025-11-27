-- Test script to verify bot network ownership and pathfinding (Manual Verification Tool)
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Only run if enabled manually
local ENABLE_TEST = false
if not ENABLE_TEST then return end

task.wait(5) -- Wait for game to load

print("--- Starting Bot Behavior Test ---")

local function checkNetworkOwnership()
    for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
        local root = bot:FindFirstChild("HumanoidRootPart")
        if root then
            local owner = root:GetNetworkOwner()
            if owner then
                print("Bot " .. bot.Name .. " is owned by player: " .. owner.Name)
            else
                print("Bot " .. bot.Name .. " is owned by Server")
            end
        end
    end
end

-- Monitor every 5 seconds
task.spawn(function()
    while true do
        checkNetworkOwnership()
        task.wait(5)
    end
end)
