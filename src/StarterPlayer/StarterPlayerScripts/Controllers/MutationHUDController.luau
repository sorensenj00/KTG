--[[
    MutationHUDController
    Displays owned mutations in a "Traits" style HUD on the right side of the screen.
    Listens to UpdateMetaEvent and updates the display when mutations change.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local MutationHUDController = {}

-- References
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local MutationConfig = require(ReplicatedStorage.GameLoop.MutationConfig)

-- UI Elements
local screenGui = nil
local mutationListFrame = nil
local mutationCards = {}

-- Theme
local THEME = {
	BG_DARK = Color3.fromRGB(20, 20, 25),
	BG_CARD = Color3.fromRGB(25, 25, 30),
	TEXT_WHITE = Color3.fromRGB(255, 255, 255),
	TEXT_GRAY = Color3.fromRGB(180, 180, 180),
	STROKE_DARK = Color3.fromRGB(50, 50, 60),
}

-- local TweenService = game:GetService("TweenService")
-- local UserInputService = game:GetService("UserInputService")

-- Create the main HUD UI
local function createMutationHUD()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MutationHUD"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 200 -- Ensure it renders on top of Lobby UI (DisplayOrder 100)
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Main container on the right side
	local container = Instance.new("Frame")
	container.Name = "MutationContainer"
	-- Collapsed state: Small header only
	container.Size = UDim2.new(0, 250, 0, 400) -- Always expanded
	container.Position = UDim2.new(1, -260, 0, 80) -- Right side, below top bar
	container.BackgroundTransparency = 1 -- Transparent background
	container.BorderSizePixel = 0
	container.ClipsDescendants = true
	container.Parent = screenGui

	-- Removed Border/Stroke for cleaner look
	-- local containerStroke = Instance.new("UIStroke") ...

	-- Title
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 40)
	title.BackgroundTransparency = 1
	title.Text = "MUTATIONS (M)"
	title.TextColor3 = Color3.fromRGB(255, 150, 0)
	title.TextSize = 18
	title.Font = Enum.Font.GothamBold
	title.TextStrokeTransparency = 0.5
	title.Parent = container

	-- Scrolling frame for mutations
	mutationListFrame = Instance.new("ScrollingFrame")
	mutationListFrame.Name = "MutationList"
	mutationListFrame.Size = UDim2.new(1, -10, 1, -40)
	mutationListFrame.Position = UDim2.new(0, 5, 0, 40)
	mutationListFrame.BackgroundTransparency = 1
	mutationListFrame.ScrollBarThickness = 4
	mutationListFrame.BorderSizePixel = 0
	mutationListFrame.Parent = container

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 5)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = mutationListFrame

	-- Update canvas size when content changes
	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		mutationListFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y)
	end)

	-- Dynamic Resizing Logic Removed (Static Display)
	-- local expandedSize = UDim2.new(0, 250, 0, 400)
	-- local collapsedSize = UDim2.new(0, 250, 0, 40)

	-- container.MouseEnter:Connect(function()
	--     TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	--         Size = expandedSize,
	--         BackgroundTransparency = 0.1
	--     }):Play()
	--     title.Text = "MUTATIONS"
	-- end)

	-- container.MouseLeave:Connect(function()
	--     TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
	--         Size = collapsedSize,
	--         BackgroundTransparency = 0.3
	--     }):Play()
	--     title.Text = "MUTATIONS (Hover)"
	-- end)
end

