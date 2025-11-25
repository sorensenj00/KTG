local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local GoldenGunManager = require(script.Parent.GoldenGunManager)

local RandomEventManager = {}

-- Configuration
local EVENT_INTERVAL = 60 -- seconds
local GRAVITY_MIN = 0.2
local GRAVITY_MAX = 0.5
local GRAVITY_DURATION = 30 -- seconds
local GOLDEN_GUN_LIMIT = 3 -- max spawns per session

-- State tracking
local eventCount = 0
local goldenGunSpawns = 0
local isGravityEventActive = false
local originalGravity = Workspace.Gravity

-- Event types
local EVENT_TYPE_GRAVITY = "Gravity"
local EVENT_TYPE_GOLDEN_GUN = "GoldenGun"

-- Change gravity
local function changeGravity()
	if isGravityEventActive then
		return -- Already active
	end
	
	isGravityEventActive = true
	originalGravity = Workspace.Gravity
	
	-- Random gravity between 0.2 and 0.5
	local newGravity = math.random() * (GRAVITY_MAX - GRAVITY_MIN) + GRAVITY_MIN
	Workspace.Gravity = newGravity
	
	print("🌍 Gravity event: Gravity set to", newGravity, "for", GRAVITY_DURATION, "seconds")
	
	-- Broadcast to all players (could use RemoteEvent for UI notification)
	-- For now, just print
	
	-- Restore gravity after duration
	task.delay(GRAVITY_DURATION, function()
		Workspace.Gravity = originalGravity
		isGravityEventActive = false
		print("🌍 Gravity restored to", originalGravity)
	end)
end

-- Spawn Golden Gun
local function spawnGoldenGun()
	if goldenGunSpawns >= GOLDEN_GUN_LIMIT then
		-- Limit reached, don't spawn
		return
	end
	
	goldenGunSpawns = goldenGunSpawns + 1
	GoldenGunManager.Spawn()
	
	print("✨ Golden Gun event: Spawned Golden Gun (", goldenGunSpawns, "/", GOLDEN_GUN_LIMIT, ")")
end

-- Trigger random event
local function triggerRandomEvent()
	eventCount = eventCount + 1
	
	-- Randomly choose event type
	-- If Golden Gun limit reached, only do gravity
	local eventType
	if goldenGunSpawns >= GOLDEN_GUN_LIMIT then
		eventType = EVENT_TYPE_GRAVITY
	elseif isGravityEventActive then
		eventType = EVENT_TYPE_GOLDEN_GUN
	else
		-- Random choice
		if math.random() < 0.5 then
			eventType = EVENT_TYPE_GRAVITY
		else
			eventType = EVENT_TYPE_GOLDEN_GUN
		end
	end
	
	if eventType == EVENT_TYPE_GRAVITY then
		changeGravity()
	elseif eventType == EVENT_TYPE_GOLDEN_GUN then
		spawnGoldenGun()
	end
end

function RandomEventManager.Start()
	print("--- Starting RandomEventManager ---")
	
	-- Start event loop
	task.spawn(function()
		while true do
			task.wait(EVENT_INTERVAL)
			triggerRandomEvent()
		end
	end)
	
	print("✅ RandomEventManager: Events will trigger every", EVENT_INTERVAL, "seconds")
end

return RandomEventManager

