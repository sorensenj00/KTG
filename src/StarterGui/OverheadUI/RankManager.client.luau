local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

-- ============================================
-- CONFIGURATION
-- All magic numbers consolidated here for easy tuning
-- ============================================

-- UI Appearance
local CONFIG = {
	-- Text Styling
	TEXT_SIZE = 14,
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	STROKE_TRANSPARENCY = 0,

	-- Billboard Positioning
	STUDS_OFFSET = Vector3.new(0, 1, 0), -- Above head
	BASE_SIZE = UDim2.fromScale(4, 1.5),
	DEFAULT_MAX_DISTANCE = 600,

	-- Health Bar Colors
	HEALTH_FULL_COLOR = Color3.fromRGB(0, 255, 100),
	HEALTH_EMPTY_COLOR = Color3.fromRGB(255, 50, 50),
	HEALTH_BG_COLOR = Color3.fromRGB(40, 40, 40),

	-- Visibility Ranges (studs)
	PASSIVE_VISIBILITY_RANGE = 100, -- Range when not in combat
	COMBAT_VISIBILITY_RANGE = 600, -- Range after damaging entity
	DAMAGE_SHOW_DURATION = 10, -- Seconds to stay visible after damage

	-- Distance Scaling
	FADE_START_PERCENT = 0.8, -- Fade starts at 80% of visibility range
	BASE_SCALE_DIVISOR = 25, -- dist / 25 = scale factor
	COMBAT_SCALE_DIVISOR = 20, -- dist / 20 = scale factor when damaged
	MIN_COMBAT_SCALE = 1.5, -- Minimum scale when damaged
	MAX_SCALE = 20, -- Cap to prevent massive UI at extreme distances

	-- Timeouts (shorter since we have retry logic)
	WAIT_FOR_HEAD_TIMEOUT = 5,
	WAIT_FOR_HUMANOID_TIMEOUT = 5,
	WAIT_FOR_REMOTE_TIMEOUT = 10,
}

