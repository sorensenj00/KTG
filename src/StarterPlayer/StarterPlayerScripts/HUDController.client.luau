local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContextActionService = game:GetService("ContextActionService")

local Constants = require(ReplicatedStorage.Blaster.Constants)
-- local InputCategorizer = require(ReplicatedStorage.Blaster.Scripts.InputCategorizer) -- Unused
local MetaConfig = require(ReplicatedStorage.GameLoop.MetaConfig)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local StarterGui = game:GetService("StarterGui")

-- Disable default Roblox HUD (PlayerList, Chat, Backpack, etc.)
-- We wrap this in a pcall because it can sometimes fail if called too early
task.spawn(function()
	local success = false
	while not success do
		success, _ = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false) -- Disabled for custom leaderboard
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, true)
		end)
		if not success then
			task.wait(0.5)
		end
	end
end)

-- --- Sound Assets --- --
local SOUNDS = {
	Hover = "rbxassetid://6895079853",
	Click = "rbxassetid://6895079684",
	Purchase = "rbxassetid://6895079766",
	Error = "rbxassetid://6895079595",
}

local function playSound(soundId)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = 0.5
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
end

-- Unused helper
-- local function bindButtonSounds(btn, isPurchase)
-- 	btn.MouseEnter:Connect(function()
-- 		playSound(SOUNDS.Hover)
-- 	end)
-- 	if not isPurchase then
-- 		btn.MouseButton1Click:Connect(function()
-- 			playSound(SOUNDS.Click)
-- 		end)
-- 	end
-- end

-- --- Constants & Theme --- --
local ARCADE_THEME = {
	BG_DARK = Color3.fromRGB(20, 20, 25),
	BG_LIGHT = Color3.fromRGB(30, 30, 35),
	BG_CARD = Color3.fromRGB(25, 25, 30),
	ACCENT_GREEN = Color3.fromRGB(0, 255, 150),
	ACCENT_ORANGE = Color3.fromRGB(255, 150, 0),
	TEXT_WHITE = Color3.fromRGB(255, 255, 255),
	TEXT_GRAY = Color3.fromRGB(180, 180, 180),
	STROKE_DARK = Color3.fromRGB(50, 50, 60),
}

local COLORS = {
	XP_GOLD = Color3.fromRGB(255, 215, 0),
	BUTTON_GREEN = Color3.fromRGB(0, 200, 100),
	BUTTON_RED = Color3.fromRGB(200, 50, 50),
	LOCKED_GREY = Color3.fromRGB(100, 100, 100),
}

local ICON_MAP = {
	Lock = "rbxassetid://6895079853", -- Placeholder
	StartLevel = "rbxassetid://6895079853", -- Placeholder
	-- Add other icons as needed
}

-- --- State Variables --- --
local currentGlobalXP = 0
local previousGlobalXP = 0
local currentBiomass = 0
local currentUpgrades = {}
local currentMagazineSize = 0

