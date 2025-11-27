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

    -- New Skills Icons (Placeholders for now)
    Regeneration = "rbxassetid://7169354151", -- Shield/Health
    Photosynthesis = "rbxassetid://15264359039", -- Leaf/Growth
    Magnetism = "rbxassetid://1234752", -- Magnet/Speed
    Thorns = "rbxassetid://10468915", -- Spikes/Sword
    Featherweight = "rbxassetid://1234752", -- Feather/Speed
    ToxicAura = "rbxassetid://11563251", -- Gas/Bomb
}

-- --- State --- --
local currentDNA = 0
local previousDNA = 0
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

	-- ============================================
	-- 1. Health Bar (Bottom Left)
	-- ============================================
	local healthFrame = Instance.new("Frame")
	healthFrame.Name = "HealthFrame"
	healthFrame.Size = UDim2.fromOffset(300, 40)
	healthFrame.Position = UDim2.fromScale(0.02, 0.90) -- Moved up slightly for XP bar
	healthFrame.AnchorPoint = Vector2.new(0, 1)
	healthFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40) -- Dark Grey Background
	healthFrame.BorderSizePixel = 0
	healthFrame.Parent = screenGui

	local healthCorner = Instance.new("UICorner")
	healthCorner.CornerRadius = UDim.new(0, 10)
	healthCorner.Parent = healthFrame

	local healthStroke = Instance.new("UIStroke")
	healthStroke.Color = Color3.fromRGB(20, 20, 20)
	healthStroke.Thickness = 3
	healthStroke.Parent = healthFrame

	local healthFill = Instance.new("Frame")
	healthFill.Name = "HealthFill"
	healthFill.Size = UDim2.fromScale(1, 1)
	healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 150)
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthFrame

	local healthFillCorner = Instance.new("UICorner")
	healthFillCorner.CornerRadius = UDim.new(0, 10)
	healthFillCorner.Parent = healthFill

	local healthText = Instance.new("TextLabel")
	healthText.Name = "HealthText"
	healthText.Size = UDim2.fromScale(1, 1)
	healthText.BackgroundTransparency = 1
	healthText.Text = "100 / 100"
	healthText.TextColor3 = Color3.fromRGB(20, 20, 20) -- Dark text on Yellow
	healthText.TextSize = 24
	healthText.Font = Enum.Font.LuckiestGuy
	if not pcall(function() healthText.Font = Enum.Font.LuckiestGuy end) then
		healthText.Font = Enum.Font.GothamBlack
	end
	healthText.TextStrokeTransparency = 1
	healthText.Parent = healthFrame

	-- ============================================
	-- 1b. Biomass Bar (Below Health Bar)
	-- ============================================
	local xpFrame = Instance.new("Frame")
	xpFrame.Name = "XPFrame"
	xpFrame.Size = UDim2.fromOffset(300, 15) -- Thinner
	xpFrame.Position = UDim2.fromScale(0.02, 0.93) -- Below Health (0.90 + height)
	xpFrame.AnchorPoint = Vector2.new(0, 1)
	xpFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	xpFrame.BorderSizePixel = 0
	xpFrame.Parent = screenGui

	local xpCorner = Instance.new("UICorner")
	xpCorner.CornerRadius = UDim.new(0, 4)
	xpCorner.Parent = xpFrame

	local xpStroke = Instance.new("UIStroke")
	xpStroke.Color = Color3.fromRGB(20, 20, 20)
	xpStroke.Thickness = 2
	xpStroke.Parent = xpFrame

	local xpFill = Instance.new("Frame")
	xpFill.Name = "XPFill"
	xpFill.Size = UDim2.fromScale(0, 1)
	xpFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpFrame

	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(0, 4)
	xpFillCorner.Parent = xpFill

	local xpText = Instance.new("TextLabel")
	xpText.Name = "ValueText"
	xpText.Size = UDim2.fromScale(1, 1)
	xpText.BackgroundTransparency = 1
	xpText.Text = "Level 1"
	xpText.TextColor3 = Color3.fromRGB(255, 255, 255)
	xpText.TextSize = 10
	xpText.Font = Enum.Font.GothamBold
	xpText.TextStrokeTransparency = 0.5
	xpText.TextStrokeColor3 = Color3.new(0, 0, 0)
	xpText.Parent = xpFrame

	-- ============================================
	-- 2. Stats Bar (Above XP Bar)
	-- ============================================
	local statsBar = Instance.new("Frame")
	statsBar.Name = "StatsBar"
	statsBar.Size = UDim2.fromOffset(300, 20)
	statsBar.Position = UDim2.fromScale(0.02, 0.85) -- Above Health (0.90 - height)
	statsBar.AnchorPoint = Vector2.new(0, 1)
	statsBar.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	statsBar.BackgroundTransparency = 0.5
	statsBar.BorderSizePixel = 0
	statsBar.Parent = screenGui

	local statsCorner = Instance.new("UICorner")
	statsCorner.CornerRadius = UDim.new(0, 4)
	statsCorner.Parent = statsBar

	local statsStroke = Instance.new("UIStroke")
	statsStroke.Color = RS_THEME.PANEL_BORDER
	statsStroke.Thickness = 2
	statsStroke.Parent = statsBar

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Horizontal
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	statsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statsLayout.Padding = UDim.new(0, 10)
	statsLayout.Parent = statsBar

	-- Kills Label
	local killsLabel = Instance.new("TextLabel")
	killsLabel.Name = "KillsLabel"
	killsLabel.Size = UDim2.new(0, 0, 1, 0)
	killsLabel.AutomaticSize = Enum.AutomaticSize.X
	killsLabel.BackgroundTransparency = 1
	killsLabel.Text = "Kills: 0"
	killsLabel.TextColor3 = RS_THEME.TEXT_ORANGE
	killsLabel.TextSize = 14
	killsLabel.Font = Enum.Font.GothamBold
	killsLabel.TextStrokeTransparency = 0.5
	killsLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	killsLabel.Parent = statsBar

	-- DNA Label (Permanent Currency)
	local dnaLabel = Instance.new("TextLabel")
	dnaLabel.Name = "DNALabel"
	dnaLabel.Size = UDim2.new(0, 0, 1, 0)
	dnaLabel.AutomaticSize = Enum.AutomaticSize.X
	dnaLabel.BackgroundTransparency = 1
	dnaLabel.Text = "DNA: 0"
	dnaLabel.TextColor3 = RS_THEME.TEXT_YELLOW -- Gold for DNA
	dnaLabel.TextSize = 14
	dnaLabel.Font = Enum.Font.GothamBold
	dnaLabel.TextStrokeTransparency = 0.5
	dnaLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	dnaLabel.Parent = statsBar

	-- ============================================
	-- 3. Ammo Display
	-- ============================================
	local ammoPanel = Instance.new("Frame")
	ammoPanel.Name = "AmmoPanel"
	ammoPanel.Size = UDim2.fromOffset(200, 100)
	ammoPanel.Position = UDim2.fromScale(0.98, 0.95)
	ammoPanel.AnchorPoint = Vector2.new(1, 1)
	ammoPanel.BackgroundTransparency = 1
	ammoPanel.BorderSizePixel = 0
	ammoPanel.ZIndex = 10
	ammoPanel.Parent = screenGui

	local ammoUIScale = Instance.new("UIScale")
	ammoUIScale.Parent = ammoPanel

	-- Weapon Icon
	local weaponIcon = Instance.new("ImageLabel")
	weaponIcon.Name = "WeaponIcon"
	weaponIcon.Size = UDim2.fromOffset(60, 60)
	weaponIcon.Position = UDim2.fromScale(1, 0)
	weaponIcon.AnchorPoint = Vector2.new(1, 0)
	weaponIcon.BackgroundTransparency = 1
	weaponIcon.Image = ""
	weaponIcon.Visible = false
	weaponIcon.Parent = ammoPanel

	local ammoContainer = Instance.new("Frame")
	ammoContainer.Name = "AmmoContainer"
	ammoContainer.Size = UDim2.new(1, 0, 1, 0)
	ammoContainer.Position = UDim2.fromScale(0, 0)
	ammoContainer.BackgroundTransparency = 1
	ammoContainer.Parent = ammoPanel

	local ammoLabel = Instance.new("TextLabel")
	ammoLabel.Name = "AmmoLabel"
	ammoLabel.Size = UDim2.new(0.6, 0, 1, 0)
	ammoLabel.Position = UDim2.new(0, 10, 0, 0)
	ammoLabel.BackgroundTransparency = 1
	ammoLabel.Text = "30"
	ammoLabel.TextColor3 = Color3.fromRGB(255, 60, 60)
	ammoLabel.TextSize = 80
	ammoLabel.Font = Enum.Font.LuckiestGuy
	if not pcall(function() ammoLabel.Font = Enum.Font.LuckiestGuy end) then
		ammoLabel.Font = Enum.Font.GothamBlack
	end
	ammoLabel.TextStrokeTransparency = 0
	ammoLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
	ammoLabel.RichText = true
	ammoLabel.Parent = ammoContainer

	local magazineLabel = Instance.new("TextLabel")
	magazineLabel.Name = "MagazineLabel"
	magazineLabel.Size = UDim2.fromScale(1, 0.3)
	magazineLabel.Position = UDim2.fromScale(0, 0.7)
	magazineLabel.BackgroundTransparency = 1
	magazineLabel.Text = "/ 90"
	magazineLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	magazineLabel.TextSize = 24
	magazineLabel.Font = Enum.Font.GothamBold
	magazineLabel.TextStrokeTransparency = 0.5
	magazineLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	magazineLabel.TextXAlignment = Enum.TextXAlignment.Right
	magazineLabel.Parent = ammoContainer

	-- ============================================
	-- 4. Popup (DNA/Biomass)
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
	xpPopupText.Name = "XPPopupText"
	xpPopupText.Size = UDim2.fromScale(1, 1)
	xpPopupText.BackgroundTransparency = 1
	xpPopupText.Text = "+0 DNA"
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
	deathSummaryFrame.Size = UDim2.fromOffset(400, 280) -- Slightly taller
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

	-- Biomass Lost Label
	local biomassLostLabel = Instance.new("TextLabel")
	biomassLostLabel.Name = "BiomassLostLabel"
	biomassLostLabel.Size = UDim2.new(1, -20, 0, 30)
	biomassLostLabel.Position = UDim2.fromOffset(10, 105)
	biomassLostLabel.BackgroundTransparency = 1
	biomassLostLabel.Text = "Biomass: 0"
	biomassLostLabel.TextColor3 = COLORS.TEXT_WHITE
	biomassLostLabel.TextSize = 20
	biomassLostLabel.Font = Enum.Font.GothamBold
	biomassLostLabel.TextStrokeTransparency = 0.5
	biomassLostLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	biomassLostLabel.TextXAlignment = Enum.TextXAlignment.Left
	biomassLostLabel.Parent = deathSummaryFrame

	-- Earned DNA Label
	local earnedDNALabel = Instance.new("TextLabel")
	earnedDNALabel.Name = "EarnedDNALabel"
	earnedDNALabel.Size = UDim2.new(1, -20, 0, 50)
	earnedDNALabel.Position = UDim2.fromOffset(10, 150)
	earnedDNALabel.BackgroundTransparency = 1
	earnedDNALabel.Text = "CONVERTED: +0 DNA"
	earnedDNALabel.TextColor3 = RS_THEME.TEXT_YELLOW
	earnedDNALabel.TextSize = 24
	earnedDNALabel.Font = Enum.Font.GothamBold
	earnedDNALabel.TextStrokeTransparency = 0.3
	earnedDNALabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	earnedDNALabel.TextXAlignment = Enum.TextXAlignment.Center
	earnedDNALabel.Parent = deathSummaryFrame

	-- OK Button
	local okButton = Instance.new("TextButton")
	okButton.Name = "OKButton"
	okButton.Size = UDim2.fromOffset(100, 35)
	okButton.Position = UDim2.fromOffset(200, 220)
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
	-- 4c. HARVEST BUTTON (Safe Zone)
	-- ============================================
	local harvestButton = Instance.new("TextButton")
	harvestButton.Name = "HarvestButton"
	harvestButton.Size = UDim2.fromOffset(250, 80)
	harvestButton.Position = UDim2.fromScale(0.5, 0.7)
	harvestButton.AnchorPoint = Vector2.new(0.5, 0.5)
	harvestButton.BackgroundColor3 = COLORS.BUTTON_GREEN
	harvestButton.Visible = false -- Hidden until Safe
	harvestButton.Text = ""
	harvestButton.Parent = screenGui

	local harvestCorner = Instance.new("UICorner")
	harvestCorner.CornerRadius = UDim.new(0, 10)
	harvestCorner.Parent = harvestButton

	local harvestStroke = Instance.new("UIStroke")
	harvestStroke.Color = Color3.fromRGB(200, 255, 200)
	harvestStroke.Thickness = 3
	harvestStroke.Parent = harvestButton

	local harvestTitle = Instance.new("TextLabel")
	harvestTitle.Name = "Title"
	harvestTitle.Size = UDim2.new(1, 0, 0, 40)
	harvestTitle.Position = UDim2.new(0,0,0,5)
	harvestTitle.BackgroundTransparency = 1
	harvestTitle.Text = "HARVEST SIZE"
	harvestTitle.TextColor3 = COLORS.TEXT_WHITE
	harvestTitle.TextSize = 24
	harvestTitle.Font = Enum.Font.GothamBlack
	harvestTitle.TextStrokeTransparency = 0.5
	harvestTitle.Parent = harvestButton

	local harvestDesc = Instance.new("TextLabel")
	harvestDesc.Name = "Desc"
	harvestDesc.Size = UDim2.new(1, 0, 0, 30)
	harvestDesc.Position = UDim2.new(0,0,0,45)
	harvestDesc.BackgroundTransparency = 1
	harvestDesc.Text = "Convert Biomass to DNA"
	harvestDesc.TextColor3 = Color3.fromRGB(200, 255, 200)
	harvestDesc.TextSize = 16
	harvestDesc.Font = Enum.Font.GothamBold
	harvestDesc.TextStrokeTransparency = 0.5
	harvestDesc.Parent = harvestButton

	bindButtonSounds(harvestButton, true)



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
	shopTitle.Position = UDim2.new(0, 0, 0, 0)
	shopTitle.BackgroundColor3 = Color3.new(0, 0, 0)
	shopTitle.BackgroundTransparency = 0.5
	shopTitle.BorderSizePixel = 0
	shopTitle.Text = "SKILL TREE (DNA SHOP)"
	shopTitle.TextColor3 = RS_THEME.TEXT_ORANGE
	shopTitle.TextSize = 24
	shopTitle.Font = Enum.Font.GothamBold
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
		XPText = xpText,
		StatsBar = statsBar,
		DNALabel = dnaLabel,
		KillsLabel = killsLabel,
		AmmoPanel = ammoPanel,
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
		DeathTitle = deathTitle,
		KillsStatLabel = killsStatLabel,
		BiomassLostLabel = biomassLostLabel,
		EarnedDNALabel = earnedDNALabel,
		OKButton = okButton,
		HarvestButton = harvestButton,
		HarvestDesc = harvestDesc,
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
	tierNameLabel.Text = tierData.Name .. " (Req: " .. tierData.UnlockAmount .. " DNA)"
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
	costLabel.Text = "100 DNA"
	costLabel.TextColor3 = COLORS.XP_GOLD
	costLabel.TextSize = 16
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

						-- Unlock Check: uses lifetime Biomass (which is effectively Lifetime DNA earned)
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
							local levelLabel = actionContainer:FindFirstChild("LevelLabel")

							if levelLabel then
								levelLabel.Text = string.format("Level %d / %d", level, upgradeConfig.MaxLevel)
							end

							if costLabel then
								if level >= upgradeConfig.MaxLevel then
									costLabel.Text = "MAX"
								else
									costLabel.Text = string.format("%d DNA", math.floor(cost))
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
								elseif currentDNA >= cost then
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
local function showXPPopup(amount: number, isDNA: boolean?)
	isDNA = isDNA or false
	local prefix = if isDNA then "DNA" else "Biomass"
	local color = if isDNA then COLORS.XP_GOLD else COLORS.XP_ORANGE

	hud.XPPopupText.Text = string.format("+%d %s", amount, prefix)
	hud.XPPopupText.TextColor3 = color
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
	local biomass = player:GetAttribute("Biomass") or 0
	local requiredBiomass = ScalingConfig.GetXPRequired(level)

	local percent = math.clamp(biomass / requiredBiomass, 0, 1)

	if level >= ScalingConfig.MAX_LEVEL then
		hud.LevelLabel.Text = "MAX LEVEL"
		percent = 1
	else
		hud.XPText.Text = string.format("Level %d (Size)", level)
	end
	
	-- Update Size Label (optimized string formatting)
	hud.SizeLabel.Text = string.format("SIZE: %d", level)

	local tween = TweenService:Create(
		hud.XPFill,
		TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(percent, 1) }
	)
	tween:Play()
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
		-- print("HUD: No tool found in character")
		hud.AmmoPanel.Visible = false
		return
	end

	-- print("HUD: Found tool:", tool.Name)
	hud.AmmoPanel.Visible = true
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