local function createOverheadUI()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RankOverhead"
	billboard.Size = CONFIG.BASE_SIZE
	billboard.StudsOffset = CONFIG.STUDS_OFFSET
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = CONFIG.DEFAULT_MAX_DISTANCE
	billboard.Enabled = false -- Hidden by default

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "InfoLabel"
	textLabel.Size = UDim2.fromScale(1, 0.6) -- Top 60%
	textLabel.Position = UDim2.fromScale(0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = CONFIG.TEXT_COLOR
	textLabel.TextStrokeTransparency = CONFIG.STROKE_TRANSPARENCY
	textLabel.TextSize = CONFIG.TEXT_SIZE
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextScaled = true
	textLabel.Parent = billboard

	-- Health Bar Background
	local healthBg = Instance.new("Frame")
	healthBg.Name = "HealthBarBg"
	healthBg.Size = UDim2.fromScale(0.8, 0.15)
	healthBg.Position = UDim2.fromScale(0.1, 0.65)
	healthBg.BackgroundColor3 = CONFIG.HEALTH_BG_COLOR
	healthBg.BorderSizePixel = 0
	healthBg.Parent = billboard

	local healthStroke = Instance.new("UIStroke")
	healthStroke.Color = Color3.fromRGB(0, 0, 0)
	healthStroke.Thickness = 1.5
	healthStroke.Parent = healthBg

	-- Health Bar Fill
	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthBarFill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = CONFIG.HEALTH_FULL_COLOR
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBg

	return billboard
end

local function updateLabel(dataSource: Instance, label: TextLabel)
	local level = dataSource:GetAttribute("Level") or 1
	local xp = dataSource:GetAttribute("XP") or 0
	local requiredXP = ScalingConfig.GetXPRequired(level)

	if level >= ScalingConfig.MAX_LEVEL then
		label.Text = string.format("MAX LEVEL (%d)", ScalingConfig.MAX_LEVEL)
		label.TextColor3 = ScalingConfig.STAR_MODE_COLOR
	else
		label.Text = string.format("Level %d | XP: %d/%d", level, xp, requiredXP)
		label.TextColor3 = CONFIG.TEXT_COLOR
	end
end

local function updateHealthBar(humanoid: Humanoid, fill: Frame)
	local hp = humanoid.Health
	local maxHp = humanoid.MaxHealth
	local percent = math.clamp(hp / maxHp, 0, 1)

	fill.Size = UDim2.fromScale(percent, 1)

	-- Color shift from Green to Red based on health percent
	local color = CONFIG.HEALTH_FULL_COLOR:Lerp(CONFIG.HEALTH_EMPTY_COLOR, 1 - percent)
	fill.BackgroundColor3 = color
end

local function setupEntity(entity: Model, dataSource: Instance)
	-- Don't show overhead for local player
	if dataSource == Players.LocalPlayer then
		return
	end

	-- Use a longer timeout for streaming/loading
	local head = entity:WaitForChild("Head", CONFIG.WAIT_FOR_HEAD_TIMEOUT)
	if not head then
		return
	end

	-- Check if already exists
	if head:FindFirstChild("RankOverhead") then
		return
	end

	local ui = createOverheadUI()
	ui.Adornee = head
	ui.Parent = head

	local label = ui.InfoLabel
	updateLabel(dataSource, label)

	-- Track ALL connections for cleanup (prevents memory leaks)
	local connections: { RBXScriptConnection } = {}

	-- Helper to cleanup all connections and UI
	local function cleanup()
		for _, conn in ipairs(connections) do
			if conn.Connected then
				conn:Disconnect()
			end
		end
		table.clear(connections)

		if ui and ui.Parent then
			ui:Destroy()
		end
	end

	-- Listen for attribute changes
	table.insert(
		connections,
		dataSource.AttributeChanged:Connect(function(attributeName)
			if attributeName == "Level" or attributeName == "XP" then
				updateLabel(dataSource, label)
			end
		end)
	)

	-- Setup Health Bar
	local humanoid = entity:WaitForChild("Humanoid", CONFIG.WAIT_FOR_HUMANOID_TIMEOUT)
	if humanoid then
		-- Disable default Roblox health bar
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

		local healthFill = ui:FindFirstChild("HealthBarBg") and ui.HealthBarBg:FindFirstChild("HealthBarFill")

		-- Visibility state
		local lastDamageTime = 0
		local wasDamagedByPlayer = false

		-- Listen for player damaging this entity
		local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
		local playerDamagedRemote = remotes:WaitForChild("PlayerDamagedEntity", CONFIG.WAIT_FOR_REMOTE_TIMEOUT)

		-- Helper to force UI fully visible instantly
		local function forceUIVisible()
			ui.Enabled = true
			ui.MaxDistance = math.huge

			-- Force full opacity on all elements immediately
			for _, child in ipairs(ui:GetDescendants()) do
				if child:IsA("TextLabel") then
					child.TextTransparency = 0
					child.TextStrokeTransparency = 0.3
				elseif child:IsA("Frame") then
					if not child:GetAttribute("OriginalTransparency") then
						child:SetAttribute("OriginalTransparency", child.BackgroundTransparency)
					end
					child.BackgroundTransparency = child:GetAttribute("OriginalTransparency")
				elseif child:IsA("UIStroke") then
					child.Transparency = 0
				end
			end
		end

		if playerDamagedRemote then
			table.insert(
				connections,
				playerDamagedRemote.OnClientEvent:Connect(function(damagedEntity)
					if damagedEntity == entity then
						wasDamagedByPlayer = true
						lastDamageTime = tick()

						-- IMMEDIATELY enable and show UI - don't wait for Heartbeat
						forceUIVisible()
					end
				end)
			)
		end

		-- Reset tracking when local player's character is removed (death/respawn)
		local localPlayer = Players.LocalPlayer
		table.insert(
			connections,
			localPlayer.CharacterRemoving:Connect(function()
				wasDamagedByPlayer = false
				lastDamageTime = 0
			end)
		)

		-- Update loop for visibility and scaling
		local camera = workspace.CurrentCamera

		table.insert(
			connections,
			RunService.Heartbeat:Connect(function()
				-- Cleanup check: if entity or head is gone, cleanup everything
				if not head or not head.Parent or not entity or not entity.Parent then
					cleanup()
					return
				end

				local dist = (camera.CFrame.Position - head.Position).Magnitude
				local recentlyDamaged = wasDamagedByPlayer and (tick() - lastDamageTime) < CONFIG.DAMAGE_SHOW_DURATION

				local currentVisibilityRange = recentlyDamaged and CONFIG.COMBAT_VISIBILITY_RANGE
					or CONFIG.PASSIVE_VISIBILITY_RANGE

				-- Visibility with smooth fade
				if dist <= currentVisibilityRange then
					ui.Enabled = true

					-- Fade based on distance (0 = fully visible, currentVisibilityRange = transparent)
					local fadeStart = currentVisibilityRange * CONFIG.FADE_START_PERCENT
					local fadeAlpha = math.clamp((dist - fadeStart) / (currentVisibilityRange - fadeStart), 0, 1)

					-- Force visibility if recently damaged (override fade)
					if recentlyDamaged then
						fadeAlpha = 0
						ui.MaxDistance = math.huge -- Infinite range within combat logic
					else
						ui.MaxDistance = currentVisibilityRange
					end

					-- Apply transparency to all UI elements
					for _, child in ipairs(ui:GetDescendants()) do
						if child:IsA("TextLabel") then
							child.TextTransparency = fadeAlpha
							child.TextStrokeTransparency = math.clamp(0.3 + fadeAlpha * 0.7, 0, 1)
						elseif child:IsA("Frame") then
							-- Save original transparency
							if not child:GetAttribute("OriginalTransparency") then
								child:SetAttribute("OriginalTransparency", child.BackgroundTransparency)
							end
							local origTrans = child:GetAttribute("OriginalTransparency")
							child.BackgroundTransparency = origTrans + fadeAlpha * (1 - origTrans)
						elseif child:IsA("UIStroke") then
							child.Transparency = fadeAlpha
						end
					end
				else
					ui.Enabled = false
				end

				-- Distance-based scaling that grows with distance for readability
				local scaleFactor = math.max(1.0, dist / CONFIG.BASE_SCALE_DIVISOR)

				if recentlyDamaged then
					-- When damaged: slightly larger and grows faster, but capped
					scaleFactor = math.min(
						CONFIG.MAX_SCALE,
						math.max(CONFIG.MIN_COMBAT_SCALE, dist / CONFIG.COMBAT_SCALE_DIVISOR)
					)
				end

				ui.Size =
					UDim2.fromScale(CONFIG.BASE_SIZE.X.Scale * scaleFactor, CONFIG.BASE_SIZE.Y.Scale * scaleFactor)
				ui.StudsOffset = CONFIG.STUDS_OFFSET * scaleFactor
			end)
		)

		if healthFill then
			updateHealthBar(humanoid, healthFill)

			table.insert(
				connections,
				humanoid.HealthChanged:Connect(function()
					updateHealthBar(humanoid, healthFill)
				end)
			)

			table.insert(
				connections,
				humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
					updateHealthBar(humanoid, healthFill)
				end)
			)
		end

		-- Also cleanup when humanoid dies
		table.insert(connections, humanoid.Died:Connect(cleanup))
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(setupEntity, character, player)
	end)

	if player.Character then
		task.spawn(setupEntity, player.Character, player)
	end