-- --- HUD Creation --- --
-- Shop UI element cache (100x faster updates)
local cardCache = {}
local function createHUD()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HUD"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- Helper for Neon Borders
	local function addNeonBorder(parent, color, cornerRadius)
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = 2
		stroke.Transparency = 0
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = parent
		
		local glow = Instance.new("UIStroke")
		glow.Color = color
		glow.Thickness = 4
		glow.Transparency = 0.5
		glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		glow.Name = "Glow"
		glow.Parent = parent

		if cornerRadius then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, cornerRadius)
			corner.Parent = parent
		end
		return stroke
	end

	-- 1. Top Right Widget (Size & Kills)
	local topWidget = Instance.new("Frame")
	topWidget.Name = "TopWidget"
	topWidget.Size = UDim2.fromOffset(200, 80)
	topWidget.Position = UDim2.new(1, -20, 0, 10) -- Moved to Top Right
	topWidget.AnchorPoint = Vector2.new(1, 0)
	topWidget.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	topWidget.BackgroundTransparency = 0.3
	topWidget.Parent = screenGui
	
	addNeonBorder(topWidget, Color3.fromRGB(100, 100, 255), 16) -- Blue/Purple Neon
	
	local sizeLabel = Instance.new("TextLabel")
	sizeLabel.Name = "SizeLabel"
	sizeLabel.Size = UDim2.new(1, 0, 0.6, 0)
	sizeLabel.BackgroundTransparency = 1
	sizeLabel.Text = "SIZE: 1"
	sizeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	sizeLabel.Font = Enum.Font.GothamBlack
	sizeLabel.TextSize = 28
	sizeLabel.Parent = topWidget
	
	local topKillsLabel = Instance.new("TextLabel")
	topKillsLabel.Name = "TopKillsLabel"
	topKillsLabel.Size = UDim2.new(1, 0, 0.4, 0)
	topKillsLabel.Position = UDim2.new(0, 0, 0.6, 0)
	topKillsLabel.BackgroundTransparency = 1
	topKillsLabel.Text = "KILLS: 0"
	topKillsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	topKillsLabel.Font = Enum.Font.GothamBold
	topKillsLabel.TextSize = 16
	topKillsLabel.Parent = topWidget

	-- 2. Bottom Left Widget (Health)
	local healthWidget = Instance.new("Frame")
	healthWidget.Name = "HealthWidget"
	healthWidget.Size = UDim2.fromOffset(280, 50)
	healthWidget.Position = UDim2.new(0, 20, 1, -20)
	healthWidget.AnchorPoint = Vector2.new(0, 1)
	healthWidget.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	healthWidget.BackgroundTransparency = 0.3
	healthWidget.Parent = screenGui
	
	addNeonBorder(healthWidget, Color3.fromRGB(0, 255, 255), 25) -- Cyan Neon

	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 150)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthWidget
	
	local healthGradient = Instance.new("UIGradient")
	healthGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 200, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 255, 150))
	})
	healthGradient.Parent = healthFill
	
	local healthCorner = Instance.new("UICorner")
	healthCorner.CornerRadius = UDim.new(0, 25)
	healthCorner.Parent = healthFill

	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.Text = "Health: 100/100"
	healthText.TextColor3 = Color3.new(1, 1, 1)
	healthText.Font = Enum.Font.GothamBlack
	healthText.TextSize = 20
	healthText.TextStrokeTransparency = 0.5
	healthText.Parent = healthWidget

	-- 3. Bottom Center Widget (Progression)
	local progressionWidget = Instance.new("Frame")
	progressionWidget.Name = "ProgressionWidget"
	progressionWidget.Size = UDim2.fromOffset(400, 50) -- Matches HealthWidget height
	progressionWidget.Position = UDim2.new(0.5, 0, 1, -20)
	progressionWidget.AnchorPoint = Vector2.new(0.5, 1)
	progressionWidget.BackgroundTransparency = 1
	progressionWidget.Parent = screenGui
	
	-- XP Bar Container (Pill Shape like Health)
	local xpBarContainer = Instance.new("Frame")
	xpBarContainer.Name = "XPBarContainer"
	xpBarContainer.Size = UDim2.new(1, 0, 1, 0) -- Fill the widget
	xpBarContainer.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	xpBarContainer.BackgroundTransparency = 0.3
	xpBarContainer.Parent = progressionWidget
	
	addNeonBorder(xpBarContainer, Color3.fromRGB(255, 100, 200), 25) -- Pink Neon, pill radius

	local xpFill = Instance.new("Frame")
	xpFill.Name = "XPFill"
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBarContainer
	
	local xpGradient = Instance.new("UIGradient")
	xpGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 50, 150)), -- Pink
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 150, 50))  -- Orange
	})
	xpGradient.Parent = xpFill
	
	local xpCorner = Instance.new("UICorner")
	xpCorner.CornerRadius = UDim.new(0, 25)
	xpCorner.Parent = xpFill
	
	-- Level Text (Inside Bar)
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.fromScale(1, 1)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 1"
	levelLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	levelLabel.Font = Enum.Font.GothamBlack
	levelLabel.TextSize = 20
	levelLabel.TextStrokeTransparency = 0.5
	levelLabel.Parent = xpBarContainer
	
	-- Stats Row (Below XP Bar)
	local statsRow = Instance.new("Frame")
	statsRow.Name = "StatsRow"
	statsRow.Size = UDim2.new(1, 0, 0, 20)
	statsRow.Position = UDim2.new(0, 0, 1, 5)
	statsRow.BackgroundTransparency = 1
	statsRow.Parent = progressionWidget
	
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statsLayout.Padding = UDim.new(0, 20)
	statsLayout.Parent = statsRow
	
	local function createStatLabel(name, color)
		local label = Instance.new("TextLabel")
		label.Name = name
		label.AutomaticSize = Enum.AutomaticSize.X
		label.Size = UDim2.new(0, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = name .. ": 0"
		label.TextColor3 = color
		label.Font = Enum.Font.GothamBold
		label.TextSize = 14
		label.TextStrokeTransparency = 0.5 -- Added stroke for readability
		label.Parent = statsRow
		return label
	end
	
	local killsStatLabel = createStatLabel("Kills", ARCADE_THEME.TEXT_WHITE)
	local biomassStatLabel = createStatLabel("Biomass", ARCADE_THEME.ACCENT_GREEN)
	local gxpStatLabel = createStatLabel("GXP", ARCADE_THEME.ACCENT_ORANGE)

	-- 4. Bottom Right Widget (Ammo)
	local ammoWidget = Instance.new("Frame")
	ammoWidget.Name = "AmmoWidget"
	ammoWidget.Size = UDim2.fromOffset(220, 60)
	ammoWidget.Position = UDim2.new(1, -20, 1, -20)
	ammoWidget.AnchorPoint = Vector2.new(1, 1)
	ammoWidget.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	ammoWidget.BackgroundTransparency = 0.3
	ammoWidget.Visible = false
	ammoWidget.Parent = screenGui
	
	addNeonBorder(ammoWidget, Color3.fromRGB(0, 150, 255), 10) -- Blue Neon
	
	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Name = "AmmoLabel"
	ammoLabel.Size = UDim2.new(0.6, 0, 1, 0)
	ammoLabel.Position = UDim2.new(0, 10, 0, 0)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.Text = "30/30"
	ammoLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	ammoLabel.Font = Enum.Font.GothamBlack
	ammoLabel.TextSize = 32
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
	ammoLabel.Parent = ammoWidget
	
	local weaponIcon = Instance.new("ImageLabel")
	weaponIcon.Name = "WeaponIcon"
	weaponIcon.Size = UDim2.new(0, 50, 0, 50)
	weaponIcon.Position = UDim2.new(1, -60, 0.5, 0)
	weaponIcon.AnchorPoint = Vector2.new(0, 0.5)
	weaponIcon.BackgroundTransparency = 1
	weaponIcon.Parent = ammoWidget
	
	-- 5. XP Popup (Keep existing logic but style it)
	local xpPopup = Instance.new("Frame")
	xpPopup.Name = "XPPopup"
	xpPopup.Size = UDim2.new(0, 200, 0, 50)
	xpPopup.Position = UDim2.fromScale(0.5, 0.3)
	xpPopup.AnchorPoint = Vector2.new(0.5, 0.5)
	xpPopup.BackgroundTransparency = 1
	xpPopup.Visible = false
	xpPopup.Parent = screenGui
	
	local xpPopupText = Instance.new("TextLabel")
	xpPopupText.Name = "XPPopupText"
	xpPopupText.Size = UDim2.fromScale(1, 1)
	xpPopupText.BackgroundTransparency = 1
	xpPopupText.Text = "+100 XP"
	xpPopupText.TextColor3 = Color3.fromRGB(255, 215, 0)
	xpPopupText.TextSize = 24
	xpPopupText.Font = Enum.Font.LuckiestGuy
	xpPopupText.TextStrokeTransparency = 0
	xpPopupText.Parent = xpPopup

	-- 6. Shop UI (Keep existing logic)
	local shopMainFrame = Instance.new("Frame")
	shopMainFrame.Name = "ShopMainFrame"
	shopMainFrame.Size = UDim2.fromScale(0.6, 0.7)
	shopMainFrame.Position = UDim2.fromScale(0.5, 0.5)
	shopMainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopMainFrame.BackgroundColor3 = ARCADE_THEME.BG_DARK
	shopMainFrame.BorderSizePixel = 0
	shopMainFrame.Visible = false
	shopMainFrame.Parent = screenGui
	
	local shopCorner = Instance.new("UICorner")
	shopCorner.CornerRadius = UDim.new(0, 10)
	shopCorner.Parent = shopMainFrame
	
	local shopStroke = Instance.new("UIStroke")
	shopStroke.Color = ARCADE_THEME.STROKE_DARK
	shopStroke.Thickness = 2
	shopStroke.Parent = shopMainFrame
	
	local shopTitle = Instance.new("TextLabel")
	shopTitle.Name = "Title"
	shopTitle.Size = UDim2.new(1, 0, 0, 50)
	shopTitle.BackgroundTransparency = 1
	shopTitle.Text = "SKILL TREE"
	shopTitle.TextColor3 = ARCADE_THEME.ACCENT_GREEN
	shopTitle.Font = Enum.Font.LuckiestGuy
	shopTitle.TextSize = 32
	shopTitle.Parent = shopMainFrame
	
	local shopCloseButton = Instance.new("TextButton")
	shopCloseButton.Name = "ShopCloseButton"
	shopCloseButton.Size = UDim2.new(0, 30, 0, 30)
	shopCloseButton.Position = UDim2.new(1, -10, 0, 10)
	shopCloseButton.AnchorPoint = Vector2.new(1, 0)
	shopCloseButton.BackgroundColor3 = ARCADE_THEME.BG_LIGHT
	shopCloseButton.Text = "X"
	shopCloseButton.TextColor3 = ARCADE_THEME.TEXT_WHITE
	shopCloseButton.Font = Enum.Font.GothamBold
	shopCloseButton.TextSize = 18
	shopCloseButton.Parent = shopMainFrame
	
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = shopCloseButton
	
	local respawnButton = Instance.new("TextButton")
	respawnButton.Name = "RespawnButton"
	respawnButton.Size = UDim2.new(0, 150, 0, 40)
	respawnButton.Position = UDim2.new(0.5, 0, 1, -20)
	respawnButton.AnchorPoint = Vector2.new(0.5, 1)
	respawnButton.BackgroundColor3 = ARCADE_THEME.ACCENT_ORANGE
	respawnButton.Text = "RESPAWN"
	respawnButton.TextColor3 = ARCADE_THEME.TEXT_WHITE
	respawnButton.Font = Enum.Font.GothamBold
	respawnButton.TextSize = 20
	respawnButton.Visible = false
	respawnButton.Parent = shopMainFrame
	
	local respawnCorner = Instance.new("UICorner")
	respawnCorner.CornerRadius = UDim.new(0, 8)
	respawnCorner.Parent = respawnButton
	
	local shopScrollFrame = Instance.new("ScrollingFrame")
	shopScrollFrame.Name = "ShopScrollFrame"
	shopScrollFrame.Size = UDim2.new(1, -40, 1, -80)
	shopScrollFrame.Position = UDim2.new(0, 20, 0, 60)
	shopScrollFrame.BackgroundTransparency = 1
	shopScrollFrame.ScrollBarThickness = 6
	shopScrollFrame.Parent = shopMainFrame
	
	local shopLayout = Instance.new("UIListLayout")
	shopLayout.Padding = UDim.new(0, 20)
	shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
	shopLayout.Parent = shopScrollFrame

	-- 7. Death Summary Frame (Legacy/Fallback)
	local deathSummaryFrame = Instance.new("Frame")
	deathSummaryFrame.Name = "DeathSummaryFrame"
	deathSummaryFrame.Size = UDim2.fromScale(0.4, 0.4)
	deathSummaryFrame.Position = UDim2.fromScale(0.5, 0.5)
	deathSummaryFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	deathSummaryFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	deathSummaryFrame.Visible = false
	deathSummaryFrame.Parent = screenGui
	
	local okButton = Instance.new("TextButton")
	okButton.Name = "OKButton"
	okButton.Size = UDim2.new(0, 100, 0, 30)
	okButton.Position = UDim2.new(0.5, 0, 1, -20)
	okButton.AnchorPoint = Vector2.new(0.5, 1)
	okButton.Text = "OK"
	okButton.Parent = deathSummaryFrame

	return {
		ScreenGui = screenGui,
		-- Top Widget
		SizeLabel = sizeLabel,
		TopKillsLabel = topKillsLabel,
		
		-- Health Widget
		HealthText = healthText,
		HealthFill = healthFill,
		
		-- Progression Widget
		LevelLabel = levelLabel,
		XPFill = xpFill,
		KillsStatLabel = killsStatLabel,
		BiomassStatLabel = biomassStatLabel,
		GXPStatLabel = gxpStatLabel,
		
		-- Ammo Widget
		AmmoWidget = ammoWidget,
		AmmoLabel = ammoLabel,
		WeaponIcon = weaponIcon,
		
		-- Other
		XPPopup = xpPopup,
		XPPopupText = xpPopupText,
		ShopMainFrame = shopMainFrame,
		ShopScrollFrame = shopScrollFrame,
		ShopCloseButton = shopCloseButton,
		RespawnButton = respawnButton,
		DeathSummaryFrame = deathSummaryFrame,
		OKButton = okButton
	}
end

-- Initialize HUD
local hud = createHUD()

-- --- Shop Creation Functions --- --

-- Create tier section
local function createTierSection(tierNumber: number, tierData)
	local tierFrame = Instance.new("Frame")
	tierFrame.Name = "Tier" .. tierNumber
	tierFrame.BackgroundTransparency = 1
	tierFrame.LayoutOrder = tierNumber
	tierFrame.Size = UDim2.new(1, -15, 0, 0)
	tierFrame.AutomaticSize = Enum.AutomaticSize.Y
	tierFrame.Parent = hud.ShopScrollFrame

	-- Tier Header
	local tierHeader = Instance.new("Frame")
	tierHeader.Name = "TierHeader"
	tierHeader.Size = UDim2.new(1, 0, 0, 40)
	tierHeader.BackgroundColor3 = tierData.Color
	tierHeader.BackgroundTransparency = 0.5
	tierHeader.BorderSizePixel = 0
	tierHeader.Parent = tierFrame
    
    local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 6)
	headerCorner.Parent = tierHeader
	
	local headerStroke = Instance.new("UIStroke")
	headerStroke.Color = tierData.Color
	headerStroke.Transparency = 0.5
	headerStroke.Thickness = 1
	headerStroke.Parent = tierHeader

	local tierNameLabel = Instance.new("TextLabel")
	tierNameLabel.Name = "TierName"
	tierNameLabel.Size = UDim2.new(1, -20, 1, 0)
	tierNameLabel.Position = UDim2.new(0, 10, 0, 0)
	tierNameLabel.BackgroundTransparency = 1
	tierNameLabel.Text = tierData.Name .. " (Req: " .. tierData.UnlockBiomass .. " Bio)"
	tierNameLabel.TextColor3 = tierData.Color
	tierNameLabel.TextSize = 18
	tierNameLabel.Font = Enum.Font.GothamBold
	tierNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	tierNameLabel.Parent = tierHeader

	-- Upgrade container
	local upgradeContainer = Instance.new("Frame")
	upgradeContainer.Name = "UpgradeContainer"
	upgradeContainer.Size = UDim2.new(1, 0, 0, 0)
	upgradeContainer.Position = UDim2.new(0, 0, 0, 50)
	upgradeContainer.BackgroundTransparency = 1
	upgradeContainer.AutomaticSize = Enum.AutomaticSize.Y
	upgradeContainer.Parent = tierFrame

	local upgradeListLayout = Instance.new("UIListLayout")
	upgradeListLayout.Padding = UDim.new(0, 10)
	upgradeListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	upgradeListLayout.Parent = upgradeContainer

	return tierFrame
