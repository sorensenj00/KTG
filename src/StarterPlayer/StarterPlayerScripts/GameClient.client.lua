--[[
    Client-side bootstrapper
    Initializes all client controllers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Controllers = script.Parent:WaitForChild("Controllers")

local function safeRequire(moduleScript)
    local success, result = pcall(function()
        local module = require(moduleScript)
        if module and typeof(module) == "table" and module.Start then
            module.Start()
        end
    end)
    if not success then
        warn("Failed to load controller: " .. moduleScript.Name)
        warn(result)
    end
end

-- Dynamically Load All Controllers in folder
-- This avoids hardcoding names and missing files
for _, child in ipairs(Controllers:GetChildren()) do
    if child:IsA("ModuleScript") then
        safeRequire(child)
    end
end
