local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local remotes = ReplicatedStorage:WaitForChild("AdminRemotes", 10)

if not remotes then
	warn("AdminPanel: Could not find AdminRemotes folder")
	return
end

-- Create GUI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AdminPanel"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false -- Hidden by default
screenGui.DisplayOrder = 100 -- High priority to be on top
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "MainFrame"
frame.Size = UDim2.new(0, 250, 0, 600) -- Increased height for speed and mutation controls
frame.Position = UDim2.new(0.05, 0, 0.5, -300) -- Adjusted to center vertically
frame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
frame.BorderSizePixel = 0
frame.Active = true -- Allow input
frame.Selectable = true
frame.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = frame

local title = Instance.new("TextLabel")
title.Text = "Testing Panel (F2)"
title.Size = UDim2.new(1, 0, 0, 30)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.Parent = frame

local listLayout = Instance.new("UIListLayout")
listLayout.Parent = frame
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.Padding = UDim.new(0, 10)
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
listLayout.SortOrder = Enum.SortOrder.LayoutOrder

local padding = Instance.new("UIPadding")
padding.Parent = frame
padding.PaddingTop = UDim.new(0, 40)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 10)
padding.PaddingRight = UDim.new(0, 10)

-- Helper to create buttons
local function createButton(text, layoutOrder)
	local btn = Instance.new("TextButton")
	btn.Text = text
	btn.Size = UDim2.new(1, 0, 0, 35)
	btn.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	btn.TextColor3 = Color3.new(1, 1, 1)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.LayoutOrder = layoutOrder

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	btn.Parent = frame
	return btn
end

-- Stats Display
local statsLabel = Instance.new("TextLabel")
statsLabel.Text = "Stats Loading..."
statsLabel.Size = UDim2.new(1, 0, 0, 60)
statsLabel.BackgroundTransparency = 1
statsLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
statsLabel.TextSize = 12
statsLabel.Font = Enum.Font.Code
statsLabel.TextXAlignment = Enum.TextXAlignment.Left
statsLabel.LayoutOrder = 1
statsLabel.Parent = frame

-- Level Control
local levelContainer = Instance.new("Frame")
levelContainer.Size = UDim2.new(1, 0, 0, 35)
levelContainer.BackgroundTransparency = 1
levelContainer.LayoutOrder = 2
levelContainer.Parent = frame

local levelInput = Instance.new("TextBox")
levelInput.Size = UDim2.new(0.6, -5, 1, 0)
levelInput.Position = UDim2.new(0, 0, 0, 0)
levelInput.PlaceholderText = "Level (1-100)"
levelInput.Text = ""
levelInput.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
levelInput.TextColor3 = Color3.new(0, 0, 0)
levelInput.Font = Enum.Font.Gotham
levelInput.TextSize = 14
levelInput.Parent = levelContainer
local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 6)
inputCorner.Parent = levelInput

local setLevelBtn = Instance.new("TextButton")
setLevelBtn.Text = "Set Lvl"
setLevelBtn.Size = UDim2.new(0.4, -5, 1, 0)
setLevelBtn.Position = UDim2.new(0.6, 5, 0, 0)
setLevelBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 215)
setLevelBtn.TextColor3 = Color3.new(1, 1, 1)
setLevelBtn.Font = Enum.Font.GothamBold
setLevelBtn.TextSize = 14
setLevelBtn.Parent = levelContainer
local btnCorner = Instance.new("UICorner")
btnCorner.CornerRadius = UDim.new(0, 6)
btnCorner.Parent = setLevelBtn

-- Bot Controls
local botContainer = Instance.new("Frame")
botContainer.Size = UDim2.new(1, 0, 0, 35)
botContainer.BackgroundTransparency = 1
botContainer.LayoutOrder = 3
botContainer.Parent = frame