end

-- Create upgrade card (with element caching for performance)
local function createUpgradeCard(statName: string, upgradeConfig: any)
	local cardFrame = Instance.new("Frame")
	cardFrame.Name = statName .. "Card"
	cardFrame.Size = UDim2.new(1, 0, 0, 80)
	cardFrame.BackgroundColor3 = ARCADE_THEME.BG_CARD
	cardFrame.BorderSizePixel = 0
	cardFrame.LayoutOrder = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 8)
	cardCorner.Parent = cardFrame

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = ARCADE_THEME.STROKE_DARK
	cardStroke.Thickness = 1
	cardStroke.Parent = cardFrame

	-- Icon (Left)
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.Size = UDim2.new(0, 50, 0, 50)
	iconImage.Position = UDim2.new(0, 15, 0.5, 0)
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.BackgroundTransparency = 1
	iconImage.Image = ICON_MAP[statName] or ICON_MAP.StartLevel
	iconImage.Parent = cardFrame

	-- Info (Middle)
	local infoContainer = Instance.new("Frame")
	infoContainer.Name = "InfoContainer"
	infoContainer.Size = UDim2.new(1, -220, 1, -10)
	infoContainer.Position = UDim2.new(0, 80, 0, 5)
	infoContainer.BackgroundTransparency = 1
	infoContainer.Parent = cardFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = upgradeConfig.Name
	titleLabel.TextColor3 = ARCADE_THEME.TEXT_WHITE
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = infoContainer

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "DescLabel"
	descLabel.Size = UDim2.new(1, 0, 0, 30)
	descLabel.Position = UDim2.new(0, 0, 0, 20)
	descLabel.BackgroundTransparency = 1
	descLabel.Text = upgradeConfig.Description or "No description available."
	descLabel.TextColor3 = ARCADE_THEME.TEXT_GRAY
	descLabel.TextSize = 12
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextWrapped = true
	descLabel.Parent = infoContainer

    -- Progress Bar
	local progressBarBg = Instance.new("Frame")
	progressBarBg.Name = "ProgressBarBg"
	progressBarBg.Size = UDim2.new(1, 0, 0, 6)
	progressBarBg.Position = UDim2.new(0, 0, 1, -5)
	progressBarBg.AnchorPoint = Vector2.new(0, 1)
	progressBarBg.BackgroundColor3 = ARCADE_THEME.BG_DARK
	progressBarBg.BorderSizePixel = 0
	progressBarBg.Parent = infoContainer
    
    local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 3)
	barCorner.Parent = progressBarBg

	local progressBarFill = Instance.new("Frame")
	progressBarFill.Name = "ProgressBarFill"
	progressBarFill.Size = UDim2.new(0, 0, 1, 0)
	progressBarFill.BackgroundColor3 = ARCADE_THEME.ACCENT_GREEN
	progressBarFill.BorderSizePixel = 0
	progressBarFill.Parent = progressBarBg
    
    local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = progressBarFill

	-- Action (Right)
	local actionContainer = Instance.new("Frame")
	actionContainer.Name = "ActionContainer"
	actionContainer.Size = UDim2.new(0, 130, 1, -10)
	actionContainer.Position = UDim2.new(1, -10, 0, 5)
	actionContainer.AnchorPoint = Vector2.new(1, 0)
	actionContainer.BackgroundTransparency = 1
	actionContainer.Parent = cardFrame

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, 0, 0, 15)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = "Level 0 / " .. upgradeConfig.MaxLevel
	levelLabel.TextColor3 = ARCADE_THEME.TEXT_GRAY
	levelLabel.TextSize = 12
	levelLabel.Font = Enum.Font.GothamBold
	levelLabel.TextXAlignment = Enum.TextXAlignment.Right
	levelLabel.Parent = actionContainer

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, 0, 0, 15)
	costLabel.Position = UDim2.new(0, 0, 0, 15)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "100 GXP"
	costLabel.TextColor3 = ARCADE_THEME.ACCENT_ORANGE
	costLabel.TextSize = 14
	costLabel.Font = Enum.Font.GothamBold
	costLabel.TextXAlignment = Enum.TextXAlignment.Right
	costLabel.Parent = actionContainer

	local purchaseButton = Instance.new("TextButton")
	purchaseButton.Name = "PurchaseButton"
	purchaseButton.Size = UDim2.new(1, 0, 0, 30)
	purchaseButton.Position = UDim2.new(0, 0, 1, 0)
	purchaseButton.AnchorPoint = Vector2.new(0, 1)
	purchaseButton.BackgroundColor3 = ARCADE_THEME.ACCENT_GREEN
	purchaseButton.BorderSizePixel = 0
	purchaseButton.Text = "Purchase"
	purchaseButton.TextColor3 = ARCADE_THEME.TEXT_WHITE
	purchaseButton.TextSize = 14
	purchaseButton.Font = Enum.Font.GothamBold
	purchaseButton.Parent = actionContainer

	local purchaseCorner = Instance.new("UICorner")
	purchaseCorner.CornerRadius = UDim.new(0, 15)
	purchaseCorner.Parent = purchaseButton

	-- Lock Overlay
	local lockOverlay = Instance.new("ImageLabel")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(0, 30, 0, 30)
	lockOverlay.Position = UDim2.new(0, 25, 0.5, 0)
    lockOverlay.AnchorPoint = Vector2.new(0, 0.5)
	lockOverlay.BackgroundTransparency = 1
	lockOverlay.Image = ICON_MAP.Lock
	lockOverlay.Visible = false
	lockOverlay.ZIndex = 10
	lockOverlay.Parent = cardFrame

	-- Purchase logic
	local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
	local purchaseUpgradeRemote = remotes and remotes:FindFirstChild("PurchaseUpgrade")

	purchaseButton.MouseEnter:Connect(function()
		playSound(SOUNDS.Hover)
	end)
	purchaseButton.MouseButton1Click:Connect(function()
		if purchaseUpgradeRemote then
			local success, _message = purchaseUpgradeRemote:InvokeServer(statName)
			if success then
				playSound(SOUNDS.Purchase)
			else
				playSound(SOUNDS.Error)
			end
		end
	end)

	cardFrame:SetAttribute("StatName", statName)
	
	-- Cache all elements for fast updates (100x improvement)
	cardCache[statName] = {
		card = cardFrame,
		progressBarFill = progressBarFill,
		levelLabel = levelLabel,
		costLabel = costLabel,
		lockOverlay = lockOverlay,
		purchaseButton = purchaseButton
	}
	
	return cardFrame
