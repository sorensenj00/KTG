local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local InputCategorizer = require(ReplicatedStorage.Blaster.Scripts.InputCategorizer)
local MetaConfig = require(ReplicatedStorage.GameLoop.MetaConfig)
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

local function bindButtonSounds(btn, isPurchase)
	btn.MouseEnter:Connect(function()
		playSound(SOUNDS.Hover)
	end)
	if not isPurchase then
		btn.MouseButton1Click:Connect(function()
			playSound(SOUNDS.Click)
		end)
	end
end

-- --- RuneScape & UI Color Constants --- --
local COLORS = {
	-- Original Colors
	HEALTH_GREEN = Color3.fromRGB(0, 255, 100),
	HEALTH_BLUE = Color3.fromRGB(100, 150, 255),
	XP_ORANGE = Color3.fromRGB(255, 170, 0),
	XP_GOLD = Color3.fromRGB(255, 215, 0),
	BUTTON_GREEN = Color3.fromRGB(50, 150, 50),
	BUTTON_RED = Color3.fromRGB(150, 50, 50),
	TEXT_WHITE = Color3.fromRGB(255, 255, 255),
	LOCKED_GREY = Color3.fromRGB(100, 100, 100),
}

local RS_THEME = {
	PANEL_BROWN = Color3.fromRGB(62, 53, 41), -- Main UI Background
	PANEL_BORDER = Color3.fromRGB(90, 80, 65), -- Bevel Highlight
	SLOT_BG = Color3.fromRGB(25, 20, 15), -- The black box behind skills
	TEXT_YELLOW = Color3.fromRGB(255, 255, 0), -- Classic RS Stat Text
	TEXT_ORANGE = Color3.fromRGB(255, 152, 31), -- RS Header Text
	HOVER_GLOW = Color3.fromRGB(255, 255, 255),
}

-- --- Icon Map --- --
local ICON_MAP = {
	Health = "rbxassetid://7169354151", -- White Shield
	Damage = "rbxassetid://10468915", -- Classic Sword
	Speed = "rbxassetid://1234752", -- Sonic/Speed
	Ammo = "rbxassetid://11563251", -- Bomb/Ammo
	Vampirism = "rbxassetid://6238815272",
	ExplosiveDeath = "rbxassetid://11563251",
	StartLevel = "rbxasset://textures/ui/GuiImagePlaceholder.png",
	Lock = "rbxassetid://10700326032",
	Stats = "rbxassetid://15264359039", -- Bar Graph Icon
	Biomass = "rbxassetid://7493638708", -- DNA/Biomass Icon
}

-- --- State --- --
local currentGlobalXP = 0
local previousGlobalXP = 0
local currentBiomass = 0
local currentUpgrades = {}
local previousXP = 0
local previousLevel = 1
local currentKills = 0

-- --- UI Creation --- --

