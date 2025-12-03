--[[
	Controller: LobbyController
	Description: Manages the lobby UI with 3D character viewport and play button
]]

local LobbyController = {}

function LobbyController.Start()
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
		bg.BackgroundColor3 = THEME.BG_DARK -- Use theme color instead of transparent
		bg.BackgroundTransparency = 0 -- Opaque background
		bg.BorderSizePixel = 0
		bg.Parent = screenGui

		-- Add a gradient for better visuals
		local bgGradient = Instance.new("UIGradient")
		bgGradient.Rotation = 90
		bgGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, THEME.BG_DARK),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(5, 8, 12)),
		})
		bgGradient.Parent = bg

		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "CharacterViewport"
		viewport.Size = UDim2.fromScale(1, 1)
		viewport.BackgroundTransparency = 1
		viewport.Ambient = Color3.fromRGB(150, 150, 150) -- Add some ambient light
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.LightDirection = Vector3.new(-1, -1, -1)
		viewport.Parent = bg

		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport

		local viewportCamera = Instance.new("Camera")
		viewportCamera.FieldOfView = 45 -- Lower FOV for better portrait look
		viewport.CurrentCamera = viewportCamera
		viewportCamera.Parent = viewport

		-- Add a platform INSIDE the ViewportFrame
		local platform = Instance.new("Part")
		platform.Size = Vector3.new(10, 1, 10)
		platform.Position = Vector3.new(0, -3, 0)
		platform.Anchored = true
		platform.Material = Enum.Material.Neon
		platform.Color = THEME.ACCENT_BLUE
		platform.Transparency = 0.5
		platform.Parent = worldModel

		local platformTexture = Instance.new("Texture")
		platformTexture.Texture = "rbxassetid://607929314"
		platformTexture.Face = Enum.NormalId.Top
		platformTexture.StudsPerTileU = 5
		platformTexture.StudsPerTileV = 5
		platformTexture.Transparency = 0.8
		platformTexture.Parent = platform

		-- Character Cloning & Animation
		local runService = game:GetService("RunService")
		local rotation = 0
		local viewmodelConnection

		local function updateViewmodel()
			worldModel:ClearAllChildren()

			local model = nil

			-- 1. Try to clone existing character
			local character = player.Character
			if character and character:FindFirstChild("Head") then
				character.Archivable = true
				model = character:Clone()
				character.Archivable = false
			end

			-- 2. Fallback: Load from UserId if clone failed
			if not model then
				local success, result = pcall(function()
					return Players:CreateHumanoidModelFromUserId(player.UserId)
				end)
				if success and result then
					model = result
				end
			end

			-- 3. Ultimate Fallback: Load Roblox (UserId 1) if player load failed
			if not model then
				local success, result = pcall(function()
					return Players:CreateHumanoidModelFromUserId(1) -- Roblox
				end)
				if success and result then
					model = result
				end
			end

			if not model then
				warn("Could not load any character for lobby")
				return
			end

			model.Name = "ViewmodelCharacter"
			model.Parent = worldModel

			-- Ensure PrimaryPart
			if not model.PrimaryPart then
				model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
					or model:FindFirstChild("Torso")
					or model:FindFirstChild("UpperTorso")
			end

			-- Anchor ONLY PrimaryPart (Root), Unanchor others for Motor6D to work
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					if part == model.PrimaryPart then
						part.Anchored = true
					else
						part.Anchored = false
					end
					part.CanCollide = false
				end
			end

			-- Position at origin
			if model.PrimaryPart then
				-- Center vertically
				model:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(180), 0))
			end

			-- Force T-Pose (Rotate limbs)
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("Motor6D") then
					local name = desc.Name
					-- R15 T-Pose
					if name == "Left Shoulder" or name == "LeftShoulder" then
						desc.C0 = CFrame.new(-1, 0.5, 0) * CFrame.Angles(0, 0, math.rad(-90))
					elseif name == "Right Shoulder" or name == "RightShoulder" then
						desc.C0 = CFrame.new(1, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
					elseif name == "Left Hip" or name == "LeftHip" then
						desc.C0 = CFrame.new(-1, -1, 0) * CFrame.Angles(0, 0, math.rad(-20)) -- Slight leg spread
					elseif name == "Right Hip" or name == "RightHip" then
						desc.C0 = CFrame.new(1, -1, 0) * CFrame.Angles(0, 0, math.rad(20)) -- Slight leg spread
					end
				end
			end
		end

		local function enableViewmodel()
			updateViewmodel()

			if viewmodelConnection then
				viewmodelConnection:Disconnect()
			end
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
			if mainHud then
				mainHud.Enabled = false
			end

			-- Hide Mutation HUD if it exists
			local mutationHud = playerGui:FindFirstChild("MutationHUD")
			if mutationHud then
				mutationHud.Enabled = false
			end

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
			if mainHud then
				mainHud.Enabled = true
			end

			-- Show Mutation HUD
			local mutationHud = playerGui:FindFirstChild("MutationHUD")
			if mutationHud then
				mutationHud.Enabled = true
			end
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
		navBar.BackgroundColor3 = Color3.new(0, 0, 0)
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
		local statNames = { "BIOMASS", "DNA", "KILLS" }

		for i, statName in ipairs(statNames) do
			local label = Instance.new("TextLabel")
			label.Name = statName .. "Label"
			label.Size = UDim2.new(1, 0, 0, 22)
			label.Position = UDim2.new(0, 0, 0, (i - 1) * 25)
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

		-- Request saved DNA from server (attributes may not be set yet at load time)
		task.spawn(function()
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes", 10)
			if remotes then
				local reqRemote = remotes:WaitForChild("RequestMetaData", 10)
				if reqRemote then
					local dna, _upgrades, _biomass = reqRemote:InvokeServer()
					if dna then
						statsLabels["DNA"].Text = "DNA: " .. math.floor(dna)
					end
				end
			end
		end)

		-- ============================================
		-- 2c. How To Play Section (Below Stats)
		-- ============================================
		local howToPlayFrame = Instance.new("Frame")
		howToPlayFrame.Name = "HowToPlayFrame"
		howToPlayFrame.Size = UDim2.new(0, 340, 0, 190)
		howToPlayFrame.Position = UDim2.new(0, 20, 0, 155) -- Below stats frame
		howToPlayFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
		howToPlayFrame.BackgroundTransparency = 0.6
		howToPlayFrame.BorderSizePixel = 0
		howToPlayFrame.Parent = screenGui

		local howToPlayCorner = Instance.new("UICorner")
		howToPlayCorner.CornerRadius = UDim.new(0, 8)
		howToPlayCorner.Parent = howToPlayFrame

		local howToPlayStroke = Instance.new("UIStroke")
		howToPlayStroke.Color = THEME.ACCENT_GOLD
		howToPlayStroke.Thickness = 1
		howToPlayStroke.Transparency = 0.5
		howToPlayStroke.Parent = howToPlayFrame

		local howToPlayPadding = Instance.new("UIPadding")
		howToPlayPadding.PaddingLeft = UDim.new(0, 12)
		howToPlayPadding.PaddingRight = UDim.new(0, 12)
		howToPlayPadding.PaddingTop = UDim.new(0, 10)
		howToPlayPadding.PaddingBottom = UDim.new(0, 10)
		howToPlayPadding.Parent = howToPlayFrame

		local howToPlayTitle = Instance.new("TextLabel")
		howToPlayTitle.Name = "Title"
		howToPlayTitle.Size = UDim2.new(1, 0, 0, 22)
		howToPlayTitle.BackgroundTransparency = 1
		howToPlayTitle.Text = "HOW TO PLAY"
		howToPlayTitle.TextColor3 = THEME.ACCENT_GOLD
		howToPlayTitle.TextSize = 16
		howToPlayTitle.Font = Enum.Font.GothamBlack
		howToPlayTitle.TextXAlignment = Enum.TextXAlignment.Left
		howToPlayTitle.Parent = howToPlayFrame

		local tipsList = {
			"🔹 Pick up orbs to sustain yourself",
			"🔹 Hunt players & bots for real Biomass gains",
			"🔹 Buy Mutations in the shop to get stronger",
			"🔹 Reach Level 50 to WIN and earn a huge DNA",
			"🔹 Use Yeetcannons around the map to get yeeted!",
			"🔹 DNA and Mutations persist between sessions!",
		}

		for i, tip in ipairs(tipsList) do
			local tipLabel = Instance.new("TextLabel")
			tipLabel.Name = "Tip" .. i
			tipLabel.Size = UDim2.new(1, 0, 0, 22)
			tipLabel.Position = UDim2.new(0, 0, 0, 22 + (i - 1) * 24)
			tipLabel.BackgroundTransparency = 1
			tipLabel.Text = tip
			tipLabel.TextColor3 = THEME.TEXT_WHITE
			tipLabel.TextSize = 13
			tipLabel.Font = Enum.Font.Gotham
			tipLabel.TextXAlignment = Enum.TextXAlignment.Left
			tipLabel.TextWrapped = true
			tipLabel.Parent = howToPlayFrame
		end

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
		playBtn.AutoButtonColor = false -- Disable auto color change
		playBtn.Parent = playArea

		-- Start disabled (gray)
		local isServerReady = false
		playBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 80) -- Gray
		playBtn.Text = "LOADING..."
		playBtn.TextTransparency = 0.5

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

		-- Wait for server ready signal
		task.spawn(function()
			local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Blaster"):WaitForChild("Remotes", 30)
			if remotes then
				local serverReadyEvent = remotes:WaitForChild("ServerReady", 30)
				if serverReadyEvent then
					serverReadyEvent.OnClientEvent:Wait()
					isServerReady = true
					playBtn.BackgroundColor3 = THEME.BUTTON_PLAY
					playBtn.Text = "QUICK PLAY"
					playBtn.TextTransparency = 0
					print("✅ LobbyController: Server ready, Quick Play enabled")
				end
			end
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
			-- Check if server is ready
			if not isServerReady then
				warn("❌ Quick Play: Server not ready yet!")
				return
			end
			-- Hide Lobby and re-enable HUD
			screenGui.Enabled = false
			disableViewmodel()

			-- Enable Game HUD
			local hud = playerGui:FindFirstChild("HUD")
			if hud then
				hud.Enabled = true
			end

			-- Enable Mutation HUD
			local mutationHud = playerGui:FindFirstChild("MutationHUD")
			if mutationHud then
				mutationHud.Enabled = true
			end

			-- Restore Camera
			local camera = workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Custom

			-- Unlock mouse for gameplay
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true

			-- Request spawn/respawn from server
			local remotes = game:GetService("ReplicatedStorage"):WaitForChild("Blaster"):WaitForChild("Remotes")
			local respawnRemote = remotes:WaitForChild("RequestRespawn", 30)
			if respawnRemote then
				respawnRemote:FireServer(true) -- true = skip death (safe spawn)
				print("Quick Play: Spawning player...")
			else
				warn("❌ Quick Play Error: RequestRespawn remote not found!")
				-- player:LoadCharacter() -- REMOVED: Cannot be called from client
			end
		end)

		-- Initial Lobby Setup
		local function setupLobbyState()
			-- Override Camera to look at nothing (since we use ViewportFrame)
			local camera = workspace.CurrentCamera
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.new(0, 10000, 0) -- Far away

			-- Hide HUD (Non-blocking)
			task.spawn(function()
				local hud = playerGui:WaitForChild("HUD", 10)
				if hud then
					hud.Enabled = false
				end

				local mutationHud = playerGui:WaitForChild("MutationHUD", 10)
				if mutationHud then
					mutationHud.Enabled = false
				end
			end)
		end

		-- Call setup immediately
		setupLobbyState()

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
		closeShop.TextColor3 = Color3.new(1, 1, 1)
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

	print("✅ LobbyController: Started")
end

return LobbyController