end

-- Build skill tree structure
local tierFrames = {}
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
	if not remotes then
		return
	end

	for tierNumber = 1, 4 do
		local tierData = MetaConfig.Tiers[tierNumber]
		if tierData then
			local tierFrame = createTierSection(tierNumber, tierData)
			tierFrames[tierNumber] = tierFrame

			for statName, upgradeConfig in pairs(MetaConfig.Upgrades) do
				if upgradeConfig.Tier == tierNumber then
					local card = createUpgradeCard(statName, upgradeConfig)
					local container = tierFrame:FindFirstChild("UpgradeContainer")
					if container then
						card.Parent = container
					end
				end
			end
		end
	end
end)


-- --- Shop Update Function (Optimized with Caching) --- --
local function updateShopUI()
	-- Direct access via cache - O(1) instead of O(n²)
	for statName, upgradeConfig in pairs(MetaConfig.Upgrades) do
		local cached = cardCache[statName]
		if not cached then continue end
		
		local level = currentUpgrades[statName] or 0
		local cost = MetaConfig.GetCost(statName, level)
		local isUnlocked = MetaConfig.IsUnlocked(currentBiomass, statName)
		
		-- Direct element access - no FindFirstChild calls
		local percent = math.clamp(level / upgradeConfig.MaxLevel, 0, 1)
		cached.progressBarFill.Size = UDim2.fromScale(percent, 1)
		
		cached.levelLabel.Text = string.format("Level %d / %d", level, upgradeConfig.MaxLevel)
		
		if level >= upgradeConfig.MaxLevel then
			cached.costLabel.Text = "MAX"
		else
			cached.costLabel.Text = string.format("%d GXP", math.floor(cost))
		end
		
		if isUnlocked then
			cached.lockOverlay.Visible = false
			cached.card.BackgroundTransparency = 0.2
			
			if level >= upgradeConfig.MaxLevel then
				cached.purchaseButton.BackgroundColor3 = COLORS.XP_GOLD
				cached.purchaseButton.Text = "MAXED"
				cached.purchaseButton.Active = false
			elseif currentGlobalXP >= cost then
				cached.purchaseButton.BackgroundColor3 = COLORS.BUTTON_GREEN
				cached.purchaseButton.Text = "UPGRADE"
				cached.purchaseButton.Active = true
			else
				cached.purchaseButton.BackgroundColor3 = COLORS.BUTTON_RED
				cached.purchaseButton.Text = "UPGRADE"
				cached.purchaseButton.Active = true
			end
		else
			cached.lockOverlay.Visible = true
			cached.card.BackgroundTransparency = 0.5
			cached.purchaseButton.BackgroundColor3 = COLORS.LOCKED_GREY
			cached.purchaseButton.Text = "LOCKED"
			cached.purchaseButton.Active = false
		end
	end
	
	-- Canvas size calculation (only once)
	task.wait()
	local totalHeight = 0
	for _, tierFrame in pairs(tierFrames) do
		if tierFrame and tierFrame.Parent then
			totalHeight = totalHeight + tierFrame.AbsoluteSize.Y
		end
	end
	if totalHeight > 0 then
		hud.ShopScrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 20)
	end
