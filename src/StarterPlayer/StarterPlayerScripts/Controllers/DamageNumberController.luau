--[[
    Controller: DamageNumberController
    Description: Manages 3D floating damage numbers using Part pooling and physics.
    Optimized for high fire-rate combat (Borderlands style).
    
    Dependencies:
    - Players, ReplicatedStorage, Workspace, RunService
    - ReplicatedStorage.Blaster.Remotes.DamageNumber
    
    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Configuration
local POOL_SIZE = 100
local PART_LIFETIME = 0.8 -- Seconds before cleanup
local FADE_DURATION = 0.2 -- Last 0.2s are for fading

-- Physics Config
local GRAVITY = Vector3.new(0, -30, 0) -- Custom gravity feel (if needed, but we use Roblox physics)
local INITIAL_UP_VELOCITY = 25
local CAMERA_BIAS_STRENGTH = 10
local SPREAD_STRENGTH = 10

-- Colors
local COLORS = {
	NORMAL = Color3.fromRGB(255, 255, 255),
	CRITICAL = Color3.fromRGB(255, 50, 50), -- Red
	KILL = Color3.fromRGB(255, 215, 0), -- Gold
	HEALING = Color3.fromRGB(0, 255, 100), -- Green
}

-- State
local damageNumberPool = {}
local activeDamageNumbers = {}
local damageNumberContainer -- Folder in Workspace

-- Remote
local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
local damageNumberRemote = remotes:WaitForChild("DamageNumber")

--------------------------------------------------------------------------------
-- Prefab Creation
--------------------------------------------------------------------------------
local function createDamageNumberPrefab(): Part
	local part = Instance.new("Part")
	part.Name = "PooledDamageNumber"
	part.Size = Vector3.new(0.5, 0.5, 0.5)
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Anchored = true -- Pooled parts are anchored
	part.Massless = true
	part.CastShadow = false

	-- BillboardGui was requested? No, user said "Floating Damage Number system".
	-- Actually, for 3D numbers that face camera, BillboardGui is easiest,
	-- but user requested "Physics" with "Trajectory".
	-- A Part with a BillboardGui works perfectly with physics.
	-- Or SurfaceGui on a Part that looksAt camera?
	-- BillboardGui is standard for damage numbers, but if we want them to tumble
	-- or have true 3D trajectory that feels "physic-y", we attach the UI to the part.
	-- Since the prompt asks for "Popcorn Physics (arcing projectiles)" and "Server must never create visual parts",
	-- we use a Part as the physical anchor.
	-- We will use a BillboardGui attached to the part so the text always faces camera,
	-- but the Part itself moves via physics.

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Display"
	billboard.Size = UDim2.fromScale(6, 3)
	billboard.Adornee = part
	billboard.AlwaysOnTop = true -- Borderlands style visibility
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "123"
	label.TextColor3 = COLORS.NORMAL
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.new(0,0,0)
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.Parent = billboard

	return part
end

--------------------------------------------------------------------------------
-- Pooling System
--------------------------------------------------------------------------------
local function initializePool()
	damageNumberContainer = Instance.new("Folder")
	damageNumberContainer.Name = "DamageNumbers_Client"
	damageNumberContainer.Parent = Workspace

	local storagePos = Vector3.new(0, -5000, 0)

	for i = 1, POOL_SIZE do
		local part = createDamageNumberPrefab()
		part.CFrame = CFrame.new(storagePos)
		part.Parent = damageNumberContainer
		table.insert(damageNumberPool, part)
	end
end

local function getPartFromPool(): Part?
	local part = table.remove(damageNumberPool)
	if not part then
		-- Optional: Dynamic expansion or just recycle oldest active (simpler to just return nil or create new temp)
		-- For safety, let's create a new temporary one if pool is empty
		part = createDamageNumberPrefab()
		part.Parent = damageNumberContainer
	end
	return part
end

local function returnPartToPool(part: Part)
	part.Anchored = true
	part.CFrame = CFrame.new(0, -5000, 0)
	part.AssemblyLinearVelocity = Vector3.zero
	part.AssemblyAngularVelocity = Vector3.zero

	-- Reset Visuals
	local bb = part:FindFirstChild("Display")
	if bb then
		local label = bb:FindFirstChild("Label")
		if label then
			label.TextTransparency = 0
			label.TextStrokeTransparency = 0
		end
	end

	table.insert(damageNumberPool, part)
end

--------------------------------------------------------------------------------
-- Logic
--------------------------------------------------------------------------------

local function spawnDamageNumber(amount: number, position: Vector3, isKill: boolean, xpAmount: number?)
	local part = getPartFromPool()
	if not part then return end

	local isHealing = amount < 0
	local absAmount = math.abs(amount)
	local isCrit = (absAmount > 50) and not isHealing -- Arbitrary crit threshold or flag passed?
	-- NOTE: The current remote doesn't pass "isCrit". We can infer it or just use simple logic.
	-- Prompt said: "Crit Hit: Red text, larger size, adds '!' to the text."
	-- I'll treat > 50 as high damage/crit for now, or just rely on visual flare for kills.

	-- Configure Text
	local bb = part:FindFirstChild("Display")
	local label = bb and bb:FindFirstChild("Label")
	local baseSize = UDim2.fromScale(8, 4) -- Default

	if label then
		local text = tostring(math.floor(absAmount))

		if isHealing then
			text = "+" .. text
			label.TextColor3 = COLORS.HEALING
			baseSize = UDim2.fromScale(6, 3)
		elseif isKill then
			text = "☠ " .. text .. "!" -- Kill flare
			label.TextColor3 = COLORS.KILL
			baseSize = UDim2.fromScale(12, 6) -- Big for kills
		elseif isCrit or absAmount >= 50 then
			text = text .. "!"
			label.TextColor3 = COLORS.CRITICAL
			baseSize = UDim2.fromScale(10, 5)
		else
			label.TextColor3 = COLORS.NORMAL
			baseSize = UDim2.fromScale(8, 4)
		end
		
		bb.Size = baseSize

		if xpAmount then
			text = text .. "\n+" .. xpAmount .. " XP"
		end

		label.Text = text
	end

	-- Physics Setup
	part.CFrame = CFrame.new(position)
	part.Anchored = false
	
	-- Calculate Velocity
	-- 1. Upwards pop
	local velocity = Vector3.new(0, INITIAL_UP_VELOCITY, 0)

	-- 2. Bias towards camera (so it doesn't get occluded by the enemy body)
	if camera then
		local camDir = (camera.CFrame.Position - position).Unit
		-- Flatten y so we don't shoot it too high/low based on look angle
		camDir = Vector3.new(camDir.X, 0, camDir.Z).Unit
		velocity = velocity + (camDir * CAMERA_BIAS_STRENGTH)
	end
	
	-- 3. Random Spread (Popcorn effect)
	local rng = Random.new()
	local spread = Vector3.new(
		rng:NextNumber(-1, 1),
		rng:NextNumber(0, 0.5), -- slight upward bias in spread
		rng:NextNumber(-1, 1)
	) * SPREAD_STRENGTH

	velocity = velocity + spread

	part.AssemblyLinearVelocity = velocity

	-- Add to active list for cleanup
	table.insert(activeDamageNumbers, {
		part = part,
		spawnTime = tick(),
		baseSize = baseSize
	})
end

local function update(dt)
	local now = tick()
	local camPos = camera.CFrame.Position

	-- Iterate backwards to safely remove
	for i = #activeDamageNumbers, 1, -1 do
		local data = activeDamageNumbers[i]
		local age = now - data.spawnTime

		if age >= PART_LIFETIME then
			-- Done
			returnPartToPool(data.part)
			table.remove(activeDamageNumbers, i)
		else
			-- Distance Scaling
			local dist = (data.part.Position - camPos).Magnitude
			-- Gentler scaling: Starts at 30 studs, adds +100% size every 100 studs. Max 3x.
			local scaleMultiplier = math.clamp(1 + (dist - 30) / 100, 1, 3)
			
			local bb = data.part:FindFirstChild("Display")
			if bb then
				bb.Size = UDim2.fromScale(
					data.baseSize.X.Scale * scaleMultiplier, 
					data.baseSize.Y.Scale * scaleMultiplier
				)
				
				-- Fading
				if age > (PART_LIFETIME - FADE_DURATION) then
					local fadeAlpha = (age - (PART_LIFETIME - FADE_DURATION)) / FADE_DURATION
					local label = bb:FindFirstChild("Label")
					if label then
						label.TextTransparency = fadeAlpha
						label.TextStrokeTransparency = fadeAlpha
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Controller
--------------------------------------------------------------------------------
local DamageNumberController = {}

function DamageNumberController.Start()
	initializePool()

	damageNumberRemote.OnClientEvent:Connect(function(damage, position, isKill, xpAmount)
		spawnDamageNumber(damage, position, isKill, xpAmount)
	end)

	RunService.Heartbeat:Connect(update)

	print("✅ DamageNumberController: Initialized (Physics/Pooling)")
end

return DamageNumberController
