local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local KillEffectController = {}

-- Config
local CONFETTI_COLORS = {
	Color3.fromRGB(255, 0, 0),   -- Red
	Color3.fromRGB(0, 255, 0),   -- Green
	Color3.fromRGB(0, 0, 255),   -- Blue
	Color3.fromRGB(255, 255, 0), -- Yellow
	Color3.fromRGB(255, 0, 255), -- Magenta
}

local COIN_COLORS = {
	Color3.fromRGB(255, 215, 0),   -- Gold
	Color3.fromRGB(255, 200, 0),   -- Bright gold
	Color3.fromRGB(200, 150, 0),   -- Dark gold
}

local SMOKE_COLORS = {
	Color3.fromRGB(200, 200, 200), -- Light gray
	Color3.fromRGB(150, 150, 150), -- Medium gray
	Color3.fromRGB(100, 100, 100), -- Dark gray
}

-- Remotes (Initialized in Start)
local remotes
local playKillEffectRemote

-- Helper: Create Particle Emitter
local function createEmitter(parent, texture, colors, size, lifetime, speed, spread)
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = texture

	local colorKeypoints = {}
	for i, color in ipairs(colors) do
		local time = (i - 1) / (#colors - 1)
		table.insert(colorKeypoints, ColorSequenceKeypoint.new(time, color))
	end
	particles.Color = ColorSequence.new(colorKeypoints)

	particles.Size = size
	particles.Lifetime = lifetime
	particles.Rate = 0 -- Burst only
	particles.Speed = speed
	particles.SpreadAngle = spread
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = parent
	return particles
end

local function playConfetti(position)
	local part = Instance.new("Part")
	part.Name = "ConfettiEffect"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace

	local att = Instance.new("Attachment", part)

	local particles = createEmitter(
		att,
		"rbxasset://textures/particles/sparkles_main.dds",
		CONFETTI_COLORS,
		NumberSequence.new({NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 0)}),
		NumberRange.new(1, 2),
		NumberRange.new(10, 20),
		Vector2.new(45, 45)
	)

	particles:Emit(150)
	Debris:AddItem(part, 3)
end

local function playSmoke(position)
	local part = Instance.new("Part")
	part.Name = "SmokeEffect"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace

	local att = Instance.new("Attachment", part)

	local particles = createEmitter(
		att,
		"rbxasset://textures/particles/smoke_main.dds",
		SMOKE_COLORS,
		NumberSequence.new({NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(0.5, 5), NumberSequenceKeypoint.new(1, 8)}),
		NumberRange.new(1.5, 3),
		NumberRange.new(5, 15),
		Vector2.new(30, 30)
	)

	-- Smoke needs explicit transparency override
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})

	particles:Emit(120)
	Debris:AddItem(part, 4)
end

local function playCoins(position)
	local part = Instance.new("Part")
	part.Name = "CoinsEffect"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace

	local att = Instance.new("Attachment", part)

	local particles = createEmitter(
		att,
		"rbxasset://textures/particles/sparkles_main.dds",
		COIN_COLORS,
		NumberSequence.new({NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.5, 1.2), NumberSequenceKeypoint.new(1, 0)}),
		NumberRange.new(1, 2),
		NumberRange.new(8, 18),
		Vector2.new(50, 50)
	)

	particles:Emit(150)
	Debris:AddItem(part, 3)
end

local function onPlayKillEffect(effectType, position)
	if effectType == 1 then
		playConfetti(position)
	elseif effectType == 2 then
		playSmoke(position)
	else
		playCoins(position)
	end
end

function KillEffectController.Start()
	remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
	playKillEffectRemote = remotes:WaitForChild("PlayKillEffect", 30)

	if playKillEffectRemote then
		playKillEffectRemote.OnClientEvent:Connect(onPlayKillEffect)
		print("✅ KillEffectController: Listening for kill effects")
	else
		warn("❌ KillEffectController: PlayKillEffect remote missing!")
	end
end

return KillEffectController