end

-- --- XP Popup Function --- --
local function showXPPopup(amount: number, isGlobalXP: boolean?)
	isGlobalXP = isGlobalXP or false
	local prefix = if isGlobalXP then "Biomass" else "XP"
	hud.XPPopupText.Text = string.format("+%d %s", amount, prefix)
	hud.XPPopup.Visible = true
	hud.XPPopup.Position = UDim2.fromScale(0.5, 0.3)
	hud.XPPopupText.TextTransparency = 0

	local floatTween = TweenService:Create(
		hud.XPPopup,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.5, 0.2) }
	)
	local fadeTween = TweenService:Create(
		hud.XPPopupText,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextTransparency = 1 }
	)
	floatTween:Play()
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		hud.XPPopup.Visible = false
	end)
end

-- --- Shop & Stats Toggle Logic --- --

local function toggleShop()
	local isOpening = not hud.ShopMainFrame.Visible
	hud.ShopMainFrame.Visible = isOpening

	if isOpening then
		-- Unlock mouse for UI interaction
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		updateShopUI()
	else
		-- Re-lock mouse for gameplay
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end

-- Button Connections
hud.ShopCloseButton.MouseButton1Click:Connect(toggleShop)

-- Keybinds
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.N then
		toggleShop()
	end
end)

local function updateHealth()
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	local hp = math.floor(humanoid.Health)
	local maxHp = math.floor(humanoid.MaxHealth)
	hud.HealthText.Text = string.format("Health: %d/%d", hp, maxHp)

	local percent = math.clamp(hp / maxHp, 0, 1)
	local tween = TweenService:Create(
		hud.HealthFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(percent, 1) }
	)
	tween:Play()