local function createHUD()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PlayerHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 5
	screenGui.Enabled = true
	screenGui.Parent = playerGui

	-- ============================================
	-- 1. Health Bar (Bottom Left)
	-- ============================================
	local healthFrame = Instance.new("Frame")
	healthFrame.Name = "HealthFrame"
	healthFrame.Size = UDim2.fromOffset(250, 45)
	healthFrame.Position = UDim2.fromScale(0.02, 0.95)
	healthFrame.AnchorPoint = Vector2.new(0, 1)
	healthFrame.BackgroundColor3 = RS_THEME.SLOT_BG
	healthFrame.BorderSizePixel = 0
	healthFrame.Parent = screenGui

	local healthStroke = Instance.new("UIStroke")
	healthStroke.Color = RS_THEME.PANEL_BORDER
	healthStroke.Thickness = 2
	healthStroke.Parent = healthFrame

	local healthFill = Instance.new("Frame")
	healthFill.Name = "Fill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = COLORS.HEALTH_GREEN
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthFrame

	local healthGradient = Instance.new("UIGradient")
	healthGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.HEALTH_GREEN),
		ColorSequenceKeypoint.new(1, COLORS.HEALTH_BLUE),
	})
	healthGradient.Parent = healthFill
	healthFill.BackgroundTransparency = 0.1

	local healthText = Instance.new("TextLabel")
	healthText.Name = "ValueText"
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.Text = "100 / 100"
	healthText.TextColor3 = RS_THEME.TEXT_YELLOW
	healthText.TextSize = 18
	healthText.Font = Enum.Font.GothamBold
	healthText.TextStrokeTransparency = 0
	healthText.TextStrokeColor3 = Color3.new(0, 0, 0)
	healthText.Parent = healthFrame

	-- ============================================
	-- 1b. XP Bar (Below Health Bar)
	-- ============================================
	local xpFrame = Instance.new("Frame")
	xpFrame.Name = "XPFrame"
	xpFrame.Size = UDim2.fromOffset(250, 30)
	xpFrame.Position = UDim2.fromScale(0.02, 0.89)
	xpFrame.AnchorPoint = Vector2.new(0, 1)
	xpFrame.BackgroundColor3 = RS_THEME.SLOT_BG
	xpFrame.BorderSizePixel = 0
	xpFrame.Parent = screenGui

	local xpStroke = Instance.new("UIStroke")
	xpStroke.Color = RS_THEME.PANEL_BORDER
	xpStroke.Thickness = 2
	xpStroke.Parent = xpFrame

	local xpFill = Instance.new("Frame")
	xpFill.Name = "Fill"
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = COLORS.XP_ORANGE
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpFrame

	local xpText = Instance.new("TextLabel")
	xpText.Name = "ValueText"
	xpText.Size = UDim2.fromScale(1, 1)
	xpText.BackgroundTransparency = 1
	xpText.Text = "Level 1"
	xpText.TextColor3 = RS_THEME.TEXT_ORANGE
	xpText.TextSize = 14
	xpText.Font = Enum.Font.GothamBold
	xpText.TextStrokeTransparency = 0.5
	xpText.TextStrokeColor3 = Color3.new(0, 0, 0)
	xpText.Parent = xpFrame

	-- ============================================
	-- 2. Stats & Shop Buttons (Top Left)
	-- ============================================

	-- The "Stats" Button (Chart Icon)
	local statsOpenButton = Instance.new("ImageButton")
	statsOpenButton.Name = "StatsOpenButton"
	statsOpenButton.Size = UDim2.fromOffset(50, 50)
	statsOpenButton.Position = UDim2.fromOffset(20, 20)
	statsOpenButton.BackgroundColor3 = RS_THEME.PANEL_BROWN
	statsOpenButton.BorderSizePixel = 2
	statsOpenButton.BorderColor3 = RS_THEME.PANEL_BORDER
	statsOpenButton.Image = ICON_MAP.Stats
	statsOpenButton.ScaleType = Enum.ScaleType.Fit
	statsOpenButton.ImageColor3 = RS_THEME.TEXT_ORANGE
	statsOpenButton.Parent = screenGui

	local statsBtnStroke = Instance.new("UIStroke")
	statsBtnStroke.Thickness = 2
	statsBtnStroke.Color = Color3.fromRGB(30, 30, 30)
	statsBtnStroke.Parent = statsOpenButton

	bindButtonSounds(statsOpenButton, false)

	-- The "Shop" Button (Skill Tree)
	local shopButton = Instance.new("TextButton")
	shopButton.Name = "ShopButton"
	shopButton.Size = UDim2.fromOffset(120, 50)
	shopButton.Position = UDim2.fromOffset(80, 20)
	shopButton.BackgroundColor3 = RS_THEME.PANEL_BROWN
	shopButton.BorderSizePixel = 0
	shopButton.Text = "SKILL TREE"
	shopButton.TextColor3 = RS_THEME.TEXT_YELLOW
	shopButton.TextSize = 16
	shopButton.Font = Enum.Font.GothamBold
	shopButton.TextStrokeTransparency = 0.5
	shopButton.TextStrokeColor3 = Color3.new(0, 0, 0)
	shopButton.Parent = screenGui

	local shopCorner = Instance.new("UICorner")
	shopCorner.CornerRadius = UDim.new(0, 6)
	shopCorner.Parent = shopButton

	local shopStroke = Instance.new("UIStroke")
	shopStroke.Color = RS_THEME.PANEL_BORDER
	shopStroke.Thickness = 2
	shopStroke.Parent = shopButton

	bindButtonSounds(shopButton, false)

	-- ============================================
	-- 2b. Kills Panel (Top Right)
	-- ============================================
	local killsPanel = Instance.new("Frame")
	killsPanel.Name = "KillsPanel"
	killsPanel.Size = UDim2.fromOffset(150, 40)
	killsPanel.Position = UDim2.fromScale(0.98, 0.02)
	killsPanel.AnchorPoint = Vector2.new(1, 0)
	killsPanel.BackgroundColor3 = RS_THEME.SLOT_BG
	killsPanel.BorderSizePixel = 0
	killsPanel.Parent = screenGui

	local killsStroke = Instance.new("UIStroke")
	killsStroke.Color = RS_THEME.PANEL_BORDER
	killsStroke.Thickness = 2
	killsStroke.Parent = killsPanel

	local killsLabel = Instance.new("TextLabel")
	killsLabel.Name = "KillsLabel"
	killsLabel.Size = UDim2.new(1, 0, 1, 0)
	killsLabel.BackgroundTransparency = 1
	killsLabel.Text = "Kills: 0"
	killsLabel.TextColor3 = RS_THEME.TEXT_ORANGE
	killsLabel.TextSize = 18
	killsLabel.Font = Enum.Font.GothamBold
	killsLabel.TextStrokeTransparency = 0.5
	killsLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	killsLabel.Parent = killsPanel

	-- ============================================
	-- 3. Ammo Display
	-- ============================================
	local ammoPanel = Instance.new("Frame")
	ammoPanel.Name = "AmmoPanel"
	ammoPanel.Size = UDim2.fromOffset(200, 80)
	ammoPanel.AnchorPoint = Vector2.new(1, 1)
	ammoPanel.BackgroundColor3 = RS_THEME.SLOT_BG
	ammoPanel.BackgroundTransparency = 0.2
	ammoPanel.BorderSizePixel = 0
	ammoPanel.ZIndex = 10
	ammoPanel.Parent = screenGui

	local ammoStroke = Instance.new("UIStroke")
	ammoStroke.Color = RS_THEME.PANEL_BORDER
	ammoStroke.Thickness = 2
	ammoStroke.Parent = ammoPanel

	local ammoUIScale = Instance.new("UIScale")
	ammoUIScale.Parent = ammoPanel

	local weaponIcon = Instance.new("ImageLabel")
	weaponIcon.Name = "WeaponIcon"
	weaponIcon.Size = UDim2.fromOffset(40, 40)
	weaponIcon.Position = UDim2.fromOffset(10, 10)
	weaponIcon.BackgroundTransparency = 1
	weaponIcon.Image = ""
	weaponIcon.Parent = ammoPanel

	local ammoContainer = Instance.new("Frame")
	ammoContainer.Name = "AmmoContainer"
	ammoContainer.Size = UDim2.new(1, -60, 1, -20)
	ammoContainer.Position = UDim2.fromOffset(60, 10)
	ammoContainer.BackgroundTransparency = 1
	ammoContainer.Parent = ammoPanel

	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Name = "AmmoLabel"
	ammoLabel.Size = UDim2.fromScale(1, 0.6)
	ammoLabel.Position = UDim2.fromScale(0, 0)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.Text = "000 / 00"
	ammoLabel.TextColor3 = RS_THEME.TEXT_YELLOW
	ammoLabel.TextSize = 28
	ammoLabel.Font = Enum.Font.GothamBold
	ammoLabel.TextStrokeTransparency = 0.5
	ammoLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Left
	ammoLabel.RichText = true
	ammoLabel.Parent = ammoContainer

	local magazineLabel = Instance.new("TextLabel")
	magazineLabel.Name = "MagazineLabel"
	magazineLabel.Size = UDim2.fromScale(1, 0.4)
	magazineLabel.Position = UDim2.fromScale(0, 0.6)
	magazineLabel.BackgroundTransparency = 1
	magazineLabel.Text = "/ 00"
	magazineLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	magazineLabel.TextSize = 16
	magazineLabel.Font = Enum.Font.Gotham
	magazineLabel.TextStrokeTransparency = 0.5
	magazineLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	magazineLabel.TextXAlignment = Enum.TextXAlignment.Left
	magazineLabel.Parent = ammoContainer

	-- ============================================
	-- 4. XP Popup
	-- ============================================
	local xpPopupFrame = Instance.new("Frame")
	xpPopupFrame.Name = "XPPopup"
	xpPopupFrame.Size = UDim2.fromOffset(300, 100)
	xpPopupFrame.Position = UDim2.fromScale(0.5, 0.3)
	xpPopupFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	xpPopupFrame.BackgroundTransparency = 1
	xpPopupFrame.Visible = false
	xpPopupFrame.Parent = screenGui

	local xpPopupText = Instance.new("TextLabel")
	xpPopupText.Name = "Text"
	xpPopupText.Size = UDim2.fromScale(1, 1)
	xpPopupText.BackgroundTransparency = 1
	xpPopupText.Text = "+0 GXP"
	xpPopupText.TextColor3 = COLORS.XP_GOLD
	xpPopupText.TextSize = 32
	xpPopupText.Font = Enum.Font.GothamBold
	xpPopupText.TextStrokeTransparency = 0.3
	xpPopupText.TextStrokeColor3 = Color3.new(0, 0, 0)
	xpPopupText.Parent = xpPopupFrame

	-- ============================================
	-- 4b. Death Summary Frame
	-- ============================================
	local deathSummaryFrame = Instance.new("Frame")
	deathSummaryFrame.Name = "DeathSummaryFrame"
	deathSummaryFrame.Size = UDim2.fromOffset(400, 250)
	deathSummaryFrame.Position = UDim2.fromScale(0.5, 0.5)
	deathSummaryFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	deathSummaryFrame.BackgroundColor3 = RS_THEME.PANEL_BROWN
	deathSummaryFrame.BorderSizePixel = 0
	deathSummaryFrame.Visible = false
	deathSummaryFrame.ZIndex = 100
	deathSummaryFrame.Parent = screenGui

	local deathStroke = Instance.new("UIStroke")
	deathStroke.Color = RS_THEME.PANEL_BORDER
	deathStroke.Thickness = 4
	deathStroke.Parent = deathSummaryFrame

	local deathTitle = Instance.new("TextLabel")
	deathTitle.Name = "Title"
	deathTitle.Size = UDim2.new(1, -20, 0, 50)
	deathTitle.Position = UDim2.fromOffset(10, 10)
	deathTitle.BackgroundTransparency = 1
	deathTitle.Text = "YOU DIED"
	deathTitle.TextColor3 = Color3.fromRGB(255, 50, 50)
	deathTitle.TextSize = 36
	deathTitle.Font = Enum.Font.GothamBold
	deathTitle.TextStrokeTransparency = 0.3
	deathTitle.TextStrokeColor3 = Color3.new(0, 0, 0)
	deathTitle.Parent = deathSummaryFrame

	-- Kills Label
	local killsStatLabel = Instance.new("TextLabel")
	killsStatLabel.Name = "KillsLabel"
	killsStatLabel.Size = UDim2.new(1, -20, 0, 30)
	killsStatLabel.Position = UDim2.fromOffset(10, 70)
	killsStatLabel.BackgroundTransparency = 1
	killsStatLabel.Text = "Kills: 0"
	killsStatLabel.TextColor3 = COLORS.TEXT_WHITE
	killsStatLabel.TextSize = 20
	killsStatLabel.Font = Enum.Font.GothamBold
	killsStatLabel.TextStrokeTransparency = 0.5
	killsStatLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	killsStatLabel.TextXAlignment = Enum.TextXAlignment.Left
	killsStatLabel.Parent = deathSummaryFrame

	-- Session XP Label
	local sessionXPLabel = Instance.new("TextLabel")
	sessionXPLabel.Name = "SessionXPLabel"
	sessionXPLabel.Size = UDim2.new(1, -20, 0, 30)
	sessionXPLabel.Position = UDim2.fromOffset(10, 105)
	sessionXPLabel.BackgroundTransparency = 1
	sessionXPLabel.Text = "Session XP: 0"
	sessionXPLabel.TextColor3 = COLORS.TEXT_WHITE
	sessionXPLabel.TextSize = 20
	sessionXPLabel.Font = Enum.Font.GothamBold
	sessionXPLabel.TextStrokeTransparency = 0.5
	sessionXPLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	sessionXPLabel.TextXAlignment = Enum.TextXAlignment.Left
	sessionXPLabel.Parent = deathSummaryFrame

	-- Earned GXP Label
	local earnedGXPLabel = Instance.new("TextLabel")
	earnedGXPLabel.Name = "EarnedGXPLabel"
	earnedGXPLabel.Size = UDim2.new(1, -20, 0, 50)
	earnedGXPLabel.Position = UDim2.fromOffset(10, 145)
	earnedGXPLabel.BackgroundTransparency = 1
	earnedGXPLabel.Text = "Earned: +0 Global XP"
	earnedGXPLabel.TextColor3 = RS_THEME.TEXT_YELLOW
	earnedGXPLabel.TextSize = 28
	earnedGXPLabel.Font = Enum.Font.GothamBold
	earnedGXPLabel.TextStrokeTransparency = 0.3
	earnedGXPLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	earnedGXPLabel.TextXAlignment = Enum.TextXAlignment.Center
	earnedGXPLabel.Parent = deathSummaryFrame

	-- OK Button
	local okButton = Instance.new("TextButton")
	okButton.Name = "OKButton"
	okButton.Size = UDim2.fromOffset(100, 35)
	okButton.Position = UDim2.fromOffset(200, 210)
	okButton.AnchorPoint = Vector2.new(0.5, 0)
	okButton.BackgroundColor3 = RS_THEME.SLOT_BG
	okButton.BorderSizePixel = 0
	okButton.Text = "OK"
	okButton.TextColor3 = COLORS.TEXT_WHITE
	okButton.TextSize = 18
	okButton.Font = Enum.Font.GothamBold
	okButton.Parent = deathSummaryFrame

	local okButtonStroke = Instance.new("UIStroke")
	okButtonStroke.Color = RS_THEME.PANEL_BORDER
	okButtonStroke.Thickness = 2
	okButtonStroke.Parent = okButton

	-- ============================================
	-- 5. Skill Tree Shop GUI
	-- ============================================
	local shopScreenGui = Instance.new("ScreenGui")
	shopScreenGui.Name = "SkillTreeGui"
	shopScreenGui.ResetOnSpawn = false
	shopScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	shopScreenGui.DisplayOrder = 20
	shopScreenGui.Parent = playerGui

	local shopMainFrame = Instance.new("Frame")
	shopMainFrame.Name = "MainFrame"
	shopMainFrame.Size = UDim2.new(0, 800, 0, 600)
	shopMainFrame.Position = UDim2.new(0.5, -400, 0.5, -300)
	shopMainFrame.BackgroundColor3 = RS_THEME.PANEL_BROWN
	shopMainFrame.BorderSizePixel = 0
	shopMainFrame.Visible = false
	shopMainFrame.Parent = shopScreenGui

	local shopMainStroke = Instance.new("UIStroke")
	shopMainStroke.Color = RS_THEME.PANEL_BORDER
	shopMainStroke.Thickness = 3
	shopMainStroke.Parent = shopMainFrame

	local shopTitle = Instance.new("TextLabel")
	shopTitle.Name = "Title"
	shopTitle.Size = UDim2.new(1, 0, 0, 50)
	shopTitle.Position = UDim2.new(0, 0, 0, 0)
	shopTitle.BackgroundColor3 = Color3.new(0, 0, 0)
	shopTitle.BackgroundTransparency = 0.5
	shopTitle.BorderSizePixel = 0
	shopTitle.Text = "SKILL TREE"
	shopTitle.TextColor3 = RS_THEME.TEXT_ORANGE
	shopTitle.TextSize = 24
	shopTitle.Font = Enum.Font.GothamBold
	shopTitle.Parent = shopMainFrame

	local shopCloseButton = Instance.new("TextButton")
	shopCloseButton.Name = "CloseButton"
	shopCloseButton.Size = UDim2.new(0, 40, 0, 40)
	shopCloseButton.Position = UDim2.new(1, -45, 0, 5)
	shopCloseButton.BackgroundColor3 = COLORS.BUTTON_RED
	shopCloseButton.BorderSizePixel = 0
	shopCloseButton.Text = "X"
	shopCloseButton.TextColor3 = COLORS.TEXT_WHITE
	shopCloseButton.TextSize = 20
	shopCloseButton.Font = Enum.Font.GothamBold
	shopCloseButton.Parent = shopMainFrame

	local shopCloseCorner = Instance.new("UICorner")
	shopCloseCorner.CornerRadius = UDim.new(0.2, 0)
	shopCloseCorner.Parent = shopCloseButton

	bindButtonSounds(shopCloseButton, false)

	local shopScrollFrame = Instance.new("ScrollingFrame")
	shopScrollFrame.Name = "ScrollFrame"
	shopScrollFrame.Size = UDim2.new(1, -20, 1, -70)
	shopScrollFrame.Position = UDim2.new(0, 10, 0, 60)
	shopScrollFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	shopScrollFrame.BackgroundTransparency = 0.5
	shopScrollFrame.BorderSizePixel = 0
	shopScrollFrame.ScrollBarThickness = 8
	shopScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	shopScrollFrame.Parent = shopMainFrame

	local shopTierListLayout = Instance.new("UIListLayout")
	shopTierListLayout.Padding = UDim.new(0, 20)
	shopTierListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	shopTierListLayout.Parent = shopScrollFrame

	-- ============================================
	-- 6. Stats Board GUI (RuneScape Style)
	-- ============================================
	local statsBoardScreenGui = Instance.new("ScreenGui")
	statsBoardScreenGui.Name = "StatsBoardGui"
	statsBoardScreenGui.ResetOnSpawn = false
	statsBoardScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	statsBoardScreenGui.DisplayOrder = 25
	statsBoardScreenGui.Parent = playerGui

	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "StatsFrame"
	statsFrame.Size = UDim2.new(0, 400, 0, 500) -- Taller, narrower like RS menu
	statsFrame.Position = UDim2.new(0.5, -200, 0.5, -250)
	statsFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	statsFrame.BackgroundColor3 = RS_THEME.PANEL_BROWN
	statsFrame.BorderSizePixel = 0
	statsFrame.Visible = false
	statsFrame.Parent = statsBoardScreenGui

	local statsFrameStroke = Instance.new("UIStroke")
	statsFrameStroke.Color = RS_THEME.PANEL_BORDER
	statsFrameStroke.Thickness = 3
	statsFrameStroke.Parent = statsFrame

	-- Title
	local statsTitle = Instance.new("TextLabel")
	statsTitle.Name = "Title"
	statsTitle.Size = UDim2.new(1, 0, 0, 40)
	statsTitle.BackgroundTransparency = 1
	statsTitle.Text = "STATS"
	statsTitle.TextColor3 = RS_THEME.TEXT_ORANGE
	statsTitle.TextSize = 24
	statsTitle.Font = Enum.Font.GothamBold
	statsTitle.Parent = statsFrame

	-- Close Button
	local statsCloseButton = Instance.new("TextButton")
	statsCloseButton.Name = "CloseButton"
	statsCloseButton.Size = UDim2.new(0, 30, 0, 30)
	statsCloseButton.Position = UDim2.new(1, -35, 0, 5)
	statsCloseButton.BackgroundColor3 = COLORS.BUTTON_RED
	statsCloseButton.BorderSizePixel = 0
	statsCloseButton.Text = "X"
	statsCloseButton.TextColor3 = COLORS.TEXT_WHITE
	statsCloseButton.TextSize = 16
	statsCloseButton.Font = Enum.Font.GothamBold
	statsCloseButton.Parent = statsFrame

	bindButtonSounds(statsCloseButton, false)

	-- The Skills Grid Container
	local skillsContainer = Instance.new("Frame")
	skillsContainer.Name = "SkillsContainer"
	skillsContainer.Size = UDim2.new(1, -20, 1, -50)
	skillsContainer.Position = UDim2.new(0, 10, 0, 45)
	skillsContainer.BackgroundTransparency = 1
	skillsContainer.Parent = statsFrame

	local skillsGrid = Instance.new("UIGridLayout")
	skillsGrid.CellSize = UDim2.new(0, 120, 0, 40) -- Rectangle boxes like RS
	skillsGrid.CellPadding = UDim2.new(0, 5, 0, 5)
	skillsGrid.FillDirection = Enum.FillDirection.Horizontal
	skillsGrid.SortOrder = Enum.SortOrder.LayoutOrder
	skillsGrid.Parent = skillsContainer

	-- Function to create RS-style Skill Box
	local function createSkillBox(name, iconId, layoutOrder, associatedStatKey)
		-- Change Frame to ImageButton for clickability
		local box = Instance.new("ImageButton")
		box.Name = name .. "Box"
		box.BackgroundColor3 = RS_THEME.SLOT_BG
		box.BorderSizePixel = 0
		box.LayoutOrder = layoutOrder
		box.AutoButtonColor = false -- We handle colors manually
		box.Parent = skillsContainer

		-- Store the stat key (e.g., "Damage", "Health") for logic
		if associatedStatKey then
			box:SetAttribute("StatKey", associatedStatKey)
		end

		-- Add Stroke for status indication (Green/Red/Gold)
		local stroke = Instance.new("UIStroke")
		stroke.Name = "StatusStroke"
		stroke.Color = RS_THEME.PANEL_BORDER
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = box

		-- Icon on Left
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.Size = UDim2.new(0, 30, 0, 30)
		icon.Position = UDim2.new(0, 5, 0.5, 0)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image = iconId
		icon.Parent = box

		-- Value Text
		local valueText = Instance.new("TextLabel")
		valueText.Name = "Value"
		valueText.Size = UDim2.new(1, -5, 1, 0)
		valueText.Position = UDim2.new(0, -5, 0, 0)
		valueText.BackgroundTransparency = 1
		valueText.Text = "1"
		valueText.TextColor3 = RS_THEME.TEXT_YELLOW
		valueText.TextSize = 16
		valueText.Font = Enum.Font.GothamBold
		valueText.TextXAlignment = Enum.TextXAlignment.Right
		valueText.Parent = box

		-- Tooltip
		local tooltip = Instance.new("TextLabel")
		tooltip.Name = "Tooltip"
		tooltip.Size = UDim2.new(2, 0, 0, 40) -- Slightly taller for cost info
		tooltip.Position = UDim2.new(0, 0, -1.1, 0)
		tooltip.BackgroundColor3 = Color3.new(0.1, 0.1, 0.1)
		tooltip.TextColor3 = Color3.new(1, 1, 1)
		tooltip.Text = name
		tooltip.ZIndex = 20
		tooltip.Visible = false
		tooltip.Font = Enum.Font.Gotham
		tooltip.TextSize = 12
		tooltip.Parent = box

		-- Add Padding to Tooltip
		local uip = Instance.new("UIPadding")
		uip.PaddingBottom = UDim.new(0, 4)
		uip.PaddingTop = UDim.new(0, 4)
		uip.PaddingLeft = UDim.new(0, 4)
		uip.PaddingRight = UDim.new(0, 4)
		uip.Parent = tooltip

		-- Rounded Tooltip
		local uic = Instance.new("UICorner")
		uic.Parent = tooltip

		-- Hover Logic
		box.MouseEnter:Connect(function()
			tooltip.Visible = true
			-- Slight lighten effect
			if box.AutoButtonColor == false then
				box.BackgroundColor3 = Color3.fromRGB(45, 40, 35)
			end
			playSound(SOUNDS.Hover)
		end)

		box.MouseLeave:Connect(function()
			tooltip.Visible = false
			box.BackgroundColor3 = RS_THEME.SLOT_BG
		end)

		-- Purchase Logic
		if associatedStatKey then
			box.MouseButton1Click:Connect(function()
				local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
				local purchaseUpgradeRemote = remotes and remotes:FindFirstChild("PurchaseUpgrade")

				if purchaseUpgradeRemote then
					-- Validate locally first for instant feedback (optional, but feels better)
					local upgradeConfig = MetaConfig.Upgrades[associatedStatKey]
					local currentLevel = currentUpgrades[associatedStatKey] or 0
					local cost = MetaConfig.GetCost(associatedStatKey, currentLevel)
					local unlocked = MetaConfig.IsUnlocked(currentBiomass, associatedStatKey)

					if unlocked and currentGlobalXP >= cost and currentLevel < upgradeConfig.MaxLevel then
						local success, _ = purchaseUpgradeRemote:InvokeServer(associatedStatKey)
						if success then
							playSound(SOUNDS.Purchase)
							-- Visuals will update automatically via the update loop
						else
							playSound(SOUNDS.Error)
						end
					else
						playSound(SOUNDS.Error)
					end
				end
			end)
		end

		return valueText
	end

	-- Create the Boxes (Order matters for grid)
	-- Row 1
	local metaBiomassValue = createSkillBox("Biomass", ICON_MAP.Biomass, 1, nil) -- Biomass is not purchasable (it's rank)
	local metaGlobalXPValue = createSkillBox("Global XP", ICON_MAP.Stats, 2, nil) -- GXP is a currency, not purchasable
	local sessionKillsValue = createSkillBox("Kills", ICON_MAP.Damage, 3, nil) -- Kills is a stat

	-- Row 2 (Combat stats - These ARE purchasable)
	local metaDamageMultValue = createSkillBox("Damage", ICON_MAP.Damage, 4, "Damage")
	local metaHealthMultValue = createSkillBox("Health", ICON_MAP.Health, 5, "Health")
	local metaSpeedMultValue = createSkillBox("Speed", ICON_MAP.Speed, 6, "Speed")

	-- Row 3 (Utility)
	local metaAmmoValue = createSkillBox("Ammo", ICON_MAP.Ammo, 7, "Ammo")
	local sessionLevelValue = createSkillBox("Level", ICON_MAP.StartLevel, 8, nil)
	local sessionWalkSpeedValue = createSkillBox("WalkSpeed", ICON_MAP.Speed, 9, nil)

	return {
		ScreenGui = screenGui,
		HealthFill = healthFill,
		HealthText = healthText,
		HealthGradient = healthGradient,
		XPFrame = xpFrame,
		XPFill = xpFill,
		XPText = xpText,
		StatsOpenButton = statsOpenButton,
		ShopButton = shopButton,
		AmmoPanel = ammoPanel,
		AmmoLabel = ammoLabel,
		MagazineLabel = magazineLabel,
		WeaponIcon = weaponIcon,
		AmmoUIScale = ammoUIScale,
		XPPopup = xpPopupFrame,
		XPPopupText = xpPopupText,
		ShopScreenGui = shopScreenGui,
		ShopMainFrame = shopMainFrame,
		ShopCloseButton = shopCloseButton,
		ShopScrollFrame = shopScrollFrame,
		ShopTierListLayout = shopTierListLayout,
		KillsPanel = killsPanel,
		KillsLabel = killsLabel,
		DeathSummaryFrame = deathSummaryFrame,
		DeathTitle = deathTitle,
		KillsStatLabel = killsStatLabel,
		SessionXPLabel = sessionXPLabel,
		EarnedGXPLabel = earnedGXPLabel,
		OKButton = okButton,
		StatsBoardScreenGui = statsBoardScreenGui,
		StatsFrame = statsFrame,
		StatsCloseButton = statsCloseButton,
		SessionLevelValue = sessionLevelValue,
		SessionWalkSpeedValue = sessionWalkSpeedValue,
		SessionKillsValue = sessionKillsValue,
		MetaBiomassValue = metaBiomassValue,
		MetaGlobalXPValue = metaGlobalXPValue,
		MetaDamageMultValue = metaDamageMultValue,
		MetaHealthMultValue = metaHealthMultValue,
		MetaSpeedMultValue = metaSpeedMultValue,
		MetaAmmoValue = metaAmmoValue,
	}
end

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

	local tierNameLabel = Instance.new("TextLabel")
	tierNameLabel.Name = "TierName"
	tierNameLabel.Size = UDim2.new(1, -20, 1, 0)
	tierNameLabel.Position = UDim2.new(0, 10, 0, 0)
	tierNameLabel.BackgroundTransparency = 1
	tierNameLabel.Text = tierData.Name .. " (Req: " .. tierData.UnlockBiomass .. " Bio)"
	tierNameLabel.TextColor3 = COLORS.TEXT_WHITE
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
	upgradeListLayout.Padding = UDim.new(0, 5)
	upgradeListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	upgradeListLayout.Parent = upgradeContainer

	return tierFrame
end

-- Create upgrade card
local function createUpgradeCard(statName: string, upgradeConfig: any)
	local cardFrame = Instance.new("Frame")
	cardFrame.Name = statName .. "Card"
	cardFrame.Size = UDim2.new(1, 0, 0, 80)
	cardFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	cardFrame.BackgroundTransparency = 0.2
	cardFrame.BorderSizePixel = 0
	cardFrame.LayoutOrder = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = cardFrame

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(80, 80, 90)
	cardStroke.Thickness = 1
	cardStroke.Parent = cardFrame

	-- Left Column: Icon
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.Size = UDim2.new(0, 50, 0, 50)
	iconImage.Position = UDim2.new(0, 15, 0.5, 0)
	iconImage.AnchorPoint = Vector2.new(0, 0.5)
	iconImage.BackgroundTransparency = 1
	iconImage.Image = ICON_MAP[statName] or ICON_MAP.StartLevel
	iconImage.Parent = cardFrame

	-- Middle Column: Info
	local infoContainer = Instance.new("Frame")
	infoContainer.Name = "InfoContainer"
	infoContainer.Size = UDim2.new(0, 300, 1, -10)
	infoContainer.Position = UDim2.new(0, 80, 0, 5)
	infoContainer.BackgroundTransparency = 1
	infoContainer.Parent = cardFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 24)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = upgradeConfig.Name
	titleLabel.TextColor3 = COLORS.TEXT_WHITE
	titleLabel.TextSize = 18
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = infoContainer

	local progressBarBg = Instance.new("Frame")
	progressBarBg.Name = "ProgressBarBg"
	progressBarBg.Size = UDim2.new(1, 0, 0, 6)
	progressBarBg.Position = UDim2.new(0, 0, 1, -10)
	progressBarBg.AnchorPoint = Vector2.new(0, 1)
	progressBarBg.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
	progressBarBg.BorderSizePixel = 0
	progressBarBg.Parent = infoContainer

	local progressBarFill = Instance.new("Frame")
	progressBarFill.Name = "ProgressBarFill"
	progressBarFill.Size = UDim2.new(0, 0, 1, 0)
	progressBarFill.BackgroundColor3 = COLORS.HEALTH_BLUE
	progressBarFill.BorderSizePixel = 0
	progressBarFill.Parent = progressBarBg

	-- Right Column: Action
	local actionContainer = Instance.new("Frame")
	actionContainer.Name = "ActionContainer"
	actionContainer.Size = UDim2.new(0, 150, 1, -10)
	actionContainer.Position = UDim2.new(1, -10, 0, 5)
	actionContainer.AnchorPoint = Vector2.new(1, 0)
	actionContainer.BackgroundTransparency = 1
	actionContainer.Parent = cardFrame

	local costLabel = Instance.new("TextLabel")
	costLabel.Name = "CostLabel"
	costLabel.Size = UDim2.new(1, 0, 0, 20)
	costLabel.BackgroundTransparency = 1
	costLabel.Text = "100 GXP"
	costLabel.TextColor3 = COLORS.XP_GOLD
	costLabel.TextSize = 14
	costLabel.Font = Enum.Font.Gotham
	costLabel.TextXAlignment = Enum.TextXAlignment.Right
	costLabel.Parent = actionContainer

	local purchaseButton = Instance.new("TextButton")
	purchaseButton.Name = "PurchaseButton"
	purchaseButton.Size = UDim2.new(1, 0, 0, 30)
	purchaseButton.Position = UDim2.new(0, 0, 1, -30)
	purchaseButton.AnchorPoint = Vector2.new(0, 1)
	purchaseButton.BackgroundColor3 = COLORS.BUTTON_GREEN
	purchaseButton.BorderSizePixel = 0
	purchaseButton.Text = "Purchase"
	purchaseButton.TextColor3 = COLORS.TEXT_WHITE
	purchaseButton.TextSize = 14
	purchaseButton.Font = Enum.Font.GothamBold
	purchaseButton.Parent = actionContainer

	local purchaseCorner = Instance.new("UICorner")
	purchaseCorner.CornerRadius = UDim.new(0, 4)
	purchaseCorner.Parent = purchaseButton

	-- Lock Overlay
	local lockOverlay = Instance.new("ImageLabel")
	lockOverlay.Name = "LockOverlay"
	lockOverlay.Size = UDim2.new(0, 40, 0, 40)
	lockOverlay.Position = UDim2.new(0, 20, 0.5, -20)
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
			local success, message = purchaseUpgradeRemote:InvokeServer(statName)
			if success then
				playSound(SOUNDS.Purchase)
			else
				playSound(SOUNDS.Error)
			end
		end
	end)

	cardFrame:SetAttribute("StatName", statName)
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

