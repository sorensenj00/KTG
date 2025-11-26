local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local CollectionService = game:GetService("CollectionService")

-- UI Configuration
local TEXT_SIZE = 14
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local STROKE_TRANSPARENCY = 0
local OFFSET = Vector3.new(0, 3, 0) -- Above head

local function createOverheadUI()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RankOverhead"
	billboard.Size = UDim2.fromScale(4, 1.5) -- Increased height to fit health bar
	billboard.StudsOffset = OFFSET
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 2000 -- Increased from 100 to 2000 (Long range)
	billboard.Enabled = false -- Hidden by default

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "InfoLabel"
	textLabel.Size = UDim2.fromScale(1, 0.6) -- Top 60%
	textLabel.Position = UDim2.fromScale(0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = TEXT_COLOR
	textLabel.TextStrokeTransparency = STROKE_TRANSPARENCY
	textLabel.TextSize = TEXT_SIZE
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Parent = billboard
	
	-- Health Bar Background
	local healthBg = Instance.new("Frame")
	healthBg.Name = "HealthBarBg"
	healthBg.Size = UDim2.fromScale(0.8, 0.15) -- Slightly narrower
	healthBg.Position = UDim2.fromScale(0.1, 0.65) -- Below text, centered
	healthBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
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
	healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 100) -- Green
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBg
	
	return billboard
end

local function updateLabel(dataSource: Instance, label: TextLabel)
	local level = dataSource:GetAttribute("Level") or 1
	local xp = dataSource:GetAttribute("XP") or 0
	local requiredXP = ScalingConfig.GetXPRequired(level)
	
	if level >= ScalingConfig.MAX_LEVEL then
		label.Text = "MAX LEVEL (20)"
		label.TextColor3 = ScalingConfig.STAR_MODE_COLOR
	else
		label.Text = string.format("Level %d | XP: %d/%d", level, xp, requiredXP)
		label.TextColor3 = TEXT_COLOR
	end

end

local function updateHealthBar(humanoid: Humanoid, fill: Frame)
	local hp = humanoid.Health
	local maxHp = humanoid.MaxHealth
	local percent = math.clamp(hp / maxHp, 0, 1)
	
	fill.Size = UDim2.fromScale(percent, 1)
	
	-- Color shift from Green to Red
	local color = Color3.fromRGB(0, 255, 100):Lerp(Color3.fromRGB(255, 50, 50), 1 - percent)
	fill.BackgroundColor3 = color
end

local function setupEntity(entity: Model, dataSource: Instance)
	local head = entity:WaitForChild("Head", 10)
	if not head then return end
	
	-- Check if already exists
	if head:FindFirstChild("RankOverhead") then return end

	local ui = createOverheadUI()
	ui.Adornee = head
	ui.Parent = head
	
	local label = ui.InfoLabel
	updateLabel(dataSource, label)
	
	-- Listen for attribute changes
	dataSource.AttributeChanged:Connect(function(attributeName)
		if attributeName == "Level" or attributeName == "XP" then
			updateLabel(dataSource, label)
		end
	end)
	
	-- Setup Health Bar
	local humanoid = entity:FindFirstChild("Humanoid")
	if humanoid then
		-- Disable default Roblox health bar
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		
		local healthFill = ui:FindFirstChild("HealthBarBg") and ui.HealthBarBg:FindFirstChild("HealthBarFill")
		
		-- Visibility Logic
		local lastDamageTime = 0
		local VISIBILITY_RANGE = 200
		local DAMAGE_SHOW_DURATION = 10
		local SCALE_DISTANCE_MAX = 400 -- Distance at which UI is smallest
		
		-- Track if this entity was damaged by the local player
		local wasDamagedByPlayer = false
		
		-- Listen for player damaging this entity
		local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Blaster"):WaitForChild("Remotes")
		local playerDamagedRemote = remotes:WaitForChild("PlayerDamagedEntity", 10)
		
		local damageConnection
		if playerDamagedRemote then
			damageConnection = playerDamagedRemote.OnClientEvent:Connect(function(damagedEntity)
				if damagedEntity == entity then
					wasDamagedByPlayer = true
					lastDamageTime = tick()
				end
			end)
		end
		
		-- Reset tracking when local player's character is removed (death/respawn)
		local localPlayer = Players.LocalPlayer
		local characterRemovedConnection
		if localPlayer.Character then
			characterRemovedConnection = localPlayer.CharacterRemoving:Connect(function()
				wasDamagedByPlayer = false
				lastDamageTime = 0
			end)
		end
		
		-- Update loop for visibility and scaling
		local RunService = game:GetService("RunService")
		local camera = workspace.CurrentCamera
		
		local visibilityConnection
		visibilityConnection = RunService.Heartbeat:Connect(function()
			if not head or not head.Parent then
				visibilityConnection:Disconnect()
				if damageConnection then
					damageConnection:Disconnect()
				end
				if characterRemovedConnection then
					characterRemovedConnection:Disconnect()
				end
				return
			end
			
			local dist = (camera.CFrame.Position - head.Position).Magnitude
			local recentlyDamaged = wasDamagedByPlayer and (tick() - lastDamageTime) < DAMAGE_SHOW_DURATION
			
			-- Visibility with smooth fade
			if dist <= VISIBILITY_RANGE or recentlyDamaged then
				ui.Enabled = true
				
				-- Fade based on distance (0 = fully visible, VISIBILITY_RANGE = transparent)
				-- Fade starts at 100 studs, full fade at 200 studs
				local fadeStart = 100
				local fadeAlpha = math.clamp((dist - fadeStart) / (VISIBILITY_RANGE - fadeStart), 0, 1)
				
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
			
			-- Distance-based scaling (closer = larger, farther = smaller)
			-- Scale from 1.5x at 0 distance to 0.5x at SCALE_DISTANCE_MAX
			local scaleFactor = math.clamp(1.5 - (dist / SCALE_DISTANCE_MAX), 0.5, 1.5)
			ui.Size = UDim2.fromScale(4 * scaleFactor, 1.5 * scaleFactor)
		end)
		
		if healthFill then
			updateHealthBar(humanoid, healthFill)
			
			humanoid.HealthChanged:Connect(function()
				updateHealthBar(humanoid, healthFill)
			end)
			
			humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
				updateHealthBar(humanoid, healthFill)
			end)
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupEntity(character, player)
	end)
	
	if player.Character then
		setupEntity(player.Character, player)
	end
end

local function onBotAdded(bot: Instance)
	if bot:IsA("Model") then
		setupEntity(bot, bot)
	end
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