end

local function onBotAdded(bot: Instance)
	if bot:IsA("Model") then
		task.spawn(setupEntity, bot, bot)
	end
end

-- Track which bots we've attempted to setup (to avoid spamming retries)
local setupAttempts: { [Instance]: number } = {}
local MAX_SETUP_ATTEMPTS = 5

-- Ensure a bot has overhead UI, with retry logic
local function ensureBotHasOverhead(bot: Instance)
	if not bot:IsA("Model") or not bot.Parent then
		return
	end

	local head = bot:FindFirstChild("Head")
	if not head then
		-- Head not loaded yet, will retry on next sweep
		return
	end

	-- Already has overhead UI
	if head:FindFirstChild("RankOverhead") then
		setupAttempts[bot] = nil -- Clear attempts tracking
		return
	end

	-- Track attempts to avoid infinite retries
	local attempts = setupAttempts[bot] or 0
	if attempts >= MAX_SETUP_ATTEMPTS then
		return -- Give up after max attempts
	end

	setupAttempts[bot] = attempts + 1
	task.spawn(setupEntity, bot, bot)
end

-- Initialize for all players
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)

-- Initialize for all bots
for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
	onBotAdded(bot)
end
for _, bot in ipairs(CollectionService:GetTagged("DisplayBot")) do
	onBotAdded(bot)
end

CollectionService:GetInstanceAddedSignal("BotAI"):Connect(onBotAdded)
CollectionService:GetInstanceAddedSignal("DisplayBot"):Connect(onBotAdded)

-- Periodic sweep to catch any bots that missed overhead UI setup
-- This handles race conditions, streaming, and edge cases
task.spawn(function()
	while true do
		task.wait(2) -- Check every 2 seconds

		-- Check all BotAI tagged entities
		for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
			ensureBotHasOverhead(bot)
		end

		-- Check all DisplayBot tagged entities
		for _, bot in ipairs(CollectionService:GetTagged("DisplayBot")) do
			ensureBotHasOverhead(bot)
		end

		-- Clean up attempts tracking for dead bots
		for bot in pairs(setupAttempts) do
			if not bot.Parent then
				setupAttempts[bot] = nil
			end
		end
	end
end)