local selectBotBtn = Instance.new("TextButton")
selectBotBtn.Text = "Select Bot"
selectBotBtn.Size = UDim2.new(0.48, 0, 1, 0)
selectBotBtn.Position = UDim2.new(0, 0, 0, 0)
selectBotBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 0)
selectBotBtn.TextColor3 = Color3.new(1, 1, 1)
selectBotBtn.Font = Enum.Font.GothamBold
selectBotBtn.TextSize = 13
selectBotBtn.Parent = botContainer
local selectCorner = Instance.new("UICorner")
selectCorner.CornerRadius = UDim.new(0, 6)
selectCorner.Parent = selectBotBtn

local setBotLevelBtn = Instance.new("TextButton")
setBotLevelBtn.Text = "Set Bot Lvl"
setBotLevelBtn.Size = UDim2.new(0.48, 0, 1, 0)
setBotLevelBtn.Position = UDim2.new(0.52, 0, 0, 0)
setBotLevelBtn.BackgroundColor3 = Color3.fromRGB(180, 0, 100)
setBotLevelBtn.TextColor3 = Color3.new(1, 1, 1)
setBotLevelBtn.Font = Enum.Font.GothamBold
setBotLevelBtn.TextSize = 13
setBotLevelBtn.Parent = botContainer
local setBotCorner = Instance.new("UICorner")
setBotCorner.CornerRadius = UDim.new(0, 6)
setBotCorner.Parent = setBotLevelBtn

-- Speed Control
local speedContainer = Instance.new("Frame")
speedContainer.Size = UDim2.new(1, 0, 0, 35)
speedContainer.BackgroundTransparency = 1
speedContainer.LayoutOrder = 4
speedContainer.Parent = frame

local speedInput = Instance.new("TextBox")
speedInput.Size = UDim2.new(0.6, -5, 1, 0)
speedInput.Position = UDim2.new(0, 0, 0, 0)
speedInput.PlaceholderText = "Speed (16-100)"
speedInput.Text = ""
speedInput.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
speedInput.TextColor3 = Color3.new(0, 0, 0)
speedInput.Font = Enum.Font.Gotham
speedInput.TextSize = 14
speedInput.Parent = speedContainer
local speedInputCorner = Instance.new("UICorner")
speedInputCorner.CornerRadius = UDim.new(0, 6)
speedInputCorner.Parent = speedInput

local setSpeedBtn = Instance.new("TextButton")
setSpeedBtn.Text = "Set Speed"
setSpeedBtn.Size = UDim2.new(0.4, -5, 1, 0)
setSpeedBtn.Position = UDim2.new(0.6, 5, 0, 0)
setSpeedBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 120)
setSpeedBtn.TextColor3 = Color3.new(1, 1, 1)
setSpeedBtn.Font = Enum.Font.GothamBold
setSpeedBtn.TextSize = 14
setSpeedBtn.Parent = speedContainer
local speedBtnCorner = Instance.new("UICorner")
speedBtnCorner.CornerRadius = UDim.new(0, 6)
speedBtnCorner.Parent = setSpeedBtn

-- Mutation Controls
local mutationContainer = Instance.new("Frame")
mutationContainer.Size = UDim2.new(1, 0, 0, 35)
mutationContainer.BackgroundTransparency = 1
mutationContainer.LayoutOrder = 5
mutationContainer.Parent = frame

local mutationInput = Instance.new("TextBox")
mutationInput.Size = UDim2.new(1, 0, 0.45, 0)
mutationInput.Position = UDim2.new(0, 0, 0, 0)
mutationInput.PlaceholderText = "Mutation Name"
mutationInput.Text = ""
mutationInput.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
mutationInput.TextColor3 = Color3.new(0, 0, 0)
mutationInput.Font = Enum.Font.Gotham
mutationInput.TextSize = 12
mutationInput.Parent = mutationContainer
local mutInputCorner = Instance.new("UICorner")
mutInputCorner.CornerRadius = UDim.new(0, 6)
mutInputCorner.Parent = mutationInput

local mutationBtnContainer = Instance.new("Frame")
mutationBtnContainer.Size = UDim2.new(1, 0, 0.5, 0)
mutationBtnContainer.Position = UDim2.new(0, 0, 0.55, 0)
mutationBtnContainer.BackgroundTransparency = 1
mutationBtnContainer.Parent = mutationContainer