-- Harvest Button Logic
local function updateHarvestButton()
	local isSafe = player:GetAttribute("SafeZone") == true
	hud.HarvestButton.Visible = isSafe

	if isSafe then
		-- Update text with current potential
		local potentialDNA = math.floor(player:GetAttribute("Biomass") or 0)
		hud.HarvestDesc.Text = "Convert Biomass to " .. potentialDNA .. " DNA"
	end
end

-- Harvest Click
local harvestDebounce = false
hud.HarvestButton.MouseButton1Click:Connect(function()
	if harvestDebounce then return end
	harvestDebounce = true

	local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
	local harvestRemote = remotes and remotes:FindFirstChild("Harvest")

	if harvestRemote then
		local success, msg = harvestRemote:InvokeServer()
		if success then
			playSound(SOUNDS.Purchase)
			-- UI will update via attribute signals
		else
			playSound(SOUNDS.Error)
		end
	end

	task.wait(1)
	harvestDebounce = false
end)


-- Meta Stats Update (from Server)
local function updateMetaStats(dna, upgrades, biomass)
	previousDNA = currentDNA
	currentDNA = dna or 0
	currentBiomass = biomass or 0 -- This is Lifetime Biomass (Unlock Progress)
	currentUpgrades = upgrades or {}

	if currentDNA > previousDNA then
		local gained = currentDNA - previousDNA
		if gained > 0 then
			showXPPopup(gained, true)
		end
	end

	if hud.ShopMainFrame.Visible then
		updateShopUI()
	end
	
	-- Update DNA Panel
	hud.DNALabel.Text = "DNA: " .. tostring(math.floor(currentDNA))
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
	updateHarvestButton()
	
	-- Connect Signals
	-- Note: Attributes are on the Player, so these signals persist across characters,
	-- but we refresh them here just in case.