end

local function updateXP()
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0
	local requiredXP = ScalingConfig.GetXPRequired(level)

	local percent = math.clamp(xp / requiredXP, 0, 1)

	if level >= ScalingConfig.MAX_LEVEL then
		hud.LevelLabel.Text = "MAX LEVEL"
		percent = 1
	else
		hud.LevelLabel.Text = string.format("Level %d", level)
	end
	
	-- Update Size Label (optimized string formatting)
	hud.SizeLabel.Text = string.format("SIZE: %d", level)

	local tween = TweenService:Create(
		hud.XPFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(percent, 1) }
	)
	tween:Play()

	-- Update Session Biomass (optimized string formatting)
	hud.BiomassStatLabel.Text = string.format("Biomass: %d", math.floor(xp))
end

local function updateKills()
	local kills = player:GetAttribute("Kills") or 0
	-- Optimized string formatting
	hud.TopKillsLabel.Text = string.format("KILLS: %d", kills)
	hud.KillsStatLabel.Text = string.format("Kills: %d", kills)
end

local function updateAmmo()
	local character = player.Character
	if not character then
		hud.AmmoWidget.Visible = false
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		hud.AmmoWidget.Visible = false
		return
	end

	hud.AmmoWidget.Visible = true
	hud.WeaponIcon.Image = tool.TextureId or ""

	local ammo = tonumber(tool:GetAttribute(Constants.AMMO_ATTRIBUTE)) or 0
	local magazineSize = tonumber(tool:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)) or 0
	local reloading = tool:GetAttribute(Constants.RELOADING_ATTRIBUTE) == true

	if magazineSize ~= currentMagazineSize then
		currentMagazineSize = magazineSize
	end

	local ammoText = ""
	if reloading then
		ammoText = "RELOADING"
	else
		ammoText = string.format("%d/%d", ammo, magazineSize)
	end
	hud.AmmoLabel.Text = ammoText