-- --- Shop Update Function --- --
local function updateShopUI()
	for tierNumber, tierFrame in pairs(tierFrames) do
		local container = tierFrame:FindFirstChild("UpgradeContainer")
		if container then
			for _, card in ipairs(container:GetChildren()) do
				if card:IsA("Frame") and card.Name:match("Card$") then
					local statName = card:GetAttribute("StatName")
					if statName and MetaConfig.Upgrades[statName] then
						local upgradeConfig = MetaConfig.Upgrades[statName]
						local level = currentUpgrades[statName] or 0
						local cost = MetaConfig.GetCost(statName, level)
						local isUnlocked = MetaConfig.IsUnlocked(currentBiomass, statName)

						local infoContainer = card:FindFirstChild("InfoContainer")
						if infoContainer then
							local progressBarBg = infoContainer:FindFirstChild("ProgressBarBg")
							if progressBarBg then
								local progressBarFill = progressBarBg:FindFirstChild("ProgressBarFill")
								if progressBarFill then
									local percent = math.clamp(level / upgradeConfig.MaxLevel, 0, 1)
									progressBarFill.Size = UDim2.fromScale(percent, 1)
								end
							end
						end

						local actionContainer = card:FindFirstChild("ActionContainer")
						if actionContainer then
							local costLabel = actionContainer:FindFirstChild("CostLabel")
							if costLabel then
								if level >= upgradeConfig.MaxLevel then
									costLabel.Text = "MAX"
								else
									costLabel.Text = string.format("%d GXP", math.floor(cost))
								end
							end
						end

						local lockOverlay = card:FindFirstChild("LockOverlay")
						local purchaseButton = card:FindFirstChild("PurchaseButton")

						if isUnlocked then
							if lockOverlay then
								lockOverlay.Visible = false
							end
							card.BackgroundTransparency = 0.2

							if purchaseButton then
								if level >= upgradeConfig.MaxLevel then
									purchaseButton.BackgroundColor3 = COLORS.XP_GOLD
									purchaseButton.Text = "MAXED"
									purchaseButton.Active = false
								elseif currentGlobalXP >= cost then
									purchaseButton.BackgroundColor3 = COLORS.BUTTON_GREEN
									purchaseButton.Text = "UPGRADE"
									purchaseButton.Active = true
								else
									purchaseButton.BackgroundColor3 = COLORS.BUTTON_RED
									purchaseButton.Text = "UPGRADE"
									purchaseButton.Active = true
								end
							end
						else
							if lockOverlay then
								lockOverlay.Visible = true
							end
							card.BackgroundTransparency = 0.5
							if purchaseButton then
								purchaseButton.BackgroundColor3 = COLORS.LOCKED_GREY
								purchaseButton.Text = "LOCKED"
								purchaseButton.Active = false
							end
						end
					end
				end
			end
		end
	end

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
	local prefix = if isGlobalXP then "GXP" else "XP"
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
	hud.StatsFrame.Visible = false -- Close stats if shop opens

	UserInputService.MouseIconEnabled = isOpening
	if isOpening then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		updateShopUI()
	else
		-- Reset if in first person
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

