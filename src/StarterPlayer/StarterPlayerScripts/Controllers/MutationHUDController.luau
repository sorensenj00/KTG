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

local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Create the main HUD UI
local function createMutationHUD()
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MutationHUD"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = playerGui

    -- Main container on the right side
    local container = Instance.new("Frame")
    container.Name = "MutationContainer"
    -- Collapsed state: Small header only
    container.Size = UDim2.new(0, 250, 0, 40)
    container.Position = UDim2.new(1, -260, 0, 80) -- Right side, below top bar
    container.BackgroundColor3 = THEME.BG_DARK
    container.BackgroundTransparency = 0.3
    container.BorderSizePixel = 0
    container.ClipsDescendants = true -- Hide content when collapsed
    container.Parent = screenGui

    local containerCorner = Instance.new("UICorner")
    containerCorner.CornerRadius = UDim.new(0, 8)
    containerCorner.Parent = container

    local containerStroke = Instance.new("UIStroke")
    containerStroke.Color = THEME.STROKE_DARK
    containerStroke.Thickness = 2
    containerStroke.Parent = container

    -- Title
    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Size = UDim2.new(1, 0, 0, 40)
    title.BackgroundTransparency = 1
    title.Text = "MUTATIONS (Hover)"
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

    -- Dynamic Resizing Logic
    local expandedSize = UDim2.new(0, 250, 0, 400)
    local collapsedSize = UDim2.new(0, 250, 0, 40)

    container.MouseEnter:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = expandedSize,
            BackgroundTransparency = 0.1
        }):Play()
        title.Text = "MUTATIONS"
    end)

    container.MouseLeave:Connect(function()
        TweenService:Create(container, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
            Size = collapsedSize,
            BackgroundTransparency = 0.3
        }):Play()
        title.Text = "MUTATIONS (Hover)"
    end)
end

-- Create a mutation card
local function createMutationCard(mutationName, level)
    local mutationData = MutationConfig.Mutations[mutationName]
    if not mutationData then return nil end

    local card = Instance.new("Frame")
    card.Name = mutationName
    card.Size = UDim2.new(1, -10, 0, 60)
    card.BackgroundColor3 = THEME.BG_CARD
    card.BorderSizePixel = 0

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 6)
    cardCorner.Parent = card

    -- Rarity border
    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = MutationConfig.RarityColors[mutationData.Rarity] or Color3.new(1, 1, 1)
    cardStroke.Thickness = 2
    cardStroke.Parent = card

    -- Icon
    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 40, 0, 40)
    icon.Position = UDim2.new(0, 10, 0.5, 0)
    icon.AnchorPoint = Vector2.new(0, 0.5)
    icon.BackgroundTransparency = 1
    icon.Image = mutationData.ImageId or "rbxasset://textures/ui/GuiImagePlaceholder.png"
    icon.Parent = card

    -- Mutation name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "NameLabel"
    nameLabel.Size = UDim2.new(1, -120, 0, 20)
    nameLabel.Position = UDim2.new(0, 55, 0, 8)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = mutationName
    nameLabel.TextColor3 = THEME.TEXT_WHITE
    nameLabel.TextSize = 14
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = card

    -- Level display
    local levelLabel = Instance.new("TextLabel")
    levelLabel.Name = "LevelLabel"
    levelLabel.Size = UDim2.new(1, -120, 0, 18)
    levelLabel.Position = UDim2.new(0, 55, 0, 32)
    levelLabel.BackgroundTransparency = 1
    levelLabel.Text = string.format("Level %d / %d", level, mutationData.MaxLevel)
    levelLabel.TextColor3 = THEME.TEXT_GRAY
    levelLabel.TextSize = 12
    levelLabel.Font = Enum.Font.Gotham
    levelLabel.TextXAlignment = Enum.TextXAlignment.Left
    levelLabel.Parent = card

    -- Level badge (right side)
    local levelBadge = Instance.new("TextLabel")
    levelBadge.Name = "LevelBadge"
    levelBadge.Size = UDim2.new(0, 35, 0, 35)
    levelBadge.Position = UDim2.new(1, -45, 0.5, 0)
    levelBadge.AnchorPoint = Vector2.new(0, 0.5)
    levelBadge.BackgroundColor3 = MutationConfig.RarityColors[mutationData.Rarity] or Color3.new(1, 1, 1)
    levelBadge.Text = tostring(level)
    levelBadge.TextColor3 = Color3.fromRGB(20, 20, 20)
    levelBadge.TextSize = 18
    levelBadge.Font = Enum.Font.GothamBlack
    levelBadge.Parent = card

    local badgeCorner = Instance.new("UICorner")
    badgeCorner.CornerRadius = UDim.new(1, 0) -- Circle
    badgeCorner.Parent = levelBadge

    return card
end

-- Update the mutation display
local function updateMutationDisplay(metaData)
    if not metaData or not metaData.Upgrades then return end

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

    print("MutationHUDController started")
end

return MutationHUDController
