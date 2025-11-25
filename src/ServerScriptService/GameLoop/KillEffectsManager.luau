local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local KillEffectsManager = {}

-- Meta-progression (optional, may not be loaded yet)
local MetaProgressionManager = nil
local function getMeta()
	if not MetaProgressionManager then
		pcall(function()
			MetaProgressionManager = require(game:GetService("ServerScriptService").GameLoop.MetaProgressionManager)
		end)
	end
	return MetaProgressionManager
end

-- Team checking utility (similar to canPlayerDamageHumanoid)
local function canPlayerDamageHumanoid(attacker: Player | Model, taggedHumanoid: Humanoid): boolean
	if taggedHumanoid.Health <= 0 then
		return false
	end

	local taggedCharacter = taggedHumanoid.Parent
	local taggedPlayer = Players:GetPlayerFromCharacter(taggedCharacter)
	
	-- Attacker is a Bot (Model)
	if attacker:IsA("Model") then
		if taggedCharacter == attacker then
			return false
		end
		return true -- FFA for bots
	end

	-- Attacker is a Player
	if not attacker:IsA("Player") then
		return false
	end

	-- If the player tagged a non-player humanoid (e.g. Bot) then allow damage
	if not taggedPlayer then
		return true
	end

	if attacker.Neutral or taggedPlayer.Neutral then
		return true
	else
		return attacker.Team ~= taggedPlayer.Team
	end
end

-- Get the Eliminated Event
local eliminatedEvent
task.spawn(function()
	local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
	if blasterFolder then
		local eventsFolder = blasterFolder:WaitForChild("Events", 10)
		if eventsFolder then
			eliminatedEvent = eventsFolder:WaitForChild("Eliminated", 10)
			if eliminatedEvent then
				print("✅ KillEffectsManager: Found Eliminated Event")
			else
				warn("⚠️ KillEffectsManager: Eliminated Event not found after 10 seconds!")
			end
		else
			warn("⚠️ KillEffectsManager: Events folder not found after 10 seconds!")
		end
	else
		warn("⚠️ KillEffectsManager: Blaster folder not found after 10 seconds!")
	end
end)

-- Create confetti particle effect
local function createConfettiEffect(position)
	local part = Instance.new("Part")
	part.Name = "ConfettiEffect"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),   -- Red
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(0, 255, 0)), -- Green
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 0, 255)),  -- Blue
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(255, 255, 0)), -- Yellow
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 255)),   -- Magenta
	})
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Rate = 100
	particles.Speed = NumberRange.new(10, 20)
	particles.SpreadAngle = Vector2.new(45, 45)
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = attachment

	-- Emit particles
	particles:Emit(150)

	-- Clean up after particles finish
	task.delay(3, function()
		particles.Enabled = false
		Debris:AddItem(part, 1)
	end)
end

-- Create smoke particle effect
local function createSmokeEffect(position)
	local part = Instance.new("Part")
	part.Name = "SmokeEffect"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/smoke_main.dds"
	particles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 200, 200)), -- Light gray
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 150, 150)), -- Medium gray
		ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100)),  -- Dark gray
	})
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2),
		NumberSequenceKeypoint.new(0.5, 5),
		NumberSequenceKeypoint.new(1, 8),
	})
	particles.Lifetime = NumberRange.new(1.5, 3)
	particles.Rate = 80
	particles.Speed = NumberRange.new(5, 15)
	particles.SpreadAngle = Vector2.new(30, 30)
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = attachment

	-- Emit particles
	particles:Emit(120)

	-- Clean up after particles finish
	task.delay(4, function()
		particles.Enabled = false
		Debris:AddItem(part, 1)
	end)
end