local function toggleStatsBoard()
	local isOpening = not hud.StatsFrame.Visible
	hud.StatsFrame.Visible = isOpening
	hud.ShopMainFrame.Visible = false -- Close shop if stats opens

	UserInputService.MouseIconEnabled = isOpening
	if isOpening then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		-- Trigger an update immediately
		hud.StatsFrame:SetAttribute("Refresh", os.time())
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	end
end

-- Button Connections
hud.ShopButton.MouseButton1Click:Connect(toggleShop)
hud.ShopCloseButton.MouseButton1Click:Connect(toggleShop)
hud.StatsOpenButton.MouseButton1Click:Connect(toggleStatsBoard)
hud.StatsCloseButton.MouseButton1Click:Connect(toggleStatsBoard)

-- Keybinds
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.M then
		toggleShop()
	elseif input.KeyCode == Enum.KeyCode.Tab then
		toggleStatsBoard()
	end
end)

-- --- Ammo Display Logic --- --
local currentMagazineSize = 0
local leadingZeros = 0
local AMMO_TEXT_FORMAT_STRING = `<font transparency="0.5">%s</font>%s`

local function updateAmmoPanelPosition()
	local lastInputCategory = InputCategorizer.getLastInputCategory()
	if lastInputCategory == InputCategorizer.InputCategory.Touch then
		hud.AmmoPanel.AnchorPoint = Vector2.new(0.5, 1)
		hud.AmmoPanel.Position = UDim2.new(0.5, 0, 1, -65)
	else
		hud.AmmoPanel.AnchorPoint = Vector2.new(1, 1)
		hud.AmmoPanel.Position = UDim2.new(1, -10, 1, -10)
	end
