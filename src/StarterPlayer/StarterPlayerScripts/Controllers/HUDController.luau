--[[
	Controller: HUDController
	Description: Manages all HUD elements including health, XP, ammo, DNA shop, and death summary
]]

local HUDController = {}

function HUDController.Start()
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
	local MutationShopController = require(script.Parent.MutationShopController)

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

	-- Sound Pool: Reuse Sound instances instead of creating/destroying each time
	-- This prevents GC thrashing during rapid UI interactions
	local soundPool = {} -- {[soundId] = {available = {Sound}, inUse = {Sound}}}

	local function getPooledSound(soundId)
		-- Initialize pool for this sound ID if needed
		if not soundPool[soundId] then
			soundPool[soundId] = { available = {}, inUse = {} }
		end

		local pool = soundPool[soundId]
		local sound = table.remove(pool.available)

		if not sound then
			-- Create new sound if pool is empty
			sound = Instance.new("Sound")
			sound.SoundId = soundId
			sound.Volume = 0.5
			sound.Parent = SoundService
		end

		pool.inUse[sound] = true
		return sound
	end

	local function returnPooledSound(soundId, sound)
		local pool = soundPool[soundId]
		if pool and pool.inUse[sound] then
			pool.inUse[sound] = nil
			table.insert(pool.available, sound)
		end
	end

	local function playSound(soundId)
		local sound = getPooledSound(soundId)
		sound:Play()

		-- Return to pool when done (use Once to auto-disconnect)
		sound.Ended:Once(function()
			returnPooledSound(soundId, sound)
		end)
	end

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
		XP_ORANGE = Color3.fromRGB(255, 150, 0),
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
		["Toxic Aura"] = "rbxassetid://11563251", -- Gas/Bomb
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
		screenGui.Enabled = false -- Hidden by default, enabled by LobbyController
		screenGui.Parent = playerGui

		-- ============================================
		-- 0. Top Bar (Size & Kills)
		-- ============================================
		local topBar = Instance.new("Frame")
		topBar.Name = "TopBar"
		topBar.Size = UDim2.new(1, 0, 0, 40)
		topBar.Position = UDim2.new(0, 0, 0, 0)
		topBar.BackgroundTransparency = 1
		topBar.Parent = screenGui

		-- Biomass Label (Top Left)
		local sizeLabel = Instance.new("TextLabel")
		sizeLabel.Name = "SizeLabel"
		sizeLabel.Size = UDim2.new(0, 200, 0, 30)
		sizeLabel.Position = UDim2.new(0, 10, 0, 0)
		sizeLabel.BackgroundTransparency = 1
		sizeLabel.Text = "BIOMASS: 0"
		sizeLabel.TextColor3 = COLORS.XP_GOLD
		sizeLabel.TextSize = 24
		sizeLabel.Font = Enum.Font.LuckiestGuy
		if not pcall(function()
			sizeLabel.Font = Enum.Font.LuckiestGuy
		end) then
			sizeLabel.Font = Enum.Font.GothamBlack
		end
		sizeLabel.TextXAlignment = Enum.TextXAlignment.Left
		sizeLabel.TextStrokeTransparency = 0
		sizeLabel.Parent = topBar

		-- DNA Label (Under Biomass)
		local dnaLabel = Instance.new("TextLabel")
		dnaLabel.Name = "DNALabel"
		dnaLabel.Size = UDim2.new(0, 200, 0, 20)
		dnaLabel.Position = UDim2.new(0, 10, 0, 30)
		dnaLabel.BackgroundTransparency = 1
		dnaLabel.Text = "DNA: 0"
		dnaLabel.TextColor3 = COLORS.XP_GOLD
		dnaLabel.TextSize = 18
		dnaLabel.Font = Enum.Font.GothamBold
		dnaLabel.TextXAlignment = Enum.TextXAlignment.Left
		dnaLabel.TextStrokeTransparency = 0.5
		dnaLabel.Parent = topBar

		-- Kills Label (Under DNA)
		local killsLabel = Instance.new("TextLabel")
		killsLabel.Name = "KillsLabel"
		killsLabel.Size = UDim2.new(0, 200, 0, 20)
		killsLabel.Position = UDim2.new(0, 10, 0, 50)
		killsLabel.BackgroundTransparency = 1
		killsLabel.Text = "KILLS: 0"
		killsLabel.TextColor3 = ARCADE_THEME.ACCENT_ORANGE
		killsLabel.TextSize = 18
		killsLabel.Font = Enum.Font.GothamBold
		killsLabel.TextXAlignment = Enum.TextXAlignment.Left
		killsLabel.TextStrokeTransparency = 0.5
		killsLabel.Parent = topBar

		-- ============================================
		-- 0b. Stats (Without Mutations)
		-- ============================================
		local statsFrame = Instance.new("Frame")
		statsFrame.Name = "StatsFrame"
		statsFrame.Size = UDim2.new(0, 200, 0, 100)
		statsFrame.Position = UDim2.new(0, 10, 0, 80) -- Below Kills
		statsFrame.BackgroundTransparency = 1
		statsFrame.Parent = topBar

		local statsHeader = Instance.new("TextLabel")
		statsHeader.Name = "Header"
		statsHeader.Size = UDim2.new(1, 0, 0, 20)
		statsHeader.BackgroundTransparency = 1
		statsHeader.Text = "Stats (without mutations)"
		statsHeader.TextColor3 = ARCADE_THEME.TEXT_GRAY
		statsHeader.TextSize = 14
		statsHeader.Font = Enum.Font.GothamBlack
		statsHeader.TextXAlignment = Enum.TextXAlignment.Left
		statsHeader.TextStrokeTransparency = 0.8
		statsHeader.Parent = statsFrame

		local function createStatLabel(name, order)
			local label = Instance.new("TextLabel")
			label.Name = name .. "Label"
			label.Size = UDim2.new(1, 0, 0, 18)
			label.Position = UDim2.new(0, 0, 0, 22 + (order * 18))
			label.BackgroundTransparency = 1
			label.Text = name .. ": -"
			label.TextColor3 = ARCADE_THEME.TEXT_WHITE
			label.TextSize = 16
			label.Font = Enum.Font.GothamBlack
			label.TextXAlignment = Enum.TextXAlignment.Left
			label.TextStrokeTransparency = 0
			label.TextStrokeColor3 = Color3.new(0, 0, 0)
			label.Parent = statsFrame
			return label
		end

		local statSizeLabel = createStatLabel("Size", 0)
		local statHealthLabel = createStatLabel("Health", 1)
		local statDamageLabel = createStatLabel("Damage", 2)
		local statSpeedLabel = createStatLabel("Speed", 3)

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
		if not pcall(function()
			healthText.Font = Enum.Font.LuckiestGuy
		end) then
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
		-- 3. Ammo Display
		-- ============================================
		local ammoPanel = Instance.new("Frame")
		ammoPanel.Name = "AmmoPanel"
		ammoPanel.Size = UDim2.fromOffset(200, 100)
		ammoPanel.Position = UDim2.fromScale(0.99, 0.95) -- Moved further right (0.98 -> 0.99)
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
		if not pcall(function()
			ammoLabel.Font = Enum.Font.LuckiestGuy
		end) then
			ammoLabel.Font = Enum.Font.GothamBlack
		end
		ammoLabel.TextStrokeTransparency = 0
		ammoLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
		ammoLabel.TextXAlignment = Enum.TextXAlignment.Right
		ammoLabel.RichText = true
		ammoLabel.Parent = ammoContainer

		-- Magazine Label removed as it was redundant and static

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
		deathSummaryFrame.BackgroundColor3 = ARCADE_THEME.BG_DARK
		deathSummaryFrame.BorderSizePixel = 0
		deathSummaryFrame.Visible = false
		deathSummaryFrame.ZIndex = 100
		deathSummaryFrame.Parent = screenGui

		local deathStroke = Instance.new("UIStroke")
		deathStroke.Color = ARCADE_THEME.STROKE_DARK
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
		killsStatLabel.TextColor3 = ARCADE_THEME.TEXT_WHITE
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
		biomassLostLabel.TextColor3 = ARCADE_THEME.TEXT_WHITE
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
		earnedDNALabel.TextColor3 = COLORS.XP_GOLD
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
		okButton.Position = UDim2.fromOffset(70, 220)
		okButton.AnchorPoint = Vector2.new(0, 0)
		okButton.BackgroundColor3 = ARCADE_THEME.BG_LIGHT
		okButton.BorderSizePixel = 0
		okButton.Text = "OK"
		okButton.TextColor3 = ARCADE_THEME.TEXT_WHITE
		okButton.TextSize = 18
		okButton.Font = Enum.Font.GothamBold
		okButton.Parent = deathSummaryFrame

		local okButtonCorner = Instance.new("UICorner")
		okButtonCorner.CornerRadius = UDim.new(0, 6)
		okButtonCorner.Parent = okButton

		local okButtonStroke = Instance.new("UIStroke")
		okButtonStroke.Color = ARCADE_THEME.STROKE_DARK
		okButtonStroke.Thickness = 2
		okButtonStroke.Parent = okButton

		-- Respawn Button (Moved to ShopMainFrame)
		local respawnButton = Instance.new("TextButton")
		respawnButton.Name = "RespawnButton"
		respawnButton.Size = UDim2.fromOffset(200, 50)
		respawnButton.Position = UDim2.new(0.5, 0, 1, -10)
		respawnButton.AnchorPoint = Vector2.new(0.5, 1)
		respawnButton.BackgroundColor3 = ARCADE_THEME.ACCENT_ORANGE
		respawnButton.BorderSizePixel = 0
		respawnButton.Text = "RESPAWN"
		respawnButton.TextColor3 = ARCADE_THEME.TEXT_WHITE
		respawnButton.TextSize = 24
		respawnButton.Font = Enum.Font.GothamBold
		respawnButton.Visible = false
		-- Parent will be set to ShopMainFrame later

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
		harvestTitle.Position = UDim2.new(0, 0, 0, 5)
		harvestTitle.BackgroundTransparency = 1
		harvestTitle.Text = "PRESS H TO HARVEST"
		harvestTitle.TextColor3 = ARCADE_THEME.TEXT_WHITE
		harvestTitle.TextSize = 24
		harvestTitle.Font = Enum.Font.GothamBlack
		harvestTitle.TextStrokeTransparency = 0.5
		harvestTitle.Parent = harvestButton

		local harvestDesc = Instance.new("TextLabel")
		harvestDesc.Name = "Desc"
		harvestDesc.Size = UDim2.new(1, 0, 0, 30)
		harvestDesc.Position = UDim2.new(0, 0, 0, 45)
		harvestDesc.BackgroundTransparency = 1
		harvestDesc.Text = "Convert Biomass to DNA"
		harvestDesc.TextColor3 = Color3.fromRGB(200, 255, 200)
		harvestDesc.TextSize = 16
		harvestDesc.Font = Enum.Font.GothamBold
		harvestDesc.TextStrokeTransparency = 0.5
		harvestDesc.Parent = harvestButton

		--bindButtonSounds(harvestButton, true)

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
		shopTitle.Text = "SHOP"
		shopTitle.TextColor3 = ARCADE_THEME.ACCENT_ORANGE
		shopTitle.TextSize = 24
		shopTitle.Font = Enum.Font.GothamBold
		shopTitle.Parent = shopMainFrame

		local shopDesc = Instance.new("TextLabel")
		shopDesc.Name = "Description"
		shopDesc.Size = UDim2.new(1, 0, 0, 20)
		shopDesc.Position = UDim2.new(0, 0, 0, 35)
		shopDesc.BackgroundTransparency = 1
		shopDesc.Text = "Common Mutations only"
		shopDesc.TextColor3 = ARCADE_THEME.TEXT_GRAY
		shopDesc.TextSize = 14
		shopDesc.Font = Enum.Font.Gotham
		shopDesc.Parent = shopMainFrame

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

		local shopScrollFrame = Instance.new("ScrollingFrame")
		shopScrollFrame.Name = "ShopScrollFrame"
		shopScrollFrame.Size = UDim2.new(1, -40, 1, -140) -- Reduced height to make room for Respawn Button
		shopScrollFrame.Position = UDim2.new(0, 20, 0, 60)
		shopScrollFrame.BackgroundTransparency = 1
		shopScrollFrame.ScrollBarThickness = 6
		shopScrollFrame.Parent = shopMainFrame

		-- Parent Respawn Button here
		respawnButton.Parent = shopMainFrame

		local respawnCorner = Instance.new("UICorner")
		respawnCorner.CornerRadius = UDim.new(0, 6)
		respawnCorner.Parent = respawnButton

		local respawnStroke = Instance.new("UIStroke")
		respawnStroke.Color = ARCADE_THEME.STROKE_DARK
		respawnStroke.Thickness = 2
		respawnStroke.Parent = respawnButton

		-- Mutations Button
		local mutationsButton = Instance.new("TextButton")
		mutationsButton.Name = "MutationsButton"
		mutationsButton.Size = UDim2.new(0, 120, 0, 30)
		mutationsButton.Position = UDim2.new(0, 10, 0, 10)
		mutationsButton.BackgroundColor3 = ARCADE_THEME.ACCENT_GREEN
		mutationsButton.Text = "MUTATIONS"
		mutationsButton.TextColor3 = ARCADE_THEME.TEXT_WHITE
		mutationsButton.Font = Enum.Font.GothamBold
		mutationsButton.TextSize = 14
		mutationsButton.Parent = shopMainFrame

		local mutationsCorner = Instance.new("UICorner")
		mutationsCorner.CornerRadius = UDim.new(0, 6)
		mutationsCorner.Parent = mutationsButton

		local mutationsStroke = Instance.new("UIStroke")
		mutationsStroke.Color = ARCADE_THEME.STROKE_DARK
		mutationsStroke.Thickness = 2
		mutationsStroke.Parent = mutationsButton

		local shopLayout = Instance.new("UIListLayout")
		shopLayout.Padding = UDim.new(0, 20)
		shopLayout.SortOrder = Enum.SortOrder.LayoutOrder
		shopLayout.Parent = shopScrollFrame

		return {
			ScreenGui = screenGui,
			-- Top Widget
			SizeLabel = sizeLabel,
			DNALabel = dnaLabel,
			KillsLabel = killsLabel,

			-- Stats Widget
			StatSizeLabel = statSizeLabel,
			StatHealthLabel = statHealthLabel,
			StatDamageLabel = statDamageLabel,
			StatSpeedLabel = statSpeedLabel,

			-- Health Widget
			HealthText = healthText,
			HealthFill = healthFill,

			-- Progression Widget
			LevelLabel = xpText,
			XPFill = xpFill,
			XPText = xpText,
			AmmoPanel = ammoPanel,
			AmmoLabel = ammoLabel,
			WeaponIcon = weaponIcon,

			-- Other
			XPPopup = xpPopupFrame,
			XPPopupText = xpPopupText,
			ShopMainFrame = shopMainFrame,
			ShopScrollFrame = shopScrollFrame,
			ShopCloseButton = shopCloseButton,
			MutationsButton = mutationsButton,
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

		if tierNumber == 1 then
			tierHeader.Visible = false
			tierHeader.Size = UDim2.new(1, 0, 0, 0)
		end

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
		tierNameLabel.TextColor3 = ARCADE_THEME.TEXT_WHITE
		tierNameLabel.TextSize = 18
		tierNameLabel.Font = Enum.Font.GothamBold
		tierNameLabel.TextXAlignment = Enum.TextXAlignment.Left
		tierNameLabel.Parent = tierHeader

		-- Upgrade container
		local upgradeContainer = Instance.new("Frame")
		upgradeContainer.Name = "UpgradeContainer"
		upgradeContainer.Size = UDim2.new(1, 0, 0, 0)
		if tierNumber == 1 then
			upgradeContainer.Position = UDim2.new(0, 0, 0, 0)
		else
			upgradeContainer.Position = UDim2.new(0, 0, 0, 50)
		end
		upgradeContainer.BackgroundTransparency = 1
		upgradeContainer.AutomaticSize = Enum.AutomaticSize.Y
		upgradeContainer.Parent = tierFrame

		local upgradeListLayout = Instance.new("UIListLayout")
		upgradeListLayout.Padding = UDim.new(0, 10)
		upgradeListLayout.SortOrder = Enum.SortOrder.LayoutOrder
		upgradeListLayout.Parent = upgradeContainer

		return tierFrame
	end

	-- Cache remotes at module level (fetched once, used by all cards)
	local cachedRemotes = nil
	local purchaseUpgradeRemote = nil

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
		iconImage.Image = upgradeConfig.ImageId or ICON_MAP[statName] or ICON_MAP.StartLevel
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

		-- Purchase logic - use cached remotes (will be set by parent scope)
		-- Note: purchaseUpgradeRemote is captured from outer scope to avoid WaitForChild in loop

		purchaseButton.MouseEnter:Connect(function()
			playSound(SOUNDS.Hover)
		end)
		purchaseButton.MouseButton1Click:Connect(function()
			if purchaseUpgradeRemote then
				local success, _message = purchaseUpgradeRemote:InvokeServer(statName)
				if success then
					playSound(SOUNDS.Purchase)

					-- Immediate Local Update (Optimistic)
					local currentLvl = currentUpgrades[statName] or 0
					local newLvl = currentLvl + 1
					currentUpgrades[statName] = newLvl

					-- Recalculate Cost for Next Level
					local nextCost = MetaConfig.GetCost(statName, newLvl)

					-- Update UI Elements directly
					local percent = math.clamp(newLvl / upgradeConfig.MaxLevel, 0, 1)
					progressBarFill.Size = UDim2.fromScale(percent, 1)

					levelLabel.Text = string.format("Level %d / %d", newLvl, upgradeConfig.MaxLevel)

					if newLvl >= upgradeConfig.MaxLevel then
						costLabel.Text = "MAX"
						purchaseButton.BackgroundColor3 = COLORS.XP_GOLD
						purchaseButton.Text = "MAXED"
						purchaseButton.Active = false
					else
						costLabel.Text = string.format("%d DNA", math.floor(nextCost))
						-- Button state will be re-evaluated on next updateShopUI or we can do it here
						-- But simpler to just let the loop or next update handle the button color/active state based on DNA
						-- For now, just update the text/bar which is the visual feedback requested.
					end

				-- Deduct DNA locally for display?
				-- currentDNA = currentDNA - (MetaConfig.GetCost(statName, currentLvl)) -- Need cost of *purchased* level
				-- Actually, better to wait for server update for currency to avoid desync,
				-- but the bar/level is safe to increment.
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
			purchaseButton = purchaseButton,
		}

		return cardFrame
	end

	-- Build skill tree structure
	local tierFrames = {}

	task.spawn(function()
		-- Fetch remotes ONCE at startup
		cachedRemotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
		if not cachedRemotes then
			return
		end
		purchaseUpgradeRemote = cachedRemotes:FindFirstChild("PurchaseUpgrade")

		-- Common Mutations Shop: Only show Common mutations (IsMutation = true, Tier = 1)
		for tierNumber = 1, 1 do
			local tierData = MetaConfig.Tiers[tierNumber]
			if tierData then
				local tierFrame = createTierSection(tierNumber, tierData)
				tierFrames[tierNumber] = tierFrame

				for statName, upgradeConfig in pairs(MetaConfig.Upgrades) do
					-- Only show common mutations, not regular upgrades
					if upgradeConfig.Tier == tierNumber and upgradeConfig.IsMutation then
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
	-- Uses cardCache to directly access UI elements without FindFirstChild lookups
	local function updateShopUI()
		-- Use cardCache for direct element access (100x faster than FindFirstChild)
		for statName, cached in pairs(cardCache) do
			local upgradeConfig = MetaConfig.Upgrades[statName]
			if not upgradeConfig then
				continue
			end

			local level = currentUpgrades[statName] or 0
			local cost = MetaConfig.GetCost(statName, level)
			local isUnlocked = MetaConfig.IsUnlocked(currentBiomass, statName)

			-- Update progress bar (cached reference)
			if cached.progressBarFill then
				local percent = math.clamp(level / upgradeConfig.MaxLevel, 0, 1)
				cached.progressBarFill.Size = UDim2.fromScale(percent, 1)
			end

			-- Update level label (cached reference)
			if cached.levelLabel then
				cached.levelLabel.Text = string.format("Level %d / %d", level, upgradeConfig.MaxLevel)
			end

			-- Update cost label (cached reference)
			if cached.costLabel then
				if level >= upgradeConfig.MaxLevel then
					cached.costLabel.Text = "MAX"
				else
					cached.costLabel.Text = string.format("%d DNA", math.floor(cost))
				end
			end

			-- Update lock overlay and purchase button (cached references)
			if isUnlocked then
				if cached.lockOverlay then
					cached.lockOverlay.Visible = false
				end
				if cached.card then
					cached.card.BackgroundTransparency = 0.2
				end

				if cached.purchaseButton then
					if level >= upgradeConfig.MaxLevel then
						cached.purchaseButton.BackgroundColor3 = COLORS.XP_GOLD
						cached.purchaseButton.Text = "MAXED"
						cached.purchaseButton.Active = false
					elseif currentDNA >= cost then
						cached.purchaseButton.BackgroundColor3 = COLORS.BUTTON_GREEN
						cached.purchaseButton.Text = "UPGRADE"
						cached.purchaseButton.Active = true
					else
						cached.purchaseButton.BackgroundColor3 = COLORS.BUTTON_RED
						cached.purchaseButton.Text = "UPGRADE"
						cached.purchaseButton.Active = true
					end
				end
			else
				if cached.lockOverlay then
					cached.lockOverlay.Visible = true
				end
				if cached.card then
					cached.card.BackgroundTransparency = 0.5
				end
				if cached.purchaseButton then
					cached.purchaseButton.BackgroundColor3 = COLORS.LOCKED_GREY
					cached.purchaseButton.Text = "LOCKED"
					cached.purchaseButton.Active = false
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

	local UI_SINK_ACTION = "HUD_UI_Sink"

	local function setUIInputSink(enabled: boolean)
		if enabled then
			-- Sink all input to prevent shooting/interactions while UI is open
			ContextActionService:BindAction(UI_SINK_ACTION, function()
				return Enum.ContextActionResult.Sink
			end, false, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch, Enum.KeyCode.ButtonR2)
		else
			ContextActionService:UnbindAction(UI_SINK_ACTION)
		end
	end

	local function setShopState(isOpen, isDeath)
		hud.ShopMainFrame.Visible = isOpen

		if isOpen then
			-- Unlock mouse for UI interaction
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			setUIInputSink(true)
			updateShopUI()

			-- Enforce mouse unlock every frame to prevent other scripts from locking it
			RunService:BindToRenderStep("UnlockMouseForShop", Enum.RenderPriority.Last.Value, function()
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)

			-- Hide Reticle (Crosshair)
			local reticle = player:WaitForChild("PlayerGui"):FindFirstChild("ReticleGui")
			if reticle then
				reticle.Enabled = false
			end

			if isDeath then
				hud.RespawnButton.Visible = true
				hud.ShopCloseButton.Visible = false
				hud.AmmoPanel.Visible = false
			else
				hud.RespawnButton.Visible = false
				hud.ShopCloseButton.Visible = true
			end
		else
			-- Re-lock mouse for gameplay
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
			setUIInputSink(false)

			pcall(function()
				RunService:UnbindFromRenderStep("UnlockMouseForShop")
			end)

			-- Restore Reticle (Crosshair) if tool is equipped
			local reticle = player:WaitForChild("PlayerGui"):FindFirstChild("ReticleGui")
			if reticle then
				local character = player.Character
				if character and character:FindFirstChildOfClass("Tool") then
					reticle.Enabled = true
				end
			end
		end
	end

	local function toggleShop()
		local isOpening = not hud.ShopMainFrame.Visible
		setShopState(isOpening, false)
	end

	-- Set callback for Mutation Shop to return here
	MutationShopController.SetCloseCallback(function()
		setShopState(true, false) -- Re-open main shop
	end)

	-- Button Connections
	hud.ShopCloseButton.MouseButton1Click:Connect(toggleShop)
	hud.MutationsButton.MouseButton1Click:Connect(function()
		local success = MutationShopController.Open()
		if success then
			toggleShop() -- Close Skill Tree
		else
			playSound(SOUNDS.Error)

			-- Visual Feedback
			local originalText = hud.MutationsButton.Text
			local originalColor = hud.MutationsButton.BackgroundColor3

			hud.MutationsButton.Text = "NEED 250 DNA"
			hud.MutationsButton.BackgroundColor3 = COLORS.BUTTON_RED

			task.delay(1.5, function()
				if hud.MutationsButton then
					hud.MutationsButton.Text = originalText
					hud.MutationsButton.BackgroundColor3 = originalColor
				end
			end)
		end
	end)

	-- Keyboard shortcut: N to toggle mutation shop
	ContextActionService:BindAction("ToggleMutationShop", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			-- Priority: Close any open shop first
			if hud.ShopMainFrame.Visible then
				-- Main shop is open, close it
				setShopState(false, false)
			elseif MutationShopController.IsOpen() then
				-- Mutation shop is open, close it (skip callback to prevent main shop reopening)
				MutationShopController.Close(true)
			else
				-- Nothing is open, open mutation shop
				local success = MutationShopController.Open()
				if not success then
					playSound(SOUNDS.Error)
				end
			end
		end
	end, false, Enum.KeyCode.N)

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
		-- Update Size Label (optimized string formatting)
		hud.SizeLabel.Text = string.format("BIOMASS: %d", biomass)

		local tween = TweenService:Create(
			hud.XPFill,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(percent, 1) }
		)
		tween:Play()

		-- Update Base Stats (Without Mutations)
		-- Calculate smooth level for stats that scale with biomass (size, health, speed)
		local progress = requiredBiomass > 0 and math.clamp(biomass / requiredBiomass, 0, 0.99) or 0
		local smoothLevel = level + progress

		local baseSize = ScalingConfig.GetSizeMultiplier(smoothLevel)
		local baseHealth = ScalingConfig.GetMaxHealth(smoothLevel)
		local baseDamage = ScalingConfig.GetDamageMultiplier(level) -- Damage stays at integer level
		local baseSpeed = ScalingConfig.GetWalkSpeed(smoothLevel)

		hud.StatSizeLabel.Text = string.format("Size: %.2fx", baseSize)
		hud.StatHealthLabel.Text = string.format("Health: %.1fx", baseHealth / ScalingConfig.GetMaxHealth(1))
		hud.StatDamageLabel.Text = string.format("Damage: %.2fx", baseDamage)
		hud.StatSpeedLabel.Text = string.format("Speed: %d", math.floor(baseSpeed))
	end

	local function updateKills()
		local kills = player:GetAttribute("Kills") or 0
		-- Optimized string formatting
		hud.KillsStatLabel.Text = string.format("Kills: %d", kills)
		hud.KillsLabel.Text = string.format("KILLS: %d", kills)
	end

	local function updateAmmo()
		local character = player.Character
		if not character then
			hud.AmmoPanel.Visible = false
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

	-- Harvest Logic
	local harvestDebounce = false
	local function tryHarvest()
		print("DEBUG: tryHarvest called")
		if harvestDebounce then
			print("DEBUG: Harvest debounced")
			return
		end

		-- Client-side check: Must be in Safe Zone
		local isSafe = player:GetAttribute("SafeZone")
		print("DEBUG: SafeZone attribute:", isSafe)

		if isSafe ~= true then
			print("DEBUG: Not in Safe Zone (Attribute is " .. tostring(isSafe) .. ")")
			return
		end

		harvestDebounce = true
		print("DEBUG: Invoking Harvest remote...")

		local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
		local harvestRemote = remotes and remotes:FindFirstChild("Harvest")

		if harvestRemote then
			local success, msg = harvestRemote:InvokeServer()
			print("DEBUG: Harvest result:", success, msg)
			if success then
				playSound(SOUNDS.Purchase)
			-- UI will update via attribute signals
			else
				warn("Harvest Failed:", msg)
				playSound(SOUNDS.Error)
			end
		else
			warn("DEBUG: Harvest remote not found!")
		end

		task.wait(1)
		harvestDebounce = false
	end

	hud.HarvestButton.MouseButton1Click:Connect(tryHarvest)

	-- Bind H key for harvesting
	ContextActionService:BindAction("HarvestAction", function(_, inputState)
		if inputState == Enum.UserInputState.Begin then
			print("DEBUG: H key pressed")
			tryHarvest()
		end
	end, false, Enum.KeyCode.H)

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
		hud.AmmoPanel.Visible = false

		-- Reset mouse lock
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false

		-- Ensure we unbind the shop mouse unlock if it's still running
		pcall(function()
			RunService:UnbindFromRenderStep("UnlockMouseForShop")
		end)

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
	player:GetAttributeChangedSignal("DNA"):Connect(function()
		local dna = player:GetAttribute("DNA") or 0
		hud.DNALabel.Text = "DNA: " .. math.floor(dna)
		currentDNA = dna
	end)

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
			if child:IsA("Tool") then
				updateAmmo()
			end
		end)
	end

	player.CharacterAdded:Connect(function(char)
		char.ChildAdded:Connect(onChildAdded)
		char.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				updateAmmo()
			end
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
		showDeathSummaryRemote.OnClientEvent:Connect(function(_sessionKills, _biomassLost, _earnedDNA)
			-- Show Shop instead of Death Summary using new helper
			-- Note: Parameters kept for API compatibility but currently unused
			setShopState(true, true)
		end)
	end

	-- Respawn Button Logic
	local requestRespawnRemote = remotes:WaitForChild("RequestRespawn", 10)
	if requestRespawnRemote then
		hud.RespawnButton.MouseButton1Click:Connect(function()
			-- Fire respawn request
			requestRespawnRemote:FireServer()

			-- Reset UI state using new helper
			setShopState(false, false)

			-- Hide Death Summary Frame (legacy)
			hud.DeathSummaryFrame.Visible = false
		end)
	end

	hud.OKButton.MouseButton1Click:Connect(function()
		hud.DeathSummaryFrame.Visible = false
		setShopState(false, false)
	end)

	task.spawn(function()
		local reqRemote = remotes:WaitForChild("RequestMetaData", 10)
		if reqRemote then
			local dna, upgrades, biomass = reqRemote:InvokeServer()
			updateMetaStats(dna, upgrades, biomass)
		end

		-- Also read DNA attribute directly as backup (in case it's set but remote hasn't fired)
		local attrDNA = player:GetAttribute("DNA")
		if attrDNA and attrDNA > 0 then
			hud.DNALabel.Text = "DNA: " .. math.floor(attrDNA)
			currentDNA = attrDNA
		end
	end)

	print("✅ HUDController: Started")
end

return HUDController
