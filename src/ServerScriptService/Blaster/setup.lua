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
	
	-- Create Blaster Folder if missing
	local rsBlaster = ReplicatedStorage:FindFirstChild("Blaster")
	if not rsBlaster then
		rsBlaster = Instance.new("Folder")
		rsBlaster.Name = "Blaster"
		rsBlaster.Parent = ReplicatedStorage
		print("✅ Blaster Setup: Created ReplicatedStorage.Blaster folder")
	end

	local remotes = rsBlaster:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = rsBlaster
		print("✅ Blaster Setup: Created Remotes folder")
	end
	
	local function getOrCreateRemote(name, className)
		local remote = remotes:FindFirstChild(name)
		if not remote then
			remote = Instance.new(className)
			remote.Name = name
			remote.Parent = remotes
			print("✅ Blaster Setup: Created " .. name .. " " .. className)
		end
		return remote
	end

	-- Create ALL required remotes
	getOrCreateRemote("PlayerDamagedEntity", "RemoteEvent")
	getOrCreateRemote("ShowDeathSummary", "RemoteEvent")
	getOrCreateRemote("RequestRespawn", "RemoteEvent")
	getOrCreateRemote("UpdateMetaStats", "RemoteEvent")
	getOrCreateRemote("RequestMetaData", "RemoteFunction")
	getOrCreateRemote("PurchaseUpgrade", "RemoteFunction")
	getOrCreateRemote("OrbEvents", "RemoteEvent")
	getOrCreateRemote("CollectOrb", "RemoteEvent")
	getOrCreateRemote("Shoot", "RemoteEvent")
	getOrCreateRemote("Reload", "RemoteEvent")
	getOrCreateRemote("ReplicateShot", "RemoteEvent")
	getOrCreateRemote("DamageNumber", "RemoteEvent")
	
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
end

return BlasterSetup