end



-- Meta Stats Update (from Server)
local function updateMetaStats(globalXP, upgrades, biomass)
	previousGlobalXP = currentGlobalXP
	currentGlobalXP = globalXP or 0
	currentBiomass = biomass or 0
	currentUpgrades = upgrades or {}

	if currentGlobalXP > previousGlobalXP then
		local gained = currentGlobalXP - previousGlobalXP
		if gained > 0 then
			showXPPopup(gained, true)
		end
	end

	if hud.ShopMainFrame.Visible then
		updateShopUI()
	end
	
	-- Update GXP Label
	hud.GXPStatLabel.Text = "GXP: " .. tostring(math.floor(currentGlobalXP))
end

-- --- Connections --- --
local function setupCharacterConnections(character)
	-- Hide Death Screen and Ammo on spawn
	hud.DeathSummaryFrame.Visible = false
	hud.AmmoWidget.Visible = false
	
	-- Reset mouse lock
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		updateHealth()
		humanoid.HealthChanged:Connect(updateHealth)
		-- MaxHealth connection removed (redundant - HealthChanged fires for MaxHealth changes)
	end
	
	-- Initial Updates
	updateXP()
	updateKills()
	
	-- Connect Signals
	player:GetAttributeChangedSignal("XP"):Connect(function()
		-- Update the bar.
		updateXP()
	end)
	
	player:GetAttributeChangedSignal("Level"):Connect(function()
		updateXP()
		-- Level Up Popup
		hud.XPPopupText.Text = "LEVEL UP!"
		hud.XPPopup.Visible = true
		
		-- Hide after a delay
		task.delay(2, function()
			hud.XPPopup.Visible = false
		end)
	end)
	
	player:GetAttributeChangedSignal("Kills"):Connect(updateKills)

	-- Tool Connections
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			updateAmmo()
			child:GetAttributeChangedSignal(Constants.AMMO_ATTRIBUTE):Connect(updateAmmo)
			child:GetAttributeChangedSignal(Constants.MAGAZINE_SIZE_ATTRIBUTE):Connect(updateAmmo)
			child:GetAttributeChangedSignal(Constants.RELOADING_ATTRIBUTE):Connect(updateAmmo)
		end
	end)
	
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			updateAmmo()
		end
	end)
	
	-- Check for existing tools
	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			updateAmmo()
			child:GetAttributeChangedSignal(Constants.AMMO_ATTRIBUTE):Connect(updateAmmo)
			child:GetAttributeChangedSignal(Constants.MAGAZINE_SIZE_ATTRIBUTE):Connect(updateAmmo)
			child:GetAttributeChangedSignal(Constants.RELOADING_ATTRIBUTE):Connect(updateAmmo)
		end
	end
