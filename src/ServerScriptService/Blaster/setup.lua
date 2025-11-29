local BlasterSetup = {}

function BlasterSetup.Initialize()
	local blasterFolder = script.Parent
	local events = blasterFolder:FindFirstChild("Events")
	
	if not events then
		events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = blasterFolder
		print("✅ Blaster Setup: Created Events folder")
	else
		print("ℹ️ Blaster Setup: Used existing Events folder")
	end
	
	local eliminated = events:FindFirstChild("Eliminated")
	if not eliminated then
		eliminated = Instance.new("BindableEvent")
		eliminated.Name = "Eliminated"
		eliminated.Parent = events
		print("✅ Blaster Setup: Created Eliminated event")
	else
		print("ℹ️ Blaster Setup: Used existing Eliminated event")
	end
	
	-- Setup ReplicatedStorage Remotes
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local rsBlaster = ReplicatedStorage:WaitForChild("Blaster", 10)
	if rsBlaster then
		local remotes = rsBlaster:FindFirstChild("Remotes")
		if not remotes then
			remotes = Instance.new("Folder")
			remotes.Name = "Remotes"
			remotes.Parent = rsBlaster
			print("✅ Blaster Setup: Created Remotes folder")
		end
		
		-- PlayerDamagedEntity Remote
		local damageRemote = remotes:FindFirstChild("PlayerDamagedEntity")
		if not damageRemote then
			damageRemote = Instance.new("RemoteEvent")
			damageRemote.Name = "PlayerDamagedEntity"
			damageRemote.Parent = remotes
			print("✅ Blaster Setup: Created PlayerDamagedEntity remote")
		end
		
		-- ShowDeathSummary Remote (fires to client on death)
		local showDeathRemote = remotes:FindFirstChild("ShowDeathSummary")
		if not showDeathRemote then
			showDeathRemote = Instance.new("RemoteEvent")
			showDeathRemote.Name = "ShowDeathSummary"
			showDeathRemote.Parent = remotes
			print("✅ Blaster Setup: Created ShowDeathSummary remote")
		end
		
		-- RequestRespawn Remote (client fires to request respawn)
		local respawnRemote = remotes:FindFirstChild("RequestRespawn")
		if not respawnRemote then
			respawnRemote = Instance.new("RemoteEvent")
			respawnRemote.Name = "RequestRespawn"
			respawnRemote.Parent = remotes
			print("✅ Blaster Setup: Created RequestRespawn remote")
		end
		
		-- UpdateMetaStats Remote (server fires to update client HUD)
		local metaStatsRemote = remotes:FindFirstChild("UpdateMetaStats")
		if not metaStatsRemote then
			metaStatsRemote = Instance.new("RemoteEvent")
			metaStatsRemote.Name = "UpdateMetaStats"
			metaStatsRemote.Parent = remotes
			print("✅ Blaster Setup: Created UpdateMetaStats remote")
		end
		
		-- RequestMetaData Function (client requests current meta stats)
		local requestMetaFunc = remotes:FindFirstChild("RequestMetaData")
		if not requestMetaFunc then
			requestMetaFunc = Instance.new("RemoteFunction")
			requestMetaFunc.Name = "RequestMetaData"
			requestMetaFunc.Parent = remotes
			print("✅ Blaster Setup: Created RequestMetaData function")
		end

        -- PurchaseUpgrade Function (client requests purchase)
        local purchaseUpgradeFunc = remotes:FindFirstChild("PurchaseUpgrade")
        if not purchaseUpgradeFunc then
            purchaseUpgradeFunc = Instance.new("RemoteFunction")
            purchaseUpgradeFunc.Name = "PurchaseUpgrade"
            purchaseUpgradeFunc.Parent = remotes
            print("✅ Blaster Setup: Created PurchaseUpgrade function")
        end
		
		-- OrbEvents Remote (server → client orb spawn/despawn)
		local orbEvents = remotes:FindFirstChild("OrbEvents")
		if not orbEvents then
			orbEvents = Instance.new("RemoteEvent")
			orbEvents.Name = "OrbEvents"
			orbEvents.Parent = remotes
			print("✅ Blaster Setup: Created OrbEvents remote")
		end
		
		-- CollectOrb Remote (client → server orb collection)
		local collectOrb = remotes:FindFirstChild("CollectOrb")
		if not collectOrb then
			collectOrb = Instance.new("RemoteEvent")
			collectOrb.Name = "CollectOrb"
			collectOrb.Parent = remotes
			print("✅ Blaster Setup: Created CollectOrb remote")
		end
		
		-- Setup RequestRespawn handler
		local Players = game:GetService("Players")
		local respawnRemote = remotes:FindFirstChild("RequestRespawn")
		if respawnRemote then
			respawnRemote.OnServerEvent:Connect(function(player, skipDeath)
				print("🔄 RequestRespawn: Loading character for", player.Name, "skipDeath:", skipDeath or false)
				player:LoadCharacter()
			end)
			print("✅ Blaster Setup: RequestRespawn handler connected")
		end
		
	-- else
	-- 	warn("❌ Blaster Setup: Handler.lua not found!")
	end
end

return BlasterSetup
