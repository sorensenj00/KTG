local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local YeetCannonManager = {}

-- === CONFIG VARIABLES ===
local DEFAULT_LAUNCH_FORCE = 400 -- Increased slightly for better feel
local DEFAULT_COOLDOWN = 1.5

-- === STATE ===
local playerStates = {}
local fireRemote = nil

-- === SETUP REMOTES ===
local function getRemote()
	local folder = ReplicatedStorage:FindFirstChild("Blaster")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Blaster"
		folder.Parent = ReplicatedStorage
	end
	local remotes = folder:FindFirstChild("Remotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "Remotes"
		remotes.Parent = folder
	end
	local remote = remotes:FindFirstChild("YeetCannonFire")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "YeetCannonFire"
		remote.Parent = remotes
	end
	return remote
end

local function findAllYeetCannons()
	local cannons = {}
	
	-- Iterate through ALL children of Workspace to find anything that looks like a YeetCannon
	-- This handles "YeetCannon", "YeetCannon (2)", "YeetCannon_2", etc.
	for _, child in ipairs(Workspace:GetChildren()) do
		if child:IsA("Model") and string.match(child.Name, "^YeetCannon") then
			table.insert(cannons, child)
		end
	end
	
	return cannons
end

local function createExplosion(muzzle)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://131961136"
	sound.Volume = 1.5
	sound.Parent = muzzle
	sound:Play()
	Debris:AddItem(sound, 5)

	local att = Instance.new("Attachment", muzzle)
	local pe = Instance.new("ParticleEmitter", att)
	pe.Texture = "rbxasset://textures/particles/explosion01_main.dds"
	pe.Rate = 0
	pe.Speed = NumberRange.new(20, 40)
	pe.SpreadAngle = Vector2.new(45, 45)
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe:Emit(50)

	task.delay(2, function()
		pe.Enabled = false
		Debris:AddItem(att, 1)
	end)
end

function YeetCannonManager.Start()
	print("--- Starting YeetCannonManager ---")
	fireRemote = getRemote()

	-- Connect the fire event ONCE
	fireRemote.OnServerEvent:Connect(function(player, aimDirection, clientOrigin)
		local char = player.Character
		if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChild("Humanoid")
		if not root or not hum then return end

		-- Verify player is sitting in a YeetCannon
		local seat = hum.SeatPart
		if not seat or not seat:IsDescendantOf(Workspace) or not seat:FindFirstAncestor("MapInteractables") then
			-- Not sitting or not in a YeetCannon (assuming all cannons are in MapInteractables as per Spawner)
			-- But let's check the tag or name to be sure it's a YeetCannon seat
			if not (seat and (seat.Name == "VehicleSeat" or seat.Name == "Seat")) then
				return
			end
			-- We can also check if the model has the "YeetCannon" tag
			local model = seat:FindFirstAncestorWhichIsA("Model")
			if not model or not model:HasTag("YeetCannon") then
				return
			end
		end

		local cannon = seat.Parent
		local muzzle = cannon:FindFirstChild("Muzzle") or seat

		-- Cooldown check
		local state = playerStates[player] or { lastFireTime = 0 }
		playerStates[player] = state
		if tick() - state.lastFireTime < DEFAULT_COOLDOWN then
			return
		end
		state.lastFireTime = tick()

		-- 1. DETERMINE VECTORS
		local launchDirection = muzzle.CFrame.LookVector
		if aimDirection and typeof(aimDirection) == "Vector3" then
			launchDirection = aimDirection.Unit
		end

		createExplosion(muzzle)

		-- 2. PREPARE PHYSICS
		seat.Disabled = true
		hum.Sit = false

		if root:CanSetNetworkOwnership() then
			root:SetNetworkOwner(nil)
		end

		task.wait()

		-- 3. CALCULATE LAUNCH POSITION
		local launchPos = muzzle.Position
		if clientOrigin and typeof(clientOrigin) == "Vector3" then
			if (clientOrigin - muzzle.Position).Magnitude < 50 then
				launchPos = clientOrigin
			end
		end

		launchPos = launchPos + (launchDirection * 10)

		-- 4. APPLY POSITION AND FORCE
		root.CFrame = CFrame.lookAt(launchPos, launchPos + launchDirection)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero

		root.AssemblyLinearVelocity = launchDirection * DEFAULT_LAUNCH_FORCE
		hum:ChangeState(Enum.HumanoidStateType.Physics)

		-- 5. CLEANUP
		task.delay(0.5, function()
			if root and root:CanSetNetworkOwnership() then
				root:SetNetworkOwner(player)
			end
			if hum then
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			end
		end)

		task.delay(1, function()
			if seat then
				seat.Disabled = false
			end
		end)
	end)

	print("✅ YeetCannonManager: Listening for fire events")
end

-- Initialize a single YeetCannon
function YeetCannonManager.Register(cannon)
	if not cannon then return end

	-- Anchor everything
	for _, part in ipairs(cannon:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	local seat = cannon:FindFirstChildOfClass("VehicleSeat") or cannon:FindFirstChildOfClass("Seat")
	local muzzle = cannon:FindFirstChild("Muzzle")

	if not muzzle and seat then
		muzzle = seat
	end
	if not seat then
		warn("YeetCannonManager: Missing Seat for", cannon.Name)
		return
	end

	seat.Transparency = 1
	seat.Disabled = false

	-- Prompt Setup
	local promptPart = cannon.PrimaryPart or muzzle or seat
	local prompt = promptPart:FindFirstChild("YeetCannonPrompt")

	if not prompt then
		prompt = Instance.new("ProximityPrompt", promptPart)
		prompt.Name = "YeetCannonPrompt"
		prompt.ActionText = "Enter YeetCannon"
		prompt.ObjectText = "Cannon"
		prompt.MaxActivationDistance = 50
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
	end
	prompt.Enabled = true

	prompt.Triggered:Connect(function(player)
		local char = player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		if hum and not seat.Occupant then
			seat:Sit(hum)
		end
	end)
end

return YeetCannonManager