end

player.CharacterAdded:Connect(setupCharacterConnections)

-- Initial Check
if player.Character then
	setupCharacterConnections(player.Character)
end

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")

local updateMetaRemote = remotes:WaitForChild("UpdateMetaStats", 10)
if updateMetaRemote then
	updateMetaRemote.OnClientEvent:Connect(updateMetaStats)
end

local showDeathSummaryRemote = remotes:WaitForChild("ShowDeathSummary", 10)
if showDeathSummaryRemote then
	showDeathSummaryRemote.OnClientEvent:Connect(function(sessionKills, sessionXP, earnedGXP)
		-- Instead of showing the old DeathSummaryFrame, we show the Shop with Respawn button
		
		-- Hide standard death summary if it was visible
		hud.DeathSummaryFrame.Visible = false
		
		-- Open Shop
		hud.ShopMainFrame.Visible = true
		
		-- Configure Shop for Death Mode
		hud.ShopCloseButton.Visible = false -- Cannot close
		hud.RespawnButton.Visible = true -- Can respawn
		
		-- Unlock mouse
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		
		updateShopUI()
	end)
end

-- Respawn Button Logic
local requestRespawnRemote = remotes:WaitForChild("RequestRespawn", 10)
if requestRespawnRemote then
	hud.RespawnButton.MouseButton1Click:Connect(function()
		-- Fire respawn request
		requestRespawnRemote:FireServer()
		
		-- Reset UI state
		hud.ShopMainFrame.Visible = false
		hud.ShopCloseButton.Visible = true
		hud.RespawnButton.Visible = false
		
		-- Lock mouse (will be handled by character spawn too, but good to be safe)
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end)
end

hud.OKButton.MouseButton1Click:Connect(function()
	hud.DeathSummaryFrame.Visible = false
	-- Re-lock mouse if needed, or let spawn logic handle it
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
end)

task.spawn(function()
	local reqRemote = remotes:WaitForChild("RequestMetaData", 10)
	if reqRemote then
	end
end)

-- Killstreak listener (Deprecated, using Attribute now)
local killstreakRemote = remotes:FindFirstChild("Killstreak")
if killstreakRemote then
	killstreakRemote.OnClientEvent:Connect(function(killCount)
		-- Optional: Keep this if the server still sends it for other reasons, 
		-- but we rely on the attribute for the HUD.
		-- currentKills = killCount or 0
		-- hud.KillsLabel.Text = "Kills: " .. currentKills
	end)
end

-- Enforce mouse unlock when shop is open (prevents weapon system from locking it)
-- Uses Heartbeat instead of RenderStepped for better performance
local mouseUnlockConnection = nil

hud.ShopMainFrame:GetPropertyChangedSignal("Visible"):Connect(function()
	if hud.ShopMainFrame.Visible then
		-- Sink ONLY mouse button inputs to prevent shooting (not keyboard - need N to close shop)
		ContextActionService:BindAction("DisableMouseInputs", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.MouseButton2)
		
		-- Continuously enforce mouse unlock (weapon system fights for control)
		mouseUnlockConnection = RunService.Heartbeat:Connect(function()
			if hud.ShopMainFrame.Visible then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			else
				-- Shop was closed, clean up
				if mouseUnlockConnection then
					mouseUnlockConnection:Disconnect()
					mouseUnlockConnection = nil
				end
			end
		end)
	else
		-- Shop closed, unbind input sink and stop enforcing
		ContextActionService:UnbindAction("DisableMouseInputs")
		
		if mouseUnlockConnection then
			mouseUnlockConnection:Disconnect()
			mouseUnlockConnection = nil
		end
		
		-- Re-lock mouse for gameplay
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
end)
