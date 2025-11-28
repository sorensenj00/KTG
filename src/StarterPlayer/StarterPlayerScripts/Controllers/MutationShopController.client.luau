local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")

local MutationShopController = {}

-- Constants
local REMOTE_DRAFT = "RequestDraft"
local REMOTE_SELECT = "SelectMutation"

-- References
local player = Players.LocalPlayer
local gui = nil
local mainFrame = nil
local cardsContainer = nil

local mutationConfig = require(ReplicatedStorage.GameLoop.MutationConfig)

-- Logic

local function createCard(name, data, index)
    local card = Instance.new("ImageButton")
    card.Name = "Card" .. index
    card.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    card.BorderSizePixel = 2
    card.BorderColor3 = mutationConfig.RarityColors[data.Rarity] or Color3.new(1,1,1)
    card.Size = UDim2.new(0, 200, 0, 300)

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Text = name
    title.Size = UDim2.new(1, 0, 0.15, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.new(1,1,1)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.Parent = card

    local icon = Instance.new("ImageLabel")
    icon.Name = "Icon"
    icon.Size = UDim2.new(0.6, 0, 0.4, 0)
    icon.Position = UDim2.new(0.2, 0, 0.2, 0)
    icon.Image = data.ImageId
    icon.BackgroundTransparency = 1
    icon.Parent = card

    local desc = Instance.new("TextLabel")
    desc.Name = "Desc"
    desc.Text = data.Description
    desc.Size = UDim2.new(0.9, 0, 0.3, 0)
    desc.Position = UDim2.new(0.05, 0, 0.65, 0)
    desc.BackgroundTransparency = 1
    desc.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    desc.TextWrapped = true
    desc.Font = Enum.Font.Gotham
    desc.TextSize = 14
    desc.Parent = card

    -- Selection Logic
    card.MouseButton1Click:Connect(function()
        local func = ReplicatedStorage:WaitForChild("SelectMutation")
        local success = func:InvokeServer(index)

        if success then
            gui.Enabled = false
        end
    end)

    return card
end

local function openShop()
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
end

function MutationShopController.Start()
    -- Create GUI
    gui = Instance.new("ScreenGui")
    gui.Name = "MutationShopGui"
    gui.ResetOnSpawn = false
    gui.Enabled = false
    gui.Parent = player:WaitForChild("PlayerGui")

    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0.6, 0, 0.6, 0)
    mainFrame.Position = UDim2.new(0.2, 0, 0.2, 0)
    mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = gui

    local title = Instance.new("TextLabel")
    title.Text = "MUTATION LAB"
    title.Size = UDim2.new(1, 0, 0.1, 0)
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.fromRGB(0, 255, 255)
    title.Font = Enum.Font.GothamBlack
    title.TextSize = 32
    title.Parent = mainFrame

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
    ContextActionService:BindAction("OpenMutationShop", function(_, state)
        if state == Enum.UserInputState.Begin then
            openShop()
        end
    end, false, Enum.KeyCode.M)
end

return MutationShopController