-- Create a mutation card
local function createMutationCard(mutationName, level)
	local mutationData = MutationConfig.Mutations[mutationName]
	if not mutationData then
		return nil
	end

	local card = Instance.new("Frame")
	card.Name = mutationName
	card.Size = UDim2.new(1, -10, 0, 45) -- Compact height (was 60)
	card.BackgroundColor3 = THEME.BG_CARD
	card.BackgroundTransparency = 0.6 -- Glass look
	card.BorderSizePixel = 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 6)
	cardCorner.Parent = card

	-- Rarity border (Thinner)
	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = MutationConfig.RarityColors[mutationData.Rarity] or Color3.new(1, 1, 1)
	cardStroke.Thickness = 1 -- Thinner stroke
	cardStroke.Transparency = 0.5 -- Subtle stroke
	cardStroke.Parent = card

	-- Icon (Smaller)
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.Size = UDim2.new(0, 30, 0, 30) -- Smaller icon
	icon.Position = UDim2.new(0, 8, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = mutationData.ImageId or "rbxasset://textures/ui/GuiImagePlaceholder.png"
	icon.Parent = card

	-- Mutation name
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -100, 0, 16)
	nameLabel.Position = UDim2.new(0, 45, 0, 6)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = mutationName
	nameLabel.TextColor3 = THEME.TEXT_WHITE
	nameLabel.TextSize = 12 -- Smaller font
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	-- Level display
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, -100, 0, 14)
	levelLabel.Position = UDim2.new(0, 45, 0, 24)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = string.format("Level %d / %d", level, mutationData.MaxLevel)
	levelLabel.TextColor3 = THEME.TEXT_GRAY
	levelLabel.TextSize = 10 -- Smaller font
	levelLabel.Font = Enum.Font.Gotham
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Parent = card

	-- Level badge (right side)
	local levelBadge = Instance.new("TextLabel")
	levelBadge.Name = "LevelBadge"
	levelBadge.Size = UDim2.new(0, 24, 0, 24) -- Smaller badge
	levelBadge.Position = UDim2.new(1, -30, 0.5, 0)
	levelBadge.AnchorPoint = Vector2.new(0, 0.5)
	levelBadge.BackgroundColor3 = MutationConfig.RarityColors[mutationData.Rarity] or Color3.new(1, 1, 1)
	levelBadge.BackgroundTransparency = 0.2
	levelBadge.Text = tostring(level)
	levelBadge.TextColor3 = Color3.fromRGB(20, 20, 20)
	levelBadge.TextSize = 14 -- Smaller text
	levelBadge.Font = Enum.Font.GothamBlack
	levelBadge.Parent = card

	local badgeCorner = Instance.new("UICorner")
	badgeCorner.CornerRadius = UDim.new(1, 0) -- Circle
	badgeCorner.Parent = levelBadge

	return card
end

-- Update the mutation display
local function updateMutationDisplay(metaData)
	if not metaData or not metaData.Upgrades then
		return
	end

	-- Clear existing cards
	for _, card in pairs(mutationCards) do
		card:Destroy()
	end
	mutationCards = {}

	-- Convert upgrades to sorted list
	local sortedMutations = {}
	for mutationName, level in pairs(metaData.Upgrades) do
		if level > 0 then -- Only show purchased mutations
			table.insert(sortedMutations, {
				Name = mutationName,
				Level = level,
			})
		end
	end

	-- Sort by level (highest first)
	table.sort(sortedMutations, function(a, b)
		if a.Level == b.Level then
			return a.Name < b.Name -- Alphabetical if same level
		end
		return a.Level > b.Level
	end)

	-- Create cards for each mutation
	for i, mutation in ipairs(sortedMutations) do
		local card = createMutationCard(mutation.Name, mutation.Level)
		if card then
			card.LayoutOrder = i
			card.Parent = mutationListFrame
			mutationCards[mutation.Name] = card
		end
	end
end

function MutationHUDController.Start()
	createMutationHUD()

	-- Listen to meta data updates
	local updateMetaEvent = ReplicatedStorage:WaitForChild("UpdateMetaEvent")
	updateMetaEvent.OnClientEvent:Connect(function(metaData)
		updateMutationDisplay(metaData)
	end)

	-- Request initial data (fixes race condition where server fires before we're listening)
	task.spawn(function()
		local blaster = ReplicatedStorage:WaitForChild("Blaster", 10)
		if blaster then
			local remotes = blaster:WaitForChild("Remotes", 10)
			if remotes then
				local reqFunc = remotes:WaitForChild("RequestMetaData", 10)
				if reqFunc then
					local upgrades, biomass = reqFunc:InvokeServer()
					if upgrades then
						updateMutationDisplay({ Upgrades = upgrades, Biomass = biomass })
					end
				end
			end
		end
	end)

	-- Keybind (M) to toggle HUD
	local UserInputService = game:GetService("UserInputService")
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.M then
			if screenGui and screenGui.Enabled then
				-- Toggle container visibility or just the whole GUI?
				-- Let's toggle the container's visibility or size.
				-- The request says "opens the tab to see your mutations".
				-- Assuming the HUD is always there but maybe we want to collapse/expand it?
				-- Or just toggle the whole GUI if it's meant to be a toggle.
				-- Given "HUD", it's usually always on. But the user said "opens the tab".
				-- Let's toggle the `MutationList` visibility for now, or the whole container.
				-- Toggle only the list, keeping the title visible
				if mutationListFrame then
					mutationListFrame.Visible = not mutationListFrame.Visible
				end
			end
		end
	end)

	print("MutationHUDController started")
end

return MutationHUDController
