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
		local remotes = rsBlaster:WaitForChild("Remotes", 10)
		if remotes then
			local damageRemote = remotes:FindFirstChild("PlayerDamagedEntity")
			if not damageRemote then
				damageRemote = Instance.new("RemoteEvent")
				damageRemote.Name = "PlayerDamagedEntity"
				damageRemote.Parent = remotes
				print("✅ Blaster Setup: Created PlayerDamagedEntity remote")
			end
		end
	end
	
	-- Load the Blaster Handler (Phase 4 refactor)
	-- Load the Blaster Handler (Phase 4 refactor)
	-- local handler = blasterFolder:FindFirstChild("Handler")
	-- if handler then
	-- 	require(handler)
	-- 	print("✅ Blaster Setup: Handler loaded")
	-- else
	-- 	warn("❌ Blaster Setup: Handler.lua not found!")
	-- end
end

return BlasterSetup