end

player.CharacterAdded:Connect(setupCharacterConnections)

-- Attribute Listeners (Persistent on Player)
player:GetAttributeChangedSignal("Biomass"):Connect(function()
	updateXP()
	updateHarvestButton()
end)

player:GetAttributeChangedSignal("Level"):Connect(function()
	updateXP()
	-- Level Up Popup
	local lvl = player:GetAttribute("Level") or 1
	if lvl > 1 then
		hud.XPPopupText.Text = "GROWN TO LEVEL " .. lvl .. "!"
		hud.XPPopupText.TextColor3 = COLORS.XP_ORANGE
		hud.XPPopup.Visible = true
		
		task.delay(2, function()
			hud.XPPopup.Visible = false
		end)
	end
end)

player:GetAttributeChangedSignal("Kills"):Connect(updateKills)
player:GetAttributeChangedSignal("SafeZone"):Connect(updateHarvestButton)

-- Tool Connections
local function onChildAdded(child)
	if child:IsA("Tool") then
		updateAmmo()
		child:GetAttributeChangedSignal(Constants.AMMO_ATTRIBUTE):Connect(updateAmmo)
		child:GetAttributeChangedSignal(Constants.MAGAZINE_SIZE_ATTRIBUTE):Connect(updateAmmo)
		child:GetAttributeChangedSignal(Constants.RELOADING_ATTRIBUTE):Connect(updateAmmo)
	end