end

local function updateAmmoPanelScale()
	local minScreenSize = math.min(hud.ScreenGui.AbsoluteSize.X, hud.ScreenGui.AbsoluteSize.Y)
	local isSmallScreen = minScreenSize < Constants.UI_SMALL_SCREEN_THRESHOLD
	hud.AmmoUIScale.Scale = if isSmallScreen then Constants.UI_SMALL_SCREEN_SCALE else 1
end

hud.AmmoPanel.Visible = false
updateAmmoPanelPosition()
updateAmmoPanelScale()

InputCategorizer.lastInputCategoryChanged:Connect(updateAmmoPanelPosition)
hud.ScreenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateAmmoPanelScale)

-- --- Updates --- --
local function updateHealth()
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		return
	end

	local hp = math.floor(humanoid.Health)
	local maxHp = math.floor(humanoid.MaxHealth)
	hud.HealthText.Text = string.format("%d / %d", hp, maxHp)

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
		hud.XPText.Text = "Max Level"
		percent = 1
	else
		hud.XPText.Text = string.format("Level %d", level)
	end

	local tween = TweenService:Create(
		hud.XPFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(percent, 1) }
	)
	tween:Play()
end

local function updateAmmo()
	local character = player.Character
	if not character then
		hud.AmmoPanel.Visible = false
		return
	end

	local tool = character:FindFirstChildOfClass("Tool")
	if not tool then
		hud.AmmoPanel.Visible = false
		return
	end

	hud.AmmoPanel.Visible = true
	hud.WeaponIcon.Image = tool.TextureId or ""

	local ammo = tonumber(tool:GetAttribute(Constants.AMMO_ATTRIBUTE)) or 0
	local magazineSize = tonumber(tool:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)) or 0
	local reloading = tool:GetAttribute(Constants.RELOADING_ATTRIBUTE) == true

	if magazineSize ~= currentMagazineSize then
		currentMagazineSize = magazineSize
		leadingZeros = #tostring(magazineSize)
	end
	hud.MagazineLabel.Text = string.format("/ %d", magazineSize)

	local zeroText = ""
	local ammoText = ""
	if reloading then
		zeroText = string.rep("-", leadingZeros)
	else
		ammoText = tostring(ammo)
		local numZeros = leadingZeros - #ammoText
		if numZeros > 0 then
			zeroText = string.rep("0", numZeros)
		end
	end
	hud.AmmoLabel.Text = string.format(AMMO_TEXT_FORMAT_STRING, zeroText, ammoText)
