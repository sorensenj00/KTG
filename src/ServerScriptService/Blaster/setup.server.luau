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

-- Load the Blaster Handler (Phase 4 refactor)
-- Load the Blaster Handler (Phase 4 refactor)
-- local handler = blasterFolder:FindFirstChild("Handler")
-- if handler then
-- 	require(handler)
-- 	print("✅ Blaster Setup: Handler loaded")
-- else
-- 	warn("❌ Blaster Setup: Handler.lua not found!")
-- end

return nil