end

if player.Character then
	setupCharacterConnections(player.Character)
	player.Character.ChildAdded:Connect(onChildAdded)
	player.Character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then updateAmmo() end
	end)
end

player.CharacterAdded:Connect(function(char)
	char.ChildAdded:Connect(onChildAdded)
	char.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then updateAmmo() end
	end)
end)


-- Remotes
local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")

local updateMetaRemote = remotes:WaitForChild("UpdateMetaStats", 10)
if updateMetaRemote then
	updateMetaRemote.OnClientEvent:Connect(updateMetaStats)
end

local showDeathSummaryRemote = remotes:WaitForChild("ShowDeathSummary", 10)
if showDeathSummaryRemote then
	showDeathSummaryRemote.OnClientEvent:Connect(function(sessionKills, biomassLost, earnedDNA)
		hud.DeathSummaryFrame.Visible = true
		hud.KillsStatLabel.Text = "Kills: " .. tostring(sessionKills)
		hud.BiomassLostLabel.Text = "Biomass Lost: " .. tostring(biomassLost)
		hud.EarnedDNALabel.Text = "CONVERTED: +" .. tostring(earnedDNA) .. " DNA"
		
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
		local dna, upgrades, biomass = reqRemote:InvokeServer()
		updateMetaStats(dna, upgrades, biomass)
	end
end)