end

-- --- Stats Board Content Update --- --
-- Helper to update upgradable boxes
local function updateUpgradeableBox(textLabel, statKey, level, multiplier)
	local box = textLabel.Parent
	local stroke = box:FindFirstChild("StatusStroke")
	local tooltip = box:FindFirstChild("Tooltip")

	if not stroke or not tooltip then
		return
	end

	local config = MetaConfig.Upgrades[statKey]
	if not config then
		return
	end

	local cost = MetaConfig.GetCost(statKey, level)
	local isUnlocked = MetaConfig.IsUnlocked(currentBiomass, statKey)
	local nextMultiplier = MetaConfig.GetMultiplier(statKey, level + 1)

	-- Update text label to show level (not multiplier)
	textLabel.Text = tostring(level)

	-- Logic for Colors and Tooltip
	if level >= config.MaxLevel then
		-- MAXED STATE
		stroke.Color = COLORS.XP_GOLD -- Gold Border
		stroke.Thickness = 2
		tooltip.Text = string.format("%s\nMAX LEVEL\nCurrent: x%.2f", config.Name, multiplier)
	elseif not isUnlocked then
		-- LOCKED STATE
		stroke.Color = RS_THEME.PANEL_BORDER -- Brown/Grey Border
		stroke.Thickness = 2
		tooltip.Text =
			string.format("%s (LOCKED)\nReq: %d Biomass", config.Name, MetaConfig.Tiers[config.Tier].UnlockBiomass)
	elseif currentGlobalXP >= cost then
		-- AFFORDABLE STATE (Call to action!)
		stroke.Color = COLORS.HEALTH_GREEN -- Bright Green Border
		stroke.Thickness = 3 -- Thicker to draw attention
		tooltip.Text = string.format(
			"%s\nCost: %d GXP\nCurrent: x%.2f\nNext: x%.2f",
			config.Name,
			math.floor(cost),
			multiplier,
			nextMultiplier
		)
	else
		-- CANT AFFORD STATE
		stroke.Color = COLORS.BUTTON_RED -- Red Border
		stroke.Thickness = 2
		tooltip.Text = string.format("%s\nCost: %d GXP\n(Not enough GXP)", config.Name, math.floor(cost))
	end
