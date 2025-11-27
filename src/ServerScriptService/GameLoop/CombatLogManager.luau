--[[
    Module: CombatLogManager
    Description: Handles player disconnections by creating a dummy character that persists for 10 seconds.
                 Ensures loot is dropped if the dummy is killed or expires.

    Dependencies:
    - ServerScriptService.GameLoop.MetaProgressionManager
    - ServerScriptService.GameLoop.ScalingEngine
    - ServerScriptService.Blaster.Events.Eliminated (to track kills on dummies)

    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- Lazy Dependencies
local MetaProgressionManager = nil
local function getMeta()
	if not MetaProgressionManager then
		pcall(function()
			MetaProgressionManager = require(ServerScriptService.GameLoop.MetaProgressionManager)
		end)
	end
	return MetaProgressionManager
end

local CombatLogManager = {}

-- Constants
local PERSISTENCE_DURATION = 10
local COMBAT_LOG_TAG = "CombatLogDummy"

-- Helper: Create Dummy from Character
local function createCombatLogDummy(player: Player, character: Model)
	local humanoid = character:FindFirstChild("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return nil
	end

	-- Check SafeZone attribute
	if player:GetAttribute("SafeZone") then
		return nil -- Don't persist if they are safe
	end

	-- Create Clone
	character.Archivable = true
	local dummy = character:Clone()
	dummy.Name = player.Name .. " (Disconnected)"

	-- Cleanup scripts and non-essential instances
	for _, child in ipairs(dummy:GetDescendants()) do
		if child:IsA("Script") or child:IsA("LocalScript") then
			child:Destroy()
		end
	end

	-- Add Tag
	CollectionService:AddTag(dummy, COMBAT_LOG_TAG)

	-- Store critical data on the Dummy itself as Attributes
	-- This allows other systems (like looting) to read it without the Player object
	local biomass = player:GetAttribute("Biomass") or 0
	local level = player:GetAttribute("Level") or 1

	dummy:SetAttribute("Biomass", biomass)
	dummy:SetAttribute("Level", level)
	dummy:SetAttribute("IsCombatLogDummy", true)
	dummy:SetAttribute("OriginalUserId", player.UserId)

	-- Position
	dummy.Parent = Workspace
	dummy:PivotTo(character:GetPivot())

	return dummy
end

-- Lazy Load XPOrbManager
local XPOrbManager = nil
local function getXPOrbManager()
	if not XPOrbManager then
		pcall(function()
			XPOrbManager = require(ServerScriptService.GameLoop.XPOrbManager)
		end)
	end
	return XPOrbManager
end

-- Handle Dummy Death
local function onDummyDied(dummy)
	print("💀 Combat Log Dummy Died:", dummy.Name)

	local biomass = dummy:GetAttribute("Biomass") or 0
	if biomass > 0 then
		local pos = dummy:GetPivot().Position

		-- Drop 100% of Biomass as Orbs (Same as regular death rules)
		local xpOrbMgr = getXPOrbManager()
		if xpOrbMgr then
			xpOrbMgr.SpawnDrop(pos, biomass)
		end

		print("💰 Dummy dropped", biomass, "Biomass")
	end
end

function CombatLogManager.Start()
	print("--- Starting CombatLogManager ---")

	Players.PlayerRemoving:Connect(function(player)
		local character = player.Character
		if character then
			local dummy = createCombatLogDummy(player, character)
			if dummy then
				print("🔌 Player", player.Name, "disconnected. Dummy spawned for", PERSISTENCE_DURATION, "s.")

				local humanoid = dummy:FindFirstChild("Humanoid")

				-- 1. Schedule Cleanup
				task.delay(PERSISTENCE_DURATION, function()
					if dummy and dummy.Parent then
						dummy:Destroy()
						print("🗑️ Combat Log Dummy expired:", dummy.Name)
					end
				end)

				-- 2. Listen for Death
				if humanoid then
					humanoid.Died:Connect(function()
						onDummyDied(dummy)
						-- Don't destroy immediately, let the ragdoll/death effect play?
						-- Usually roblox removes dead humanoids after a while.
						-- We can force cleanup after a shorter delay if dead.
						task.delay(3, function()
							if dummy and dummy.Parent then
								dummy:Destroy()
							end
						end)
					end)
				end
			end
		end
	end)
end

return CombatLogManager