local addMutationBtn = Instance.new("TextButton")
addMutationBtn.Text = "Add"
addMutationBtn.Size = UDim2.new(0.48, 0, 1, 0)
addMutationBtn.Position = UDim2.new(0, 0, 0, 0)
addMutationBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
addMutationBtn.TextColor3 = Color3.new(1, 1, 1)
addMutationBtn.Font = Enum.Font.GothamBold
addMutationBtn.TextSize = 13
addMutationBtn.Parent = mutationBtnContainer
local addMutCorner = Instance.new("UICorner")
addMutCorner.CornerRadius = UDim.new(0, 6)
addMutCorner.Parent = addMutationBtn

local removeMutationBtn = Instance.new("TextButton")
removeMutationBtn.Text = "Remove"
removeMutationBtn.Size = UDim2.new(0.48, 0, 1, 0)
removeMutationBtn.Position = UDim2.new(0.52, 0, 0, 0)
removeMutationBtn.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
removeMutationBtn.TextColor3 = Color3.new(1, 1, 1)
removeMutationBtn.Font = Enum.Font.GothamBold
removeMutationBtn.TextSize = 13
removeMutationBtn.Parent = mutationBtnContainer
local removeMutCorner = Instance.new("UICorner")
removeMutCorner.CornerRadius = UDim.new(0, 6)
removeMutCorner.Parent = removeMutationBtn

-- Buttons
local addXPBtn = createButton("+1000 XP", 6)
local addGlobalXPBtn = createButton("+1000 GlobalXP", 7)
local godModeBtn = createButton("God Mode: OFF", 8)
local infAmmoBtn = createButton("Inf Ammo: OFF", 9)

-- Logic
local godMode = false
local infAmmo = false
local selectedBot = nil

UserInputService.InputBegan:Connect(function(input, processed)
	-- if processed then return end -- Don't ignore processed here so we can open it even if something else is focused,
	-- OR we check if it's strictly F2 and not typing in a text box.

	if input.KeyCode == Enum.KeyCode.F2 then
		screenGui.Enabled = not screenGui.Enabled
		print("AdminPanel Toggled:", screenGui.Enabled)

		-- Toggle Mouse Behavior
		if screenGui.Enabled then
			UserInputService.MouseIconEnabled = true
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			-- Use a TextButton for Modal as Frames don't have it
			local modalButton = screenGui:FindFirstChild("ModalButton")
			if not modalButton then
				modalButton = Instance.new("TextButton")
				modalButton.Name = "ModalButton"
				modalButton.BackgroundTransparency = 1
				modalButton.Text = ""
				modalButton.Size = UDim2.new(0, 0, 0, 0)
				modalButton.Modal = true
				modalButton.Parent = screenGui
			end
			modalButton.Modal = true
		else
			-- Reset to gameplay default (assuming locked center)
			UserInputService.MouseIconEnabled = false
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			local modalButton = screenGui:FindFirstChild("ModalButton")
			if modalButton then
				modalButton.Modal = false
			end
		end
	end
end)

-- Select nearest bot
selectBotBtn.MouseButton1Click:Connect(function()
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then
		print("❌ No character found")
		return
	end
	
	local myPos = char.HumanoidRootPart.Position
	local closestBot = nil
	local closestDist = math.huge
	
	local CollectionService = game:GetService("CollectionService")
	for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
		if bot:IsA("Model") and bot:FindFirstChild("HumanoidRootPart") then
			local dist = (bot.HumanoidRootPart.Position - myPos).Magnitude
			if dist < closestDist then
				closestDist = dist
				closestBot = bot
			end
		end
	end
	
	if closestBot then
		selectedBot = closestBot
		local botLevel = selectedBot:GetAttribute("Level") or 1
		selectBotBtn.Text = string.format("%s (Lv%d)", selectedBot.Name, botLevel)
		selectBotBtn.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
		print("✅ Selected bot:", selectedBot.Name, "Level:", botLevel, "Distance:", math.floor(closestDist))
	else
		print("❌ No bots found nearby")
	end
end)