end

local function updateStatsBoardContent()
	if not hud.StatsFrame.Visible then
		return
	end

	-- 1. Biomass & GXP (Standard updates)
	hud.MetaBiomassValue.Text = tostring(math.floor(currentBiomass))
	hud.MetaBiomassValue.Parent.Tooltip.Text = "Biomass: " .. tostring(math.floor(currentBiomass))

	hud.MetaGlobalXPValue.Text = tostring(math.floor(currentGlobalXP))
	hud.MetaGlobalXPValue.Parent.Tooltip.Text = "Total Global XP: " .. tostring(math.floor(currentGlobalXP))

	hud.SessionKillsValue.Text = tostring(currentKills)
	hud.SessionKillsValue.Parent.Tooltip.Text = "Current Life Kills: " .. tostring(currentKills)

	-- 2. Upgradable Stats (Use the helper)
	local damageLevel = (currentUpgrades["Damage"] or 0)
	local damageMult = MetaConfig.GetMultiplier("Damage", damageLevel)
	updateUpgradeableBox(hud.MetaDamageMultValue, "Damage", damageLevel, damageMult)

	local healthLevel = (currentUpgrades["Health"] or 0)
	local healthMult = MetaConfig.GetMultiplier("Health", healthLevel)
	updateUpgradeableBox(hud.MetaHealthMultValue, "Health", healthLevel, healthMult)

	local speedLevel = (currentUpgrades["Speed"] or 0)
	local speedMult = MetaConfig.GetMultiplier("Speed", speedLevel)
	updateUpgradeableBox(hud.MetaSpeedMultValue, "Speed", speedLevel, speedMult)

	local ammoLevel = (currentUpgrades["Ammo"] or 0)
	local ammoMult = MetaConfig.GetMultiplier("Ammo", ammoLevel)
	updateUpgradeableBox(hud.MetaAmmoValue, "Ammo", ammoLevel, ammoMult)

	-- 3. Session Stats
	local level = player:GetAttribute("Level") or 1
	hud.SessionLevelValue.Text = tostring(level)
	hud.SessionLevelValue.Parent.Tooltip.Text = "Current Level: " .. tostring(level)

	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid")
	local ws = hum and math.floor(hum.WalkSpeed) or 16
	hud.SessionWalkSpeedValue.Text = tostring(ws)
	hud.SessionWalkSpeedValue.Parent.Tooltip.Text = "Actual WalkSpeed: " .. tostring(ws)