-- Create coins particle effect
local function createCoinsEffect(position)
	local part = Instance.new("Part")
	part.Name = "CoinsEffect"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.CFrame = CFrame.new(position)
	part.Parent = Workspace

	local attachment = Instance.new("Attachment")
	attachment.Parent = part

	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 0)),   -- Gold
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 0)), -- Bright gold
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 150, 0)),   -- Dark gold
	})
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 1.2),
		NumberSequenceKeypoint.new(1, 0),
	})
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Rate = 100
	particles.Speed = NumberRange.new(8, 18)
	particles.SpreadAngle = Vector2.new(50, 50)
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	particles.Parent = attachment

	-- Emit particles
	particles:Emit(150)

	-- Clean up after particles finish
	task.delay(3, function()
		particles.Enabled = false
		Debris:AddItem(part, 1)
	end)
end

-- Hide character immediately to prevent ragdoll
local function hideCharacter(character)
	if not character or not character.Parent then
		return
	end

	-- Hide all parts
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = 1
			descendant.CanCollide = false
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 1
		end
	end

	-- Disable humanoid
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
	end

	-- Destroy character after a brief delay to allow particles to spawn
	task.delay(0.1, function()
		if character and character.Parent then
			character:Destroy()
		end
	end)
end

-- Handle kill event
local function onEliminated(_gameState, _killer, victim, _tool)
	if not victim or not victim.Parent then
		return
	end

	local rootPart = victim:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		return
	end
	local position = rootPart.Position

	-- === EXPLOSIVE DEMISE LOGIC ===
	local victimPlayer = Players:GetPlayerFromCharacter(victim)
	if victimPlayer and getMeta() then
		local explodeMult = getMeta().GetStatMultiplier(victimPlayer, "ExplosiveDeath")

		if explodeMult > 1 then
			local dmgPercent = explodeMult - 1 -- e.g. 1.5 -> 0.5 (50%)
			local explosionDmg = victim.Humanoid.MaxHealth * dmgPercent
			local radius = 25

			-- Visual Explosion
			local explosion = Instance.new("Explosion")
			explosion.Position = position
			explosion.BlastRadius = 0 -- Handle damage manually
			explosion.BlastPressure = 0
			explosion.Visible = true
			explosion.Parent = Workspace

			-- Manual Damage Logic
			local overlap = OverlapParams.new()
			overlap.FilterDescendantsInstances = {victim}
			overlap.FilterType = Enum.RaycastFilterType.Exclude

			local hits = Workspace:GetPartBoundsInRadius(position, radius, overlap)
			local damaged = {}

			for _, part in ipairs(hits) do
				local char = part.Parent
				local hum = char:FindFirstChild("Humanoid")
				if hum and hum.Health > 0 and not damaged[hum] then
					damaged[hum] = true
					-- Check for Friendly Fire here if needed
					hum:TakeDamage(explosionDmg)
				end
			end
			print("💥 Explosive Demise triggered for", victimPlayer.Name)
		end
	end
	-- ==============================

	hideCharacter(victim)

	-- (Keep existing particle logic below...)
	local effectType = math.random(1, 3)
	if effectType == 1 then
		createConfettiEffect(position)
	elseif effectType == 2 then
		createSmokeEffect(position)
	else
		createCoinsEffect(position)
	end
end

function KillEffectsManager.Start()
	print("--- Starting KillEffectsManager ---")

	-- Wait for Eliminated event to be available
	task.spawn(function()
		if eliminatedEvent then
			print("✅ KillEffectsManager: Hooked into Blaster System!")
			eliminatedEvent.Event:Connect(onEliminated)
		else
			-- Retry waiting
			task.wait(2)
			local blasterFolder = ServerScriptService:WaitForChild("Blaster", 10)
			if blasterFolder then
				local eventsFolder = blasterFolder:WaitForChild("Events", 10)
				if eventsFolder then
					eliminatedEvent = eventsFolder:WaitForChild("Eliminated", 10)
					if eliminatedEvent then
						print("✅ KillEffectsManager: Hooked into Blaster System!")
						eliminatedEvent.Event:Connect(onEliminated)
					else
						warn("⚠️ KillEffectsManager: Failed to find Eliminated event")
					end
				end
			end
		end
	end)
end

return KillEffectsManager

