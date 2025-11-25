local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService") -- Added Service

local YeetCannonSpawner = {}

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

function YeetCannonSpawner.Start()
	print("--- Starting YeetCannonSpawner ---")

	-- Helper to get baseplate info
	local function getBaseplateInfo()
		local baseplate = Workspace:FindFirstChild("Baseplate")
		local centerX, centerZ = 0, 0
		local sizeX, sizeZ = 100, 100 -- Default fallback

		if baseplate then
			if baseplate:IsA("Model") then
				local cf, s = baseplate:GetBoundingBox()
				centerX, centerZ = cf.Position.X, cf.Position.Z
				sizeX, sizeZ = s.X, s.Z
			elseif baseplate:IsA("BasePart") then
				centerX, centerZ = baseplate.Position.X, baseplate.Position.Z
				sizeX, sizeZ = baseplate.Size.X, baseplate.Size.Z
			end
		end
		return centerX, centerZ, sizeX, sizeZ
	end

	-- Helper to get random position avoiding center
	local function getRandomPositionAvoidingCenter()
		local centerX, centerZ, sizeX, sizeZ = getBaseplateInfo()
		local halfSizeX = sizeX / 2
		local halfSizeZ = sizeZ / 2

		-- Define center exclusion zone (30% of map size)
		local exclusionRadius = math.min(sizeX, sizeZ) * 0.15

		local attempts = 0
		local maxAttempts = 50
		local targetX, targetZ

		repeat
			-- Random position within baseplate bounds (with margin)
			targetX = centerX + math.random(-halfSizeX + 20, halfSizeX - 20)
			targetZ = centerZ + math.random(-halfSizeZ + 20, halfSizeZ - 20)

			-- Check distance from center
			local distFromCenter = math.sqrt((targetX - centerX) ^ 2 + (targetZ - centerZ) ^ 2)
			attempts = attempts + 1
		until distFromCenter > exclusionRadius or attempts >= maxAttempts

		return targetX, targetZ
	end

	local function spawnYeetCannon(targetX, targetZ, cannonNumber)
		local cannonTemplate = ServerStorage:FindFirstChild("YeetCannon")
		if not cannonTemplate then
			warn("YeetCannonSpawner: 'YeetCannon' not found in ServerStorage!")
			return
		end

		local cannon = cannonTemplate:Clone()
		-- First cannon keeps original name for compatibility, others get numbered
		cannon.Name = (cannonNumber == 1) and "YeetCannon" or ("YeetCannon_" .. cannonNumber)

		-- 1. CRITICAL: Set PrimaryPart to the Seat
		-- This ensures PivotTo and MoveTo work based on the player's sitting position, not a random part
		local seat = cannon:FindFirstChildOfClass("VehicleSeat") or cannon:FindFirstChildOfClass("Seat")
		if seat then
			cannon.PrimaryPart = seat
			seat.Disabled = false -- Ensure seat is active
		else
			warn("YeetCannonSpawner: Warning - Spawned cannon has no Seat!")
		end

		-- 2. Anchor all parts
		for _, descendant in ipairs(cannon:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = true
			end
		end

		-- 3. Add CollectionService Tag
		CollectionService:AddTag(cannon, "YeetCannon")

		-- 4. Use provided position (or get random if not provided)
		if not targetX or not targetZ then
			targetX, targetZ = getRandomPositionAvoidingCenter()
		end

		-- 5. Parent to MapInteractables folder so we can raycast against the world
		cannon.Parent = getMapInteractablesFolder()

		-- 6. Use Raycasting to find the EXACT floor height
		local rayOrigin = Vector3.new(targetX, 50, targetZ)
		local rayDirection = Vector3.new(0, -100, 0)

		local rayParams = RaycastParams.new()
		rayParams.FilterDescendantsInstances = { cannon } -- Don't let the cannon hit itself
		rayParams.FilterType = Enum.RaycastFilterType.Exclude

		local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)

		-- Get the original rotation from the template
		local templateRotation = cannonTemplate:GetPivot().Rotation

		if rayResult then
			-- FOUND FLOOR: Position cannon exactly on the hit point

			-- MoveTo automatically calculates the bounding box bottom and places it ON the vector provided.
			-- Since we set PrimaryPart to Seat, we might need to adjust slightly if the seat is high up,
			-- but usually MoveTo handles the model bounds correctly.
			cannon:MoveTo(rayResult.Position)

			-- Re-apply rotation (MoveTo resets orientation to 0,0,0 usually)
			local currentPos = cannon:GetPivot().Position
			cannon:PivotTo(CFrame.new(currentPos) * templateRotation)

			print("YeetCannonSpawner: Raycast found floor. Spawned at", rayResult.Position)
		else
			-- FALLBACK: If void/no floor, simply spawn at default coordinates
			local defaultPos = Vector3.new(targetX, 5, targetZ)
			cannon:PivotTo(CFrame.new(defaultPos) * templateRotation)
			print("YeetCannonSpawner: No floor found. Spawned at default", defaultPos)
		end
	end

	-- Spawn 3 cannons at random positions (never in the middle)
	for i = 1, 3 do
		local targetX, targetZ = getRandomPositionAvoidingCenter()
		spawnYeetCannon(targetX, targetZ, i)
	end
end

return YeetCannonSpawner
