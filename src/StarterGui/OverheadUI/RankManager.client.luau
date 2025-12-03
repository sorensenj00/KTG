--[[
	RankManager: Overhead UI for players and bots
	Shows level, XP, and health bar above entities
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- Config
local VISIBILITY_RANGE = 200
local COMBAT_RANGE = 600
local COMBAT_DURATION = 10
local FADE_START = 0.8
local SCALE_DIVISOR = 25

-- All active overhead UIs: [entity] = { ui, connections, lastDamage, inCombat }
local activeUIs = {}

-- Track setup attempts for retry logic
local setupAttempts = {}
local MAX_ATTEMPTS = 5

--== UI Creation ==--

local function createUI()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RankOverhead"
	billboard.Size = UDim2.fromScale(4, 1.5)
	billboard.StudsOffset = Vector3.new(0, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = VISIBILITY_RANGE

	local label = Instance.new("TextLabel")
	label.Name = "InfoLabel"
	label.Size = UDim2.fromScale(1, 0.6)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	local healthBg = Instance.new("Frame")
	healthBg.Name = "HealthBg"
	healthBg.Size = UDim2.fromScale(0.8, 0.15)
	healthBg.Position = UDim2.fromScale(0.1, 0.65)
	healthBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	healthBg.BorderSizePixel = 0
	healthBg.Parent = billboard

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 1.5
	stroke.Parent = healthBg

	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 100)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBg

	return billboard
end

--== Update Functions ==--

local function updateLabel(entity, label)
	local level = entity:GetAttribute("Level") or 1
	local xp = entity:GetAttribute("XP") or 0
	local required = ScalingConfig.GetXPRequired(level)

	if level >= ScalingConfig.MAX_LEVEL then
		label.Text = string.format("MAX LEVEL (%d)", ScalingConfig.MAX_LEVEL)
		label.TextColor3 = ScalingConfig.STAR_MODE_COLOR
	else
		label.Text = string.format("Level %d | XP: %d/%d", level, xp, required)
		label.TextColor3 = Color3.new(1, 1, 1)
	end
end

local function updateHealth(humanoid, fill)
	local pct = math.clamp(humanoid.Health / humanoid.MaxHealth, 0, 1)
	fill.Size = UDim2.fromScale(pct, 1)
	fill.BackgroundColor3 = Color3.fromRGB(0, 255, 100):Lerp(Color3.fromRGB(255, 50, 50), 1 - pct)
end

--== Entity Setup ==--

local function setupEntity(entity, dataSource)
	-- Skip local player
	if dataSource == LocalPlayer then
		return false
	end

	local head = entity:FindFirstChild("Head")
	local humanoid = entity:FindFirstChild("Humanoid")

	if not head or not humanoid then
		return false -- Will retry
	end

	-- Already has UI
	if head:FindFirstChild("RankOverhead") then
		return true
	end

	-- Create UI
	local ui = createUI()
	ui.Adornee = head
	ui.Parent = head

	local label = ui.InfoLabel
	local healthFill = ui.HealthBg.HealthFill

	updateLabel(dataSource, label)
	updateHealth(humanoid, healthFill)

	-- Disable default health bar
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff

	-- Connections
	local connections = {}

	table.insert(
		connections,
		dataSource.AttributeChanged:Connect(function(attr)
			if attr == "Level" or attr == "XP" then
				updateLabel(dataSource, label)
			end
		end)
	)

	table.insert(
		connections,
		humanoid.HealthChanged:Connect(function()
			updateHealth(humanoid, healthFill)
		end)
	)

	table.insert(
		connections,
		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
			updateHealth(humanoid, healthFill)
		end)
	)

	-- Store data
	activeUIs[entity] = {
		ui = ui,
		head = head,
		connections = connections,
		lastDamage = 0,
		inCombat = false,
	}

	-- Cleanup on death
	humanoid.Died:Once(function()
		local data = activeUIs[entity]
		if data then
			for _, conn in data.connections do
				conn:Disconnect()
			end
			if data.ui and data.ui.Parent then
				data.ui:Destroy()
			end
			activeUIs[entity] = nil
		end
	end)

	return true
end

--== Combat Tracking ==--

local function resetAllCombatStates()
	for _, data in activeUIs do
		data.inCombat = false
		data.lastDamage = 0
	end
end

local function setupCombatTracking()
	local remotes = ReplicatedStorage:FindFirstChild("Blaster")
	if not remotes then
		return
	end
	remotes = remotes:FindFirstChild("Remotes")
	if not remotes then
		return
	end

	local damageRemote = remotes:FindFirstChild("PlayerDamagedEntity")
	if damageRemote then
		damageRemote.OnClientEvent:Connect(function(entity)
			local data = activeUIs[entity]
			if data then
				data.lastDamage = tick()
				data.inCombat = true
			end
		end)
	end
end

-- Reset combat visibility on death AND respawn (outside of setupCombatTracking to always run)
LocalPlayer.CharacterRemoving:Connect(resetAllCombatStates)
LocalPlayer.CharacterAdded:Connect(resetAllCombatStates)

--== Main Update Loop ==--

local function updateAllUIs()
	local now = tick()
	local camPos = Camera.CFrame.Position

	for entity, data in activeUIs do
		local ui = data.ui
		local head = data.head

		-- Cleanup dead entities
		if not head or not head.Parent or not entity.Parent then
			for _, conn in data.connections do
				conn:Disconnect()
			end
			if ui and ui.Parent then
				ui:Destroy()
			end
			activeUIs[entity] = nil
			continue
		end

		-- Distance check
		local dist = (camPos - head.Position).Magnitude
		local inCombat = data.inCombat and (now - data.lastDamage) < COMBAT_DURATION
		local range = inCombat and COMBAT_RANGE or VISIBILITY_RANGE

		if dist > range then
			ui.Enabled = false
			continue
		end

		ui.Enabled = true

		-- Fade calculation
		local fadeStart = range * FADE_START
		local alpha = inCombat and 0 or math.clamp((dist - fadeStart) / (range - fadeStart), 0, 1)

		-- Apply fade
		ui.InfoLabel.TextTransparency = alpha
		ui.InfoLabel.TextStrokeTransparency = 0.3 + alpha * 0.7
		ui.HealthBg.BackgroundTransparency = alpha
		ui.HealthBg.HealthFill.BackgroundTransparency = alpha

		local stroke = ui.HealthBg:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = alpha
		end

		-- Scale with distance
		local scale = math.clamp(dist / SCALE_DIVISOR, 1, 20)
		ui.Size = UDim2.fromScale(4 * scale, 1.5 * scale)
		ui.StudsOffset = Vector3.new(0, scale, 0)
		ui.MaxDistance = inCombat and math.huge or range
	end
end

--== Bot Management ==--

local function trySetupBot(bot)
	if not bot:IsA("Model") or not bot.Parent then
		return
	end

	-- Already tracked
	if activeUIs[bot] then
		return
	end

	local attempts = setupAttempts[bot] or 0
	if attempts >= MAX_ATTEMPTS then
		return
	end

	setupAttempts[bot] = attempts + 1

	if setupEntity(bot, bot) then
		setupAttempts[bot] = nil
	end
end

local function onBotAdded(bot)
	task.defer(trySetupBot, bot)
end

local function onBotRemoved(bot)
	local data = activeUIs[bot]
	if data then
		for _, conn in data.connections do
			conn:Disconnect()
		end
		if data.ui and data.ui.Parent then
			data.ui:Destroy()
		end
		activeUIs[bot] = nil
	end
	setupAttempts[bot] = nil
end

--== Player Management ==--

local function onPlayerAdded(player)
	if player == LocalPlayer then
		return
	end

	local function onCharacter(character)
		task.defer(function()
			setupEntity(character, player)
		end)
	end

	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

local function onPlayerRemoving(player)
	if player.Character then
		local data = activeUIs[player.Character]
		if data then
			for _, conn in data.connections do
				conn:Disconnect()
			end
			if data.ui and data.ui.Parent then
				data.ui:Destroy()
			end
			activeUIs[player.Character] = nil
		end
	end
end

--== Initialize ==--

-- Setup existing players
for _, player in Players:GetPlayers() do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Setup existing bots
for _, bot in CollectionService:GetTagged("BotAI") do
	onBotAdded(bot)
end
for _, bot in CollectionService:GetTagged("DisplayBot") do
	onBotAdded(bot)
end

CollectionService:GetInstanceAddedSignal("BotAI"):Connect(onBotAdded)
CollectionService:GetInstanceAddedSignal("DisplayBot"):Connect(onBotAdded)
CollectionService:GetInstanceRemovedSignal("BotAI"):Connect(onBotRemoved)
CollectionService:GetInstanceRemovedSignal("DisplayBot"):Connect(onBotRemoved)

-- Combat tracking
setupCombatTracking()

-- Main update loop
RunService.Heartbeat:Connect(updateAllUIs)

-- Periodic retry for failed setups
task.spawn(function()
	while true do
		task.wait(2)

		for _, bot in CollectionService:GetTagged("BotAI") do
			if not activeUIs[bot] then
				trySetupBot(bot)
			end
		end

		for _, bot in CollectionService:GetTagged("DisplayBot") do
			if not activeUIs[bot] then
				trySetupBot(bot)
			end
		end

		-- Cleanup dead attempts
		for bot in setupAttempts do
			if not bot.Parent then
				setupAttempts[bot] = nil
			end
		end
	end
end)
