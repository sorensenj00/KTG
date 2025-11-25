local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local KillfeedManager = {}

-- Helper to resolve entity (Player or Bot Model)
local function resolveEntity(argument)
	if not argument then
		return nil, false -- entity, isBot
	end

	if typeof(argument) ~= "Instance" then
		return nil, false
	end

	-- 1. Check for Player
	if argument:IsA("Player") then
		return argument, false
	elseif argument:IsA("Model") then
		if CollectionService:HasTag(argument, "BotAI") then
			return argument, true -- Return the Bot Model directly
		end
		return Players:GetPlayerFromCharacter(argument), false
	elseif argument:IsA("Humanoid") then
		local model = argument.Parent
		if CollectionService:HasTag(model, "BotAI") then
			return model, true
		end
		return Players:GetPlayerFromCharacter(model), false
	end
	return nil, false
end

-- Helper to get entity name and level
local function getEntityInfo(entity, isBot)
	if not entity then
		return "Unknown", 1
	end

	local name = entity.Name
	local level = 1

	level = entity:GetAttribute("Level") or 1

	return name, level
end

function KillfeedManager.Start()
	print("--- Starting KillfeedManager ---")

	-- Get RemoteEvent
	local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
	local killfeedRemote = remotes:WaitForChild("Killfeed")

	-- Listen to Blaster System
	task.spawn(function()
		local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
		if not blasterFolder then
			warn("KillfeedManager: Blaster folder not found")
			return
		end

		local eliminatedEvent = blasterFolder:WaitForChild("Events"):WaitForChild("Eliminated", 10)

		if eliminatedEvent then
			print("✅ KillfeedManager: Hooked into Blaster System!")

			-- Listen for Kills
			eliminatedEvent.Event:Connect(function(_gameState, killerArg, victimArg, _toolArg)
				-- Resolve killer and victim
				local killer, killerIsBot = resolveEntity(killerArg)
				local victim, victimIsBot = resolveEntity(victimArg)

				if killer and victim then
					-- Get names and levels
					local killerName, killerLevel = getEntityInfo(killer, killerIsBot)
					local victimName, victimLevel = getEntityInfo(victim, victimIsBot)

					-- Broadcast to all clients
					killfeedRemote:FireAllClients(
						killerName,
						killerLevel,
						killerIsBot,
						victimName,
						victimLevel,
						victimIsBot
					)

					print(
						string.format(
							"📢 Killfeed: %s (Lv%d, %s) → %s (Lv%d, %s)",
							killerName,
							killerLevel,
							killerIsBot and "Bot" or "Player",
							victimName,
							victimLevel,
							victimIsBot and "Bot" or "Player"
						)
					)
				end
			end)
		else
			warn("⚠️ KillfeedManager: EliminatedEvent not found")
		end
	end)
end

return KillfeedManager