end

-- Refresh stats signal
hud.StatsFrame:GetAttributeChangedSignal("Refresh"):Connect(updateStatsBoardContent)

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
	if hud.StatsFrame.Visible then
		updateStatsBoardContent()
	end
end

-- --- Connections --- --
player.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid then
		updateHealth()
		humanoid.HealthChanged:Connect(updateHealth)
		humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(updateHealth)
	end

	-- Tool Connections
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			updateAmmo()
			child:GetAttributeChangedSignal(Constants.AMMO_ATTRIBUTE):Connect(updateAmmo)
			child:GetAttributeChangedSignal(Constants.MAGAZINE_SIZE_ATTRIBUTE):Connect(updateAmmo)
			child:GetAttributeChangedSignal(Constants.RELOADING_ATTRIBUTE):Connect(updateAmmo)
		end
	end)
end)

-- Initial Check
if player.Character then
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if humanoid then
		updateHealth()
		humanoid.HealthChanged:Connect(updateHealth)
	end
	for _, child in ipairs(player.Character:GetChildren()) do
		if child:IsA("Tool") then
			updateAmmo()
			child:GetAttributeChangedSignal(Constants.AMMO_ATTRIBUTE):Connect(updateAmmo)
		end
	end
end

-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")

local updateMetaRemote = remotes:WaitForChild("UpdateMetaStats", 10)
if updateMetaRemote then
	updateMetaRemote.OnClientEvent:Connect(updateMetaStats)
end

task.spawn(function()
	local reqRemote = remotes:WaitForChild("RequestMetaData", 10)
	if reqRemote then
		local s, res = pcall(function()
			return { reqRemote:InvokeServer() }
		end)
		if s and res then
			updateMetaStats(res[1], res[2], res[3])
		end
	end
end)

-- Loops
task.spawn(function()
	while true do
		task.wait(0.2)
		if player.Character then
			local curXP = player:GetAttribute("XP") or 0
			local curLevel = player:GetAttribute("Level") or 1
			updateXP()

			if curLevel > previousLevel then
				hud.XPPopupText.Text = "LEVEL UP!"
				hud.XPPopup.Visible = true
				previousLevel = curLevel
			elseif curXP > previousXP then
				showXPPopup(curXP - previousXP, false)
				previousXP = curXP
			end

			if hud.StatsFrame.Visible then
				updateStatsBoardContent()
			end
		end
	end
end)

-- Killstreak listener
local killstreakRemote = remotes:FindFirstChild("Killstreak")
if killstreakRemote then
	killstreakRemote.OnClientEvent:Connect(function(killCount)
		currentKills = killCount or 0
		hud.KillsLabel.Text = "Kills: " .. currentKills
		if hud.StatsFrame.Visible then
			updateStatsBoardContent()
		end
	end)
end
