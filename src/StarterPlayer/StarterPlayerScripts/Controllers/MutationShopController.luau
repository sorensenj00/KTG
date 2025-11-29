local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
-- local ContextActionService = game:GetService("ContextActionService") -- Unused
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local MutationShopController = {}

-- Constants
-- Constants
-- local REMOTE_DRAFT = "RequestDraft" -- Unused
-- local REMOTE_SELECT = "SelectMutation" -- Unused

-- References
local player = Players.LocalPlayer
local gui = nil
local mainFrame = nil
local cardsContainer = nil

local mutationConfig = require(ReplicatedStorage.GameLoop.MutationConfig)

local closeCallback = nil

function MutationShopController.SetCloseCallback(callback)
    closeCallback = callback
end

-- Logic

local function createCard(name, data, index)
    local card = Instance.new("ImageButton")
    card.Name = "Card" .. index
    card.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    card.BorderSizePixel = 0
    card.Size = UDim2.new(0, 220, 0, 320)
    card.AutoButtonColor = false

    local cardCorner = Instance.new("UICorner")
    cardCorner.CornerRadius = UDim.new(0, 10)
    cardCorner.Parent = card

    local cardStroke = Instance.new("UIStroke")
    cardStroke.Color = mutationConfig.RarityColors[data.Rarity] or Color3.new(1,1,1)
    cardStroke.Thickness = 2
    cardStroke.Parent = card

    local cardGradient = Instance.new("UIGradient")
    cardGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.8, 0.8, 0.8))
    }
    cardGradient.Rotation = 45
    cardGradient.Parent = card

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Text = name
    title.Size = UDim2.new(1, -20, 0, 40)
    title.Position = UDim2.new(0, 10, 0, 10)
    title.BackgroundTransparency = 1
    title.TextColor3 = mutationConfig.RarityColors[data.Rarity] or Color3.new(1,1,1)
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 24 -- Increased from 20
    title.TextWrapped = true
    title.Parent = card

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0, 100, 0, 100)
    icon.Position = UDim2.new(0.5, 0, 0.3, 0)
    icon.AnchorPoint = Vector2.new(0.5, 0)
    icon.Image = data.ImageId
    icon.BackgroundTransparency = 1
    icon.Parent = card

    local desc = Instance.new("TextLabel")
    desc.Name = "Desc"
    desc.Text = data.Description
    desc.Size = UDim2.new(1, -20, 0.3, 0)
    desc.Position = UDim2.new(0, 10, 0.55, 0)
    desc.BackgroundTransparency = 1
    desc.TextColor3 = Color3.new(0.9, 0.9, 0.9)
    desc.TextWrapped = true
    desc.Font = Enum.Font.GothamMedium
    desc.BackgroundTransparency = 1
    desc.TextColor3 = Color3.new(0.9, 0.9, 0.9)
    desc.TextWrapped = true
    desc.Font = Enum.Font.GothamMedium
    desc.TextSize = 16 -- Increased from 14
    desc.TextYAlignment = Enum.TextYAlignment.Top
    desc.Parent = card
    
    -- Cost Label
    local costLabel = Instance.new("TextLabel")
    costLabel.Name = "CostLabel"
    costLabel.Text = "COST: 100 DNA" -- Placeholder or fetch from config
    costLabel.Size = UDim2.new(1, 0, 0, 25)
    costLabel.Position = UDim2.new(0, 0, 0.82, 0)
    costLabel.BackgroundTransparency = 1
    costLabel.TextColor3 = Color3.fromRGB(255, 215, 0) -- Gold
    costLabel.Font = Enum.Font.GothamBold
    costLabel.TextSize = 20 -- Increased from 16
    costLabel.Parent = card
    
    -- Timer/Rarity Label
    local rarityLabel = Instance.new("TextLabel")
    rarityLabel.Name = "RarityLabel"
    rarityLabel.Text = string.upper(data.Rarity)
    rarityLabel.Size = UDim2.new(1, 0, 0, 30)
    rarityLabel.Position = UDim2.new(0, 0, 0.15, 0) -- Moved up
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.TextColor3 = mutationConfig.RarityColors[data.Rarity] or Color3.new(1,1,1)
    rarityLabel.Font = Enum.Font.GothamBlack
    rarityLabel.TextSize = 24 -- Big and Bold
    rarityLabel.TextTransparency = 0.2
    rarityLabel.Parent = card

    -- Hover Animation
    card.MouseEnter:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.2), {Size = UDim2.new(0, 230, 0, 330)}):Play()
        TweenService:Create(cardStroke, TweenInfo.new(0.2), {Thickness = 4}):Play()
    end)

    card.MouseLeave:Connect(function()
        TweenService:Create(card, TweenInfo.new(0.2), {Size = UDim2.new(0, 220, 0, 320)}):Play()
        TweenService:Create(cardStroke, TweenInfo.new(0.2), {Thickness = 2}):Play()
    end)

    -- Selection Logic
    card.MouseButton1Click:Connect(function()
        local func = ReplicatedStorage:WaitForChild("SelectMutation")
        local success = func:InvokeServer(index)

        if success then
            gui.Enabled = false
            pcall(function() RunService:UnbindFromRenderStep("UnlockMouseForMutationShop") end)
            UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        end
    end)

    return card
