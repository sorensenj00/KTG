local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local VehicleSpawner = {}

-- Helper to ensure MapInteractables folder exists in Workspace
local function getMapInteractablesFolder()
	local folder = Workspace:FindFirstChild("MapInteractables")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "MapInteractables"
		folder.Parent = Workspace
	end
	return folder
end

function VehicleSpawner.Start()
	print("--- Starting VehicleSpawner ---")

	local VEHICLE_NAME = "Dune" -- Matches the name in ServerStorage
	local VEHICLE_COUNT = 3
	local RESPAWN_DELAY = 5

	local function getRandomSpawnPosition()
		-- Logic reused from BotSpawner/PlayerSpawner
		local baseplate = Workspace:FindFirstChild("Baseplate")
		local pos = Vector3.new(0, 5, 0)
		local size = Vector3.new(100, 1, 100)

		if baseplate then
			if baseplate:IsA("Model") then
				local cf, s = baseplate:GetBoundingBox()
				pos = cf.Position
				size = s
			elseif baseplate:IsA("BasePart") then
				pos = baseplate.Position
				size = baseplate.Size
			end
		end

		local halfSizeX = size.X / 2
		local halfSizeZ = size.Z / 2

		-- Random offset
		local x = math.random(-halfSizeX + 15, halfSizeX - 15)
		local z = math.random(-halfSizeZ + 15, halfSizeZ - 15)

		return Vector3.new(pos.X + x, pos.Y + 5, pos.Z + z)
	end

	local function spawnVehicle()
		print("Attempting to spawn Dune...")
		local vehicleTemplate = ServerStorage:FindFirstChild(VEHICLE_NAME)
		if not vehicleTemplate then
			warn("VehicleSpawner: Could not find '" .. VEHICLE_NAME .. "' in ServerStorage!")
			return
		else
			print("Found Dune template in ServerStorage.")
		end

		local vehicle = vehicleTemplate:Clone()
		vehicle.Name = VEHICLE_NAME

		-- Ensure it has the tag so VehicleController picks it up
		if not CollectionService:HasTag(vehicle, "Vehicle") then
			print("Adding 'Vehicle' tag to spawned car.")
			CollectionService:AddTag(vehicle, "Vehicle")
		end

		local spawnPos = getRandomSpawnPosition()
		vehicle:PivotTo(CFrame.new(spawnPos))
		vehicle.Parent = getMapInteractablesFolder()
		print("Dune spawned at: " .. tostring(spawnPos))

		-- Handle Respawn on Destroy
		vehicle.AncestryChanged:Connect(function(_, parent)
			if not parent then
				print("Vehicle destroyed, respawning in " .. RESPAWN_DELAY .. "s...")
				task.wait(RESPAWN_DELAY)
				spawnVehicle()
			end
		end)
	end

	-- Initial Spawn
	for i = 1, VEHICLE_COUNT do
		spawnVehicle()
		task.wait(1)
	end
end

return VehicleSpawner
