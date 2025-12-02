--[[
    Service: GiantFootstepService
    Description: Handles server-side replication of camera shake for giant footsteps.
    Dependencies: Networking (Remotes)

    Refactor: Moved from GameLoop/GiantFootstepHandler.server.luau
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GiantFootstepService = {}

-- Configuration
local SHAKE_RANGE = 100
local SHAKE_INTENSITY_BASE = 0.3
local GIANT_LEVEL_THRESHOLD = 21

-- Remotes
local giantFootstepRemote
local giantFootstepShakeRemote

function GiantFootstepService.Start()
    print("--- Starting GiantFootstepService ---")

    -- Remotes
    -- TODO: Move to Networking folder completely, but for now maintaining Blaster path for compatibility if clients use it
    local remotes = ReplicatedStorage:WaitForChild("Blaster", 10):WaitForChild("Remotes", 10)
    if not remotes then warn("GiantFootstepService: Missing remotes") return end

    giantFootstepRemote = remotes:WaitForChild("GiantFootstep")
    giantFootstepShakeRemote = remotes:WaitForChild("GiantFootstepShake")

    giantFootstepRemote.OnServerEvent:Connect(function(player: Player, footstepPosition: Vector3)
        if not player.Character then return end

        local level = player:GetAttribute("Level") or 1
        if level < GIANT_LEVEL_THRESHOLD then return end

        -- O(N) Broadcast
        for _, otherPlayer in ipairs(Players:GetPlayers()) do
            if otherPlayer == player then continue end
            if not otherPlayer.Character then continue end

            local root = otherPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not root then continue end

            local distance = (footstepPosition - root.Position).Magnitude
            if distance <= SHAKE_RANGE then
                local distanceFactor = 1 - (distance / SHAKE_RANGE)
                local shakeIntensity = SHAKE_INTENSITY_BASE * distanceFactor

                giantFootstepShakeRemote:FireClient(otherPlayer, shakeIntensity)
            end
        end
    end)
end

return GiantFootstepService