end

function MutationShopController.Open()
    if gui.Enabled then return end

    -- Request Draft
    local func = ReplicatedStorage:WaitForChild("RequestDraft")
    local draft = func:InvokeServer()

    if not draft then
        -- Notify "Not enough DNA" or error
        return
    end

    -- Build UI
    for _, child in ipairs(cardsContainer:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end

    for i, name in ipairs(draft) do
        local data = mutationConfig.Mutations[name]
        if data then
            local card = createCard(name, data, i)
            card.Parent = cardsContainer
        end
    end

    gui.Enabled = true
    UserInputService.MouseBehavior = Enum.MouseBehavior.Default
    
    -- Enforce mouse unlock
    RunService:BindToRenderStep("UnlockMouseForMutationShop", Enum.RenderPriority.Last.Value, function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end)
end

function MutationShopController.Start()
    -- Create GUI
    gui = Instance.new("ScreenGui")
    gui.Name = "MutationShopGui"
    gui.ResetOnSpawn = false
    gui.Enabled = false
    gui.Parent = player:WaitForChild("PlayerGui")

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0.7, 0, 0.7, 0)
    mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = gui

    local mainCorner = Instance.new("UICorner")
    mainCorner.CornerRadius = UDim.new(0, 15)
    mainCorner.Parent = mainFrame

    local mainStroke = Instance.new("UIStroke")
    mainStroke.Color = Color3.fromRGB(50, 50, 60)
    mainStroke.Thickness = 2
    mainStroke.Parent = mainFrame

    local mainGradient = Instance.new("UIGradient")
    mainGradient.Rotation = 45
    mainGradient.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
        ColorSequenceKeypoint.new(1, Color3.new(0.9, 0.9, 0.95))
    }
    mainGradient.Parent = mainFrame

    local title = Instance.new("TextLabel")
    title.Text = "MUTATION LAB"
    title.Size = UDim2.new(1, 0, 0.1, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(0, 255, 255)
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 32
    title.Parent = mainFrame
    
    -- Timer Label
    local timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerLabel"
    timerLabel.Text = "New mutations in: 05:00"
    timerLabel.Size = UDim2.new(1, 0, 0, 20)
    timerLabel.Position = UDim2.new(0, 0, 0.1, 0)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.TextSize = 14
    timerLabel.Parent = mainFrame
    
    -- Timer Logic
    task.spawn(function()
        while gui.Parent do
            local now = os.time()
            local cycle = 300 -- 5 minutes
            local remaining = cycle - (now % cycle)
            local m = math.floor(remaining / 60)
            local s = remaining % 60
            timerLabel.Text = string.format("New mutations in: %02d:%02d", m, s)
            
            if remaining == cycle - 1 and gui.Enabled then
                 -- Auto-refresh if open when timer hits 0 (actually starts new cycle)
                 -- Ideally we'd trigger a refresh here, but let's just let the user re-roll or close/open
            end
            task.wait(1)
        end
    end)
    
    -- Close/Back Button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Text = "BACK"
    closeButton.Size = UDim2.new(0, 80, 0, 30)
    closeButton.Position = UDim2.new(1, -10, 0, 10)
    closeButton.AnchorPoint = Vector2.new(1, 0)
    closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
    closeButton.TextColor3 = Color3.new(1, 1, 1)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 14
    closeButton.Parent = mainFrame
    
    local closeCorner = Instance.new("UICorner")
    closeCorner.CornerRadius = UDim.new(0, 6)
    closeCorner.Parent = closeButton
    
    closeButton.MouseButton1Click:Connect(function()
        gui.Enabled = false
        pcall(function() RunService:UnbindFromRenderStep("UnlockMouseForMutationShop") end)
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default -- Keep unlocked for main shop
        if closeCallback then
            closeCallback()
        end
    end)

    cardsContainer = Instance.new("Frame")
    cardsContainer.Size = UDim2.new(1, 0, 0.9, 0)
    cardsContainer.Position = UDim2.new(0, 0, 0.1, 0)
    cardsContainer.BackgroundTransparency = 1
    cardsContainer.Parent = mainFrame

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 20)
    layout.Parent = cardsContainer

    -- Bind Key (e.g., M for Mutation or Shop button)
    -- ContextActionService:BindAction("OpenMutationShop", function(_, state)
    --     if state == Enum.UserInputState.Begin then
    --         openShop()
    --     end
    -- end, false, Enum.KeyCode.M)
end

return MutationShopController
