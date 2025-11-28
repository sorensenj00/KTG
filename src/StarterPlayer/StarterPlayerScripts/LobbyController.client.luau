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
	BUTTON_PLAY = Color3.fromRGB(30, 30, 35), -- Dark button base
	BUTTON_PLAY_STROKE = Color3.fromRGB(0, 200, 255), -- Bright Blue Stroke
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
		end
	end
	
	local function enableViewmodel()
		updateViewmodel()
		
		if viewmodelConnection then viewmodelConnection:Disconnect() end
		viewmodelConnection = runService.RenderStepped:Connect(function(dt)
			rotation = rotation + (dt * 0.5) -- Speed of rotation
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

	local TABS = {"HOME", "LOREFINDER", "MATCH HISTORY", "NEWS", "STORE", "TREASURE REALMS"}
	local currentTab = "HOME"
	
	local function updateTabStyles()
		for _, child in ipairs(navBar:GetChildren()) do
			if child:IsA("TextButton") then
				if child.Name == currentTab then
					child.TextColor3 = THEME.TEXT_WHITE
					child.BackgroundTransparency = 0.7
					child.BackgroundColor3 = THEME.ACCENT_BLUE
				else
					child.TextColor3 = Color3.fromRGB(150, 150, 160)
					child.BackgroundTransparency = 1
				end
			end
		end
	end
	
	for _, tabName in ipairs(TABS) do
		local btn = Instance.new("TextButton")
		btn.Name = tabName
		btn.Text = tabName
		btn.Size = UDim2.new(0, 140, 0, 35)
		btn.BackgroundColor3 = THEME.ACCENT_BLUE
		btn.BackgroundTransparency = 1
		btn.TextColor3 = (tabName == "HOME") and THEME.TEXT_WHITE or Color3.fromRGB(150, 150, 160)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.Parent = navBar
		
		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(0, 4)
		btnCorner.Parent = btn
		
		-- Mouse unlock for all buttons
		btn.MouseEnter:Connect(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			if btn.Name ~= currentTab then
				btn.TextColor3 = THEME.TEXT_GOLD
			end
		end)
		
		btn.MouseLeave:Connect(function()
			if btn.Name ~= currentTab then
				btn.TextColor3 = Color3.fromRGB(150, 150, 160)
			end
		end)
		
		btn.MouseButton1Click:Connect(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			
			currentTab = tabName
			updateTabStyles()
			
			-- Handle tab-specific logic
			if tabName == "STORE" then
				local shop = screenGui:FindFirstChild("ShopFrame")
				if shop then shop.Visible = not shop.Visible end
			elseif tabName == "HOME" then
				-- Hide shop if open
				local shop = screenGui:FindFirstChild("ShopFrame")
				if shop then shop.Visible = false end
			else
				print("Tab clicked: " .. tabName .. " (not yet implemented)")
			end
		end)
	end

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
	-- 4. Right Side Panels (News/Promo)
	-- ============================================
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(0, 300, 0.6, 0)
	rightPanel.Position = UDim2.new(1, -20, 0.2, 0)
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.BackgroundTransparency = 1
	rightPanel.Parent = screenGui

	local rightList = Instance.new("UIListLayout")
	rightList.Padding = UDim.new(0, 15)
	rightList.Parent = rightPanel
	
	local promoTitles = {"FEATURED EVENT", "NEWS UPDATE"}

	for i = 1, 2 do
		local promo = Instance.new("TextButton")
		promo.Name = "Promo"..i
		promo.Size = UDim2.new(1, 0, 0.45, 0)
		promo.BackgroundColor3 = Color3.new(0,0,0)
		promo.BackgroundTransparency = 0.5
		promo.BorderSizePixel = 0
		promo.AutoButtonColor = false
		promo.Text = ""
		promo.Parent = rightPanel
		
		local promoStroke = Instance.new("UIStroke")
		promoStroke.Color = THEME.ACCENT_GOLD
		promoStroke.Transparency = 0.7
		promoStroke.Thickness = 1
		promoStroke.Parent = promo
		
		local promoCorner = Instance.new("UICorner")
		promoCorner.CornerRadius = UDim.new(0, 8)
		promoCorner.Parent = promo
		
		-- Title label
		local promoLabel = Instance.new("TextLabel")
		promoLabel.Size = UDim2.new(1, -20, 0, 30)
		promoLabel.Position = UDim2.new(0, 10, 0, 10)
		promoLabel.BackgroundTransparency = 1
		promoLabel.Text = promoTitles[i] or "PROMO"
		promoLabel.TextColor3 = THEME.ACCENT_GOLD
		promoLabel.Font = Enum.Font.GothamBold
		promoLabel.TextSize = 14
		promoLabel.TextXAlignment = Enum.TextXAlignment.Left
		promoLabel.Parent = promo
		
		-- Mouse handlers
		promo.MouseEnter:Connect(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			promo.BackgroundTransparency = 0.3
		end)
		
		promo.MouseLeave:Connect(function()
			promo.BackgroundTransparency = 0.5
		end)
		
		promo.MouseButton1Click:Connect(function()
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
			print("Promo Panel " .. i .. " clicked (not yet implemented)")
		end)
	end

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
	playCorner.CornerRadius = UDim.new(0, 25) -- Rounded pills
	playCorner.Parent = playBtn
	
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
			respawnRemote:FireServer()
			print("Quick Play: Spawning player...")
		else
			-- Fallback: Just spawn the character directly
			player:LoadCharacter()
			print("Quick Play: Loading character (fallback)...")
		end
	end)

	-- ============================================
	-- 6. Friend List (Collapsible Drawer)
	-- ============================================
	local friendPanel = Instance.new("Frame")
	friendPanel.Name = "FriendPanel"
	friendPanel.Size = UDim2.new(0, 250, 0.6, 0)
	friendPanel.Position = UDim2.new(1, -20, 0.2, 0) -- Same as right panel? No, usually separate.
	-- Let's put it on the far right, maybe toggleable.
	-- The image shows it integrated or as a sidebar.
	-- I'll make it a dedicated sidebar on the right, pushing the promo panels?
	-- Actually, let's make it a floating panel on the right edge.
	friendPanel.Position = UDim2.new(1, -10, 0.5, 0)
	friendPanel.AnchorPoint = Vector2.new(1, 0.5)
	friendPanel.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	friendPanel.BorderSizePixel = 0
	friendPanel.Visible = true -- Always visible in lobby?
	friendPanel.Parent = screenGui
	
	local friendStroke = Instance.new("UIStroke")
	friendStroke.Color = THEME.ACCENT_GOLD
	friendStroke.Transparency = 0.8
	friendStroke.Parent = friendPanel

	local friendTitle = Instance.new("TextLabel")
	friendTitle.Text = "SOCIAL"
	friendTitle.Size = UDim2.new(1, 0, 0, 30)
	friendTitle.BackgroundTransparency = 1
	friendTitle.TextColor3 = THEME.TEXT_GOLD
	friendTitle.Font = Enum.Font.GothamBold
	friendTitle.Parent = friendPanel

	local friendScroll = Instance.new("ScrollingFrame")
	friendScroll.Size = UDim2.new(1, 0, 1, -40)
	friendScroll.Position = UDim2.new(0, 0, 0, 40)
	friendScroll.BackgroundTransparency = 1
	friendScroll.BorderSizePixel = 0
	friendScroll.Parent = friendPanel
	
	local friendListLayout = Instance.new("UIListLayout")
	friendListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	friendListLayout.Padding = UDim.new(0, 5)
	friendListLayout.Parent = friendScroll

	-- Populate Friends (Online Only)
	task.spawn(function()
		while true do
			local success, friends = pcall(function()
				return Players.LocalPlayer:GetFriendsOnline(200)
			end)
			
			if success and friends then
				-- Clear existing
				for _, child in ipairs(friendScroll:GetChildren()) do
					if child:IsA("Frame") then child:Destroy() end
				end

				for _, friendInfo in ipairs(friends) do
					local fFrame = Instance.new("Frame")
					fFrame.Size = UDim2.new(1, -10, 0, 50)
					fFrame.BackgroundTransparency = 1
					fFrame.Parent = friendScroll
					
					local fName = Instance.new("TextLabel")
					fName.Text = friendInfo.UserName
					fName.Size = UDim2.new(0.6, 0, 0.5, 0)
					fName.Position = UDim2.new(0, 50, 0, 5)
					fName.BackgroundTransparency = 1
					fName.TextColor3 = THEME.TEXT_WHITE
					fName.TextXAlignment = Enum.TextXAlignment.Left
					fName.Font = Enum.Font.GothamBold
					fName.TextSize = 14
					fName.Parent = fFrame
					
					local fStatus = Instance.new("TextLabel")
					fStatus.Text = (friendInfo.LastLocation and friendInfo.LastLocation ~= "") and friendInfo.LastLocation or "Online"
					fStatus.Size = UDim2.new(0.6, 0, 0.5, 0)
					fStatus.Position = UDim2.new(0, 50, 0.5, -5)
					fStatus.BackgroundTransparency = 1
					fStatus.TextColor3 = Color3.fromRGB(150, 150, 150)
					fStatus.TextXAlignment = Enum.TextXAlignment.Left
					fStatus.Font = Enum.Font.Gotham
					fStatus.TextSize = 12
					fStatus.Parent = fFrame
					
					-- Avatar
					local fAvatar = Instance.new("ImageLabel")
					fAvatar.Size = UDim2.new(0, 40, 0, 40)
					fAvatar.Position = UDim2.new(0, 5, 0, 5)
					fAvatar.Image = "rbxassetid://0" 
					task.spawn(function()
						local content, isReady = Players:GetUserThumbnailAsync(friendInfo.VisitorId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
						if isReady then fAvatar.Image = content end
					end)
					fAvatar.Parent = fFrame
					fAvatar.BackgroundColor3 = Color3.new(0,0,0)
					local fAvCorner = Instance.new("UICorner")
					fAvCorner.CornerRadius = UDim.new(1, 0)
					fAvCorner.Parent = fAvatar
					
					-- Join Button (Only if in a game)
					if friendInfo.PlaceId and friendInfo.GameId then
						local joinBtn = Instance.new("ImageButton")
						joinBtn.Size = UDim2.new(0, 24, 0, 24)
						joinBtn.Position = UDim2.new(1, -30, 0.5, 0)
						joinBtn.AnchorPoint = Vector2.new(0, 0.5)
						joinBtn.BackgroundColor3 = THEME.ACCENT_BLUE
						joinBtn.Image = "rbxassetid://1234752" -- Arrow/Play icon
						joinBtn.Parent = fFrame
						
						local joinCorner = Instance.new("UICorner")
						joinCorner.CornerRadius = UDim.new(0, 4)
						joinCorner.Parent = joinBtn
						
						joinBtn.MouseButton1Click:Connect(function()
							print("Joining friend: " .. friendInfo.UserName)
							game:GetService("TeleportService"):TeleportToPlaceInstance(friendInfo.PlaceId, friendInfo.GameId, player)
						end)
					end
				end
			end
			task.wait(60) -- Refresh every minute
		end
	end)

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
