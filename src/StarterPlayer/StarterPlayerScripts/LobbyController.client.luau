local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- --- Constants & Theme (LoL Client Style) --- --
local THEME = {
	BG_DARK = Color3.fromRGB(10, 14, 20), -- Deep Blue/Black
	BG_PANEL = Color3.fromRGB(30, 36, 46), -- Panel Background
	ACCENT_GOLD = Color3.fromRGB(200, 170, 110), -- Hextech Gold
	ACCENT_BLUE = Color3.fromRGB(0, 150, 200), -- Hextech Blue
	TEXT_WHITE = Color3.fromRGB(240, 240, 240),
	TEXT_GOLD = Color3.fromRGB(240, 210, 150),
	BUTTON_PLAY = Color3.fromRGB(0, 200, 100), -- Green button base
	BUTTON_PLAY_STROKE = Color3.fromRGB(0, 150, 80), -- Darker Green Stroke
	BUTTON_PLAY_SHADOW = Color3.fromRGB(0, 100, 50), -- Shadow color
}

local function createLobby()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true -- Full screen
	screenGui.DisplayOrder = 100 -- On top of everything
	screenGui.Parent = playerGui

	-- ============================================
	-- 1. Background & ViewportFrame (Viewmodel)
	-- ============================================
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.new(0, 0, 0)
	bg.BackgroundTransparency = 0.2 -- Darken the world behind
	bg.BorderSizePixel = 0
	bg.Parent = screenGui

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "CharacterViewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Parent = bg
	
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	
	local viewportCamera = Instance.new("Camera")
	viewportCamera.FieldOfView = 60
	viewport.CurrentCamera = viewportCamera
	viewportCamera.Parent = viewport

	-- Character Cloning & Animation
	local runService = game:GetService("RunService")
	local rotation = 0
	local viewmodelConnection
	
	local function updateViewmodel()
		worldModel:ClearAllChildren()
		local char = player.Character
		if char then
			char.Archivable = true
			local clone = char:Clone()
			clone.Name = "ViewmodelCharacter"
			clone.Parent = worldModel
			
			-- Anchor everything in the clone so it doesn't fall
			for _, part in ipairs(clone:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CanCollide = false
				end
			end
			
			-- Position at origin
			if clone.PrimaryPart then
				clone:SetPrimaryPartCFrame(CFrame.new(0, 0, 0))
			else
				-- Fallback if no primary part
				clone:PivotTo(CFrame.new(0,0,0))
			end

			-- Force T-Pose (Remove Animate script and stop tracks)
			local animateScript = clone:FindFirstChild("Animate")
			if animateScript then
				animateScript:Destroy()
			end
			
			local humanoid = clone:FindFirstChild("Humanoid")
			if humanoid then
				local animator = humanoid:FindFirstChild("Animator")
				if animator then
					for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
						track:Stop()
					end
				end
			end
			
			-- Explicitly force T-Pose by manipulating Motor6Ds
			-- R15 Standard: LeftShoulder, RightShoulder in UpperTorso
			-- We want to rotate them up 90 degrees (pi/2)
			local upperTorso = clone:WaitForChild("UpperTorso", 5)
			if upperTorso then
				local leftShoulder = upperTorso:WaitForChild("LeftShoulder", 5)
				local rightShoulder = upperTorso:WaitForChild("RightShoulder", 5)
				
				if leftShoulder then
					-- Rotate Left Arm Up (Z axis usually)
					leftShoulder.C0 = CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
				end
				
				if rightShoulder then
					-- Rotate Right Arm Up
					rightShoulder.C0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, 0, math.rad(-90))
				end
			end
		end
	end
	
	local function enableViewmodel()
		updateViewmodel()
		
		if viewmodelConnection then viewmodelConnection:Disconnect() end
		viewmodelConnection = runService.RenderStepped:Connect(function(dt)
			rotation = rotation + (dt * 0.25) -- Slower rotation (was 0.5)
			local radius = 9
			local camX = math.sin(rotation) * radius
			local camZ = math.cos(rotation) * radius
			
			viewportCamera.CFrame = CFrame.lookAt(Vector3.new(camX, 1, camZ), Vector3.new(0, 0, 0))
			
			-- Continuously ensure mouse is unlocked (prevents other systems from locking it)
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
		
		-- Hide Main HUD if it exists
		local mainHud = playerGui:FindFirstChild("HUD")
		if mainHud then mainHud.Enabled = false end
		
		-- Unlock Mouse for UI interaction
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end
	
	local function disableViewmodel()
		if viewmodelConnection then 
			viewmodelConnection:Disconnect() 
			viewmodelConnection = nil
		end
		-- Show Main HUD
		local mainHud = playerGui:FindFirstChild("HUD")
		if mainHud then mainHud.Enabled = true end
	end

	-- Initial Setup
	enableViewmodel()
	
	-- Refresh on respawn
	player.CharacterAdded:Connect(function()
		if screenGui.Enabled then
			task.wait(0.5) -- Wait for character to load appearance
			enableViewmodel()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end)

	-- ============================================
	-- 2. Top Navigation Bar
	-- ============================================
	local navBar = Instance.new("Frame")
	navBar.Name = "NavBar"
	navBar.Size = UDim2.new(1, 0, 0, 50)
	navBar.BackgroundColor3 = Color3.new(0,0,0)
	navBar.BackgroundTransparency = 0.3
	navBar.BorderSizePixel = 0
	navBar.Parent = screenGui

	local navList = Instance.new("UIListLayout")
	navList.FillDirection = Enum.FillDirection.Horizontal
	navList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	navList.VerticalAlignment = Enum.VerticalAlignment.Center
	navList.Padding = UDim.new(0, 40)
	navList.Parent = navBar
	
	local navPadding = Instance.new("UIPadding")
	navPadding.PaddingLeft = UDim.new(0, 20)
	navPadding.Parent = navBar

	-- Navigation Buttons Removed as per request
	-- Keeping the bar for visual structure if needed, or it can be empty.


	-- ============================================
	-- 2b. Player Stats Display (Top Left)
	-- ============================================
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "StatsFrame"
	statsFrame.Size = UDim2.new(0, 200, 0, 80)
	statsFrame.Position = UDim2.new(0, 20, 0, 60)
	statsFrame.BackgroundTransparency = 1
	statsFrame.Parent = screenGui
	
	local statsLabels = {}
	local statNames = {"BIOMASS", "DNA", "KILLS"}
	
	for i, statName in ipairs(statNames) do
		local label = Instance.new("TextLabel")
		label.Name = statName .. "Label"
		label.Size = UDim2.new(1, 0, 0, 22)
		label.Position = UDim2.new(0, 0, 0, (i-1) * 25)
		label.BackgroundTransparency = 1
		label.Text = statName .. ": 0"
		label.TextColor3 = THEME.TEXT_GOLD
		label.TextSize = 16
		label.Font = Enum.Font.GothamBold
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextStrokeTransparency = 0.5
		label.TextStrokeColor3 = Color3.new(0, 0, 0)
		label.Parent = statsFrame
		
		statsLabels[statName] = label
	end
	
	-- Update stats from player attributes
	local function updateStats()
		local biomass = player:GetAttribute("Biomass") or 0
		local dna = player:GetAttribute("DNA") or 0
		local kills = player:GetAttribute("Kills") or 0
		
		statsLabels["BIOMASS"].Text = "BIOMASS: " .. biomass
		statsLabels["DNA"].Text = "DNA: " .. dna
		statsLabels["KILLS"].Text = "KILLS: " .. kills
	end
	
	-- Listen for attribute changes
	player.AttributeChanged:Connect(function(attr)
		if attr == "Biomass" or attr == "DNA" or attr == "Kills" then
			updateStats()
		end
	end)
	
	updateStats() -- Initial update

	-- ============================================
	-- 3. Main Content (Empty for 3D View)
	-- ============================================
	local mainContent = Instance.new("Frame")
	mainContent.Name = "MainContent"
	mainContent.Size = UDim2.fromScale(1, 1)
	mainContent.BackgroundTransparency = 1
	mainContent.Parent = screenGui
	mainContent.ZIndex = 0

	-- Static Art Removed for Real-time 3D View

	-- ============================================
	-- 4. Right Side Panels (News/Promo) - REMOVED
	-- ============================================
	-- Removed as per request


	-- ============================================
	-- 5. Bottom Bar (Play Button & Social)
	-- ============================================
	local bottomBar = Instance.new("Frame")
	bottomBar.Name = "BottomBar"
	bottomBar.Size = UDim2.new(1, 0, 0, 80)
	bottomBar.Position = UDim2.fromScale(0, 1)
	bottomBar.AnchorPoint = Vector2.new(0, 1)
	bottomBar.BackgroundTransparency = 1
	bottomBar.Parent = screenGui

	-- Play Button Area
	local playArea = Instance.new("Frame")
	playArea.Name = "PlayArea"
	playArea.Size = UDim2.new(0, 250, 1, 0)
	playArea.Position = UDim2.new(1, -20, 0, 0)
	playArea.AnchorPoint = Vector2.new(1, 0)
	playArea.BackgroundTransparency = 1
	playArea.Parent = bottomBar

	-- "NORMAL" Label
	local modeLabel = Instance.new("TextLabel")
	modeLabel.Text = "NORMAL"
	modeLabel.Size = UDim2.new(1, 0, 0, 20)
	modeLabel.Position = UDim2.new(0, 0, 0.2, 0)
	modeLabel.BackgroundTransparency = 1
	modeLabel.TextColor3 = THEME.TEXT_WHITE
	modeLabel.Font = Enum.Font.GothamBold
	modeLabel.TextSize = 14
	modeLabel.Parent = playArea

	-- Play Button (Bottom Right)
	local playBtn = Instance.new("TextButton")
	playBtn.Name = "PlayButton"
	playBtn.Size = UDim2.new(0, 180, 0, 50)
	playBtn.Position = UDim2.new(1, 0, 0.8, 0)
	playBtn.AnchorPoint = Vector2.new(1, 1)
	playBtn.BackgroundColor3 = THEME.BUTTON_PLAY
	playBtn.Text = "QUICK PLAY"
	playBtn.TextColor3 = THEME.TEXT_WHITE
	playBtn.Font = Enum.Font.GothamBlack
	playBtn.TextSize = 20
	playBtn.Parent = playArea

	local playStroke = Instance.new("UIStroke")
	playStroke.Color = THEME.BUTTON_PLAY_STROKE
	playStroke.Thickness = 2
	playStroke.Parent = playBtn
	
	local playCorner = Instance.new("UICorner")
	playCorner.CornerRadius = UDim.new(0, 8) -- Less rounded, more button-like
	playCorner.Parent = playBtn
	
	-- Depth Effect (Shadow)
	local playShadow = Instance.new("Frame")
	playShadow.Name = "Shadow"
	playShadow.Size = UDim2.new(1, 0, 1, 0)
	playShadow.Position = UDim2.new(0, 0, 0, 4) -- Offset downwards
	playShadow.BackgroundColor3 = THEME.BUTTON_PLAY_SHADOW
	playShadow.ZIndex = -1
	playShadow.Parent = playBtn
	
	local shadowCorner = Instance.new("UICorner")
	shadowCorner.CornerRadius = UDim.new(0, 8)
	shadowCorner.Parent = playShadow
	
	-- Role Icon (Left of Play Button)
	local roleIcon = Instance.new("ImageButton")
	roleIcon.Size = UDim2.new(0, 45, 0, 45)
	roleIcon.Position = UDim2.new(0, 10, 0.8, -5)
	roleIcon.AnchorPoint = Vector2.new(0, 1)
	roleIcon.BackgroundColor3 = THEME.BG_PANEL
	roleIcon.Image = "rbxassetid://7733960981" -- Role/Settings icon
	roleIcon.ScaleType = Enum.ScaleType.Fit
	roleIcon.Parent = playArea
	
	local roleCorner = Instance.new("UICorner")
	roleCorner.CornerRadius = UDim.new(0.2, 0)
	roleCorner.Parent = roleIcon
	
	local roleStroke = Instance.new("UIStroke")
	roleStroke.Color = THEME.ACCENT_GOLD
	roleStroke.Thickness = 2
	roleStroke.Parent = roleIcon
	
	-- Role icon interactions
	roleIcon.MouseEnter:Connect(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		roleStroke.Color = THEME.ACCENT_BLUE
	end)
	
	roleIcon.MouseLeave:Connect(function()
		roleStroke.Color = THEME.ACCENT_GOLD
	end)
	
	roleIcon.MouseButton1Click:Connect(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		print("Role selector clicked (not yet implemented)")
	end)

	-- Play Button Logic
	playBtn.MouseEnter:Connect(function()
		-- Ensure mouse stays unlocked even on hover
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
	
	playBtn.MouseButton1Down:Connect(function()
		-- Immediately unlock mouse when button is pressed down
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
	
	playBtn.MouseButton1Click:Connect(function()
		-- Hide Lobby and re-enable HUD
		screenGui.Enabled = false
		disableViewmodel()
		
		-- Unlock mouse for gameplay
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		
		-- Request spawn/respawn from server
		local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Blaster"):WaitForChild("Remotes")
		local respawnRemote = remotes:WaitForChild("RequestRespawn", 5)
		if respawnRemote then
			respawnRemote:FireServer(true) -- true = skip death (safe spawn)
			print("Quick Play: Spawning player...")
		else
			-- Fallback: Just spawn the character directly
			player:LoadCharacter()
			print("Quick Play: Loading character (fallback)...")
		end
	end)

	-- ============================================
	-- 6. Friend List (Collapsible Drawer) - REMOVED
	-- ============================================
	-- Removed as per request


	-- ============================================
	-- 7. Shop Template
	-- ============================================
	local shopFrame = Instance.new("Frame")
	shopFrame.Name = "ShopFrame"
	shopFrame.Size = UDim2.fromScale(0.8, 0.8)
	shopFrame.Position = UDim2.fromScale(0.5, 0.5)
	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopFrame.BackgroundColor3 = THEME.BG_DARK
	shopFrame.Visible = false
	shopFrame.ZIndex = 200
	shopFrame.Parent = screenGui
	
	local shopStroke = Instance.new("UIStroke")
	shopStroke.Color = THEME.ACCENT_GOLD
	shopStroke.Thickness = 2
	shopStroke.Parent = shopFrame
	
	local shopTitle = Instance.new("TextLabel")
	shopTitle.Text = "STORE"
	shopTitle.Size = UDim2.new(1, 0, 0, 50)
	shopTitle.BackgroundTransparency = 1
	shopTitle.TextColor3 = THEME.ACCENT_GOLD
	shopTitle.Font = Enum.Font.GothamBlack
	shopTitle.TextSize = 32
	shopTitle.Parent = shopFrame
	
	local closeShop = Instance.new("TextButton")
	closeShop.Text = "X"
	closeShop.Size = UDim2.new(0, 40, 0, 40)
	closeShop.Position = UDim2.new(1, -10, 0, 10)
	closeShop.AnchorPoint = Vector2.new(1, 0)
	closeShop.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeShop.TextColor3 = Color3.new(1,1,1)
	closeShop.Parent = shopFrame
	
	closeShop.MouseButton1Click:Connect(function()
		shopFrame.Visible = false
	end)
	
	local shopContent = Instance.new("TextLabel")
	shopContent.Text = "SHOP TEMPLATE\n(Coming Soon)"
	shopContent.Size = UDim2.fromScale(1, 1)
	shopContent.BackgroundTransparency = 1
	shopContent.TextColor3 = Color3.fromRGB(100, 100, 100)
	shopContent.TextSize = 40
	shopContent.Parent = shopFrame

end

createLobby()
