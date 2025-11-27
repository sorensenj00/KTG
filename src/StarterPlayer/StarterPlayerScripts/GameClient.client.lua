--[[
    Client-side bootstrapper
    Initializes all client controllers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Controllers = script.Parent:WaitForChild("Controllers")

local function safeRequire(moduleScript)
    local success, result = pcall(function()
        return require(moduleScript)
    end)
    if not success then
        warn("Failed to load controller: " .. moduleScript.Name)
        warn(result)
    end
end

-- Load Controllers
safeRequire(Controllers:WaitForChild("HUDController"))
safeRequire(Controllers:WaitForChild("MovementController"))
safeRequire(Controllers:WaitForChild("YeetCannonController"))
safeRequire(Controllers:WaitForChild("MutationShopController"))
-- safeRequire(Controllers:WaitForChild("CameraGrowthController")) -- This is a script, not a module, so it runs automatically?
-- Actually CameraGrowthController.client.luau is in StarterPlayerScripts, so it runs itself.
-- Wait, the list_files showed it as a separate file, not in Controllers.
-- "src/StarterPlayer/StarterPlayerScripts/CameraGrowthController.client.luau"
-- So we don't need to require it here if it's a LocalScript.
-- Checking file extension: .client.luau usually means LocalScript if Rojo syncs it as such.
-- If it's a ModuleScript in Controllers, we require it.
-- Let's check `list_files` again to be sure where I put MutationShopController.
-- I put it in `src/StarterPlayer/StarterPlayerScripts/Controllers/MutationShopController.client.luau`.
-- If it ends in .client.luau, Rojo might treat it as a LocalScript if not configured as Module.
-- Usually "Controllers" folder contains ModuleScripts.
-- I should ensure it returns a table with Start() and I call Start().

-- Re-verify CameraGrowthController
-- It was at `src/StarterPlayer/StarterPlayerScripts/CameraGrowthController.client.luau`.
-- This means it's a sibling of GameClient.client.lua.

-- My new file: `src/StarterPlayer/StarterPlayerScripts/Controllers/MutationShopController.client.luau`
-- If it is a module, I should require it.
-- Based on the code I wrote `local MutationShopController = {} ... return MutationShopController`, it is a Module.
-- The `.client.luau` extension is just a naming convention often used for client-side modules.

local MutationShop = require(Controllers:WaitForChild("MutationShopController"))
if MutationShop.Start then
    MutationShop.Start()
end