-- Set selected bot's level
setBotLevelBtn.MouseButton1Click:Connect(function()
	if not selectedBot or not selectedBot.Parent then
		print("❌ No bot selected or bot was destroyed")
		selectBotBtn.Text = "Select Bot"
		selectBotBtn.BackgroundColor3 = Color3.fromRGB(180, 100, 0)
		selectedBot = nil
		return
	end
	
	local lvl = tonumber(levelInput.Text)
	if not lvl then
		print("❌ Invalid level input")
		return
	end
	
	print("🤖 Setting bot", selectedBot.Name, "to level", lvl)
	remotes.SetBotLevel:FireServer(selectedBot, lvl)
end)

setLevelBtn.MouseButton1Click:Connect(function()
	local lvl = tonumber(levelInput.Text)
	print("🖱️ SetLevel clicked. Input:", levelInput.Text)
	if lvl then
		remotes.SetLevel:FireServer(lvl)
	end
end)

addXPBtn.MouseButton1Click:Connect(function()
	print("🖱️ AddXP clicked")
	remotes.AddXP:FireServer(1000)
end)

addGlobalXPBtn.MouseButton1Click:Connect(function()
	print("🖱️ AddGlobalXP clicked")
	remotes.AddGlobalXP:FireServer(1000)
end)

godModeBtn.MouseButton1Click:Connect(function()
	godMode = not godMode
	print("🖱️ GodMode toggled:", godMode)
	godModeBtn.Text = "God Mode: " .. (godMode and "ON" or "OFF")
	godModeBtn.BackgroundColor3 = godMode and Color3.fromRGB(0, 180, 0) or Color3.fromRGB(60, 60, 60)
	remotes.ToggleGodMode:FireServer(godMode)
end)

infAmmoBtn.MouseButton1Click:Connect(function()
	infAmmo = not infAmmo
	print("🖱️ InfAmmo toggled:", infAmmo)
	infAmmoBtn.Text = "Inf Ammo: " .. (infAmmo and "ON" or "OFF")
	infAmmoBtn.BackgroundColor3 = infAmmo and Color3.fromRGB(0, 180, 0) or Color3.fromRGB(60, 60, 60)
	remotes.ToggleInfiniteAmmo:FireServer(infAmmo)
end)

setSpeedBtn.MouseButton1Click:Connect(function()
	local speed = tonumber(speedInput.Text)
	print("🖱️ SetSpeed clicked. Input:", speedInput.Text)
	if speed then
		remotes.SetSpeed:FireServer(speed)
	end
end)

addMutationBtn.MouseButton1Click:Connect(function()
	local mutationName = mutationInput.Text
	if mutationName and mutationName ~= "" then
		print("🖱️ AddMutation clicked. Mutation:", mutationName)
		remotes.AddMutation:FireServer(mutationName)
	else
		print("❌ Please enter a mutation name")
	end
end)

removeMutationBtn.MouseButton1Click:Connect(function()
	local mutationName = mutationInput.Text
	if mutationName and mutationName ~= "" then
		print("🖱️ RemoveMutation clicked. Mutation:", mutationName)
		remotes.RemoveMutation:FireServer(mutationName)
	else
		print("❌ Please enter a mutation name")
	end
end)

-- Update Stats Loop
RunService.RenderStepped:Connect(function()
	if not screenGui.Enabled then
		return
	end

	local char = player.Character
	if not char then
		return
	end

	local humanoid = char:FindFirstChild("Humanoid")
	local tool = char:FindFirstChildOfClass("Tool")

	local hp = humanoid and math.floor(humanoid.Health) or 0
	local maxHp = humanoid and math.floor(humanoid.MaxHealth) or 0
	local ammo = tool and tool:GetAttribute("Ammo") or "N/A"
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0

	statsLabel.Text = string.format("HP: %d/%d\nLevel: %d\nXP: %d\nAmmo: %s", hp, maxHp, level, xp, tostring(ammo))
end)

print("✅ AdminPanel: Loaded (Press F2)")
