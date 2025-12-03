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
local timerLabel = nil

local mutationConfig = require(ReplicatedStorage.GameLoop.MutationConfig)

local closeCallback = nil
local nextRotationTime = 0
local currentRerolls = 0
local MAX_REROLLS = 3

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

    -- Level Bar Container
    local barContainer = Instance.new("Frame")
    barContainer.Name = "LevelBar"
    barContainer.Size = UDim2.new(0.8, 0, 0, 6)
    barContainer.Position = UDim2.new(0.1, 0, 0.48, 0) -- Between Icon and Desc
    barContainer.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    barContainer.BorderSizePixel = 0
    barContainer.Parent = card

    local barCorner = Instance.new("UICorner")
    barCorner.CornerRadius = UDim.new(1, 0)
    barCorner.Parent = barContainer

    local barLayout = Instance.new("UIListLayout")
    barLayout.Name = "BarLayout"
    barLayout.FillDirection = Enum.FillDirection.Horizontal
    barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    barLayout.Padding = UDim.new(0, 2) -- Will be adjusted based on segment count
    barLayout.Parent = barContainer

    
    -- Cost Label
    local costLabel = Instance.new("TextLabel")
    costLabel.Name = "CostLabel"
    -- Calculate Cost
    -- Ideally we pass current level in 'data' or fetch it.
    -- For now, let's assume data has it or we default to 0 (Cost for Lvl 1)
    -- The server passes 'draft' which is just names.
    -- We need the player's current level of this mutation to calculate cost.
    -- Let's fetch it from client state if possible, or just show "???"
    -- Actually, we can get it from the HUDController's cached data if we had access, 
    -- but better to just ask server or pass it in draft.
    -- For now, let's just show "COST: [Dynamic]" placeholder or fetch it.
    -- Let's use a helper to get cost.
    costLabel.Text = "COST: ???" 
    
    -- Async fetch cost? Or just calculate if we know our level.
    -- Let's assume we can get our level.
    task.spawn(function()
        local blaster = ReplicatedStorage:WaitForChild("Blaster")
        local remotes = blaster:WaitForChild("Remotes")
        local reqFunc = remotes:WaitForChild("RequestMetaData")
        
        local dna, upgrades = reqFunc:InvokeServer()
        local lvl = upgrades[name] or 0
        local cost = mutationConfig.GetUpgradeCost(data.Rarity, lvl)
        costLabel.Text = "COST: " .. cost .. " DNA"

        -- Update Level Bar
        local maxLevel = data.MaxLevel or 5
        -- Clear existing segments (if any)
        for _, child in ipairs(barContainer:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
        
        -- Adjust padding based on segment count (smaller padding for more segments)
        local layout = barContainer:FindFirstChild("BarLayout")
        local padding = maxLevel > 10 and 1 or 2
        if layout then
            layout.Padding = UDim.new(0, padding)
        end
        
        -- Calculate segment size properly
        -- Total padding = (maxLevel - 1) * padding pixels
        -- We use scale for the main width and subtract padding share from each segment
        local totalPaddingRatio = (maxLevel - 1) * padding / 176 -- Approximate container width
        local segmentScale = (1 - totalPaddingRatio) / maxLevel
        
        for i = 1, maxLevel do
            local segment = Instance.new("Frame")
            segment.Name = "Segment" .. i
            segment.BackgroundColor3 = (i <= lvl) and (mutationConfig.RarityColors[data.Rarity] or Color3.new(1,1,1)) or Color3.fromRGB(60, 60, 70)
            segment.Size = UDim2.new(segmentScale, 0, 1, 0)
            segment.BorderSizePixel = 0
            segment.Parent = barContainer
            
            -- Only add corner radius if segments are big enough
            if maxLevel <= 10 then
                local segCorner = Instance.new("UICorner")
                segCorner.CornerRadius = UDim.new(0, 2)
                segCorner.Parent = segment
            end
        end

        
        -- Check affordability
        if dna < cost then
            costLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
        else
            costLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
        end
    end)
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
    -- Selection Logic
    local isPurchased = false
    card.MouseButton1Click:Connect(function()
        if isPurchased then return end

        local func = ReplicatedStorage:WaitForChild("SelectMutation")
        local success, msg = func:InvokeServer(index)

        if success then
            -- Mark as Purchased
            isPurchased = true
            
            -- Visual Update
            card.AutoButtonColor = false
            card.ImageColor3 = Color3.fromRGB(100, 100, 100) -- Darken
            cardStroke.Color = Color3.fromRGB(100, 100, 100)
            
            -- Update Text
            local costLabel = card:FindFirstChild("CostLabel")
            if costLabel then
                costLabel.Text = "PURCHASED"
                costLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
            end
            
            local title = card:FindFirstChild("Title")
            if title then
                title.TextColor3 = Color3.fromRGB(150, 150, 150)
            end

            -- Update Level Bar (Immediate Feedback)
            local barContainer = card:FindFirstChild("LevelBar")
            if barContainer then
                -- Find segments by name order and light up the next unlit one
                local segments = {}
                for _, child in ipairs(barContainer:GetChildren()) do
                    if child:IsA("Frame") and child.Name:match("^Segment%d+$") then
                        local segNum = tonumber(child.Name:match("%d+"))
                        if segNum then
                            segments[segNum] = child
                        end
                    end
                end
                
                -- Find first unlit segment (gray) using approximate color match
                local grayColor = Color3.fromRGB(60, 60, 70)
                local rarityColor = mutationConfig.RarityColors[data.Rarity] or Color3.new(1,1,1)
                for i = 1, #segments do
                    local seg = segments[i]
                    if seg then
                        -- Use approximate comparison (tolerance of 0.01)
                        local c = seg.BackgroundColor3
                        local isGray = math.abs(c.R - grayColor.R) < 0.05 
                            and math.abs(c.G - grayColor.G) < 0.05 
                            and math.abs(c.B - grayColor.B) < 0.05
                        if isGray then
                            seg.BackgroundColor3 = rarityColor
                            break
                        end
                    end
                end
            end
            
            -- Disable Hover
            card.Active = false
            
            -- Play Sound? (Optional)
        else
            -- Failed (e.g. Not enough DNA)
            warn("Purchase failed:", msg)
        end
    end)

    return card
end

function MutationShopController.Open()
    if gui.Enabled then return true end

    -- Request Draft
    -- Request Draft
    local func = ReplicatedStorage:WaitForChild("RequestDraft")
    local draft, rotationTime, rerolls = func:InvokeServer()

    if rotationTime then
        nextRotationTime = tonumber(rotationTime) or 0
    end
    
    if rerolls then
        currentRerolls = rerolls
    end

    if not draft then
        -- Notify "Not enough DNA" or error
        return false
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
    UserInputService.MouseIconEnabled = true -- Ensure cursor is visible
    
    -- Enforce mouse unlock and cursor visibility
    RunService:BindToRenderStep("UnlockMouseForMutationShop", Enum.RenderPriority.Last.Value, function()
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    end)
    
    -- Hide Reticle (Crosshair)
    local reticle = player:WaitForChild("PlayerGui"):FindFirstChild("ReticleGui")
    if reticle then
        reticle.Enabled = false
    end

    return true
end

function MutationShopController.Close(skipCallback)
    if not gui or not gui.Enabled then return end
    
    gui.Enabled = false
    pcall(function() RunService:UnbindFromRenderStep("UnlockMouseForMutationShop") end)
    
    -- Restore Reticle (Crosshair) if tool is equipped
    local reticle = player:WaitForChild("PlayerGui"):FindFirstChild("ReticleGui")
    if reticle then
        local character = player.Character
        if character and character:FindFirstChildOfClass("Tool") then
            reticle.Enabled = true
        end
    end
    
    -- If we have a parent menu callback, use it to return smoothly (unless skipped)
    if closeCallback and not skipCallback then
        closeCallback()
    else
        -- Fallback: Just lock mouse and resume game
        UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
        UserInputService.MouseIconEnabled = false
    end
end

function MutationShopController.IsOpen()
    return gui and gui.Enabled
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
    
    local desc = Instance.new("TextLabel")
    desc.Name = "Description"
    desc.Text = "Roll for powerful, unique traits."
    desc.Size = UDim2.new(1, 0, 0, 20)
    desc.Position = UDim2.new(0, 0, 0.08, 0)
    desc.BackgroundTransparency = 1
    desc.TextColor3 = Color3.fromRGB(180, 180, 180)
    desc.Font = Enum.Font.Gotham
    desc.TextSize = 14
    desc.Parent = mainFrame
    
    -- Timer Label
    timerLabel = Instance.new("TextLabel")
    timerLabel.Name = "TimerLabel"
    timerLabel.Text = "New mutations in: --:--"
    timerLabel.Size = UDim2.new(1, 0, 0, 20)
    timerLabel.Position = UDim2.new(0, 0, 0.1, 0)
    timerLabel.BackgroundTransparency = 1
    timerLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
    timerLabel.Font = Enum.Font.GothamBold
    timerLabel.TextSize = 14
    timerLabel.Parent = mainFrame
    
    -- Reroll Button
    local rerollButton = Instance.new("TextButton")
    rerollButton.Name = "RerollButton"
    rerollButton.Text = "REROLL (250 DNA)"
    rerollButton.Size = UDim2.new(0, 150, 0, 30)
    rerollButton.Position = UDim2.new(0.5, 0, 0.92, 0) -- Bottom Center
    rerollButton.AnchorPoint = Vector2.new(0.5, 0)
    rerollButton.BackgroundColor3 = Color3.fromRGB(255, 100, 50)
    rerollButton.TextColor3 = Color3.new(1, 1, 1)
    rerollButton.Font = Enum.Font.GothamBold
    rerollButton.TextSize = 14
    rerollButton.Parent = mainFrame
    
    local rerollCorner = Instance.new("UICorner")
    rerollCorner.CornerRadius = UDim.new(0, 6)
    rerollCorner.Parent = rerollButton
    
    -- Reroll Logic
    rerollButton.MouseButton1Click:Connect(function()
        if currentRerolls >= MAX_REROLLS then return end
        
        local func = ReplicatedStorage:WaitForChild("RequestReroll")
        local draft, _, rerolls = func:InvokeServer()
        
        if draft then
            -- Refresh UI
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
            
            if rerolls then currentRerolls = rerolls end
            rerollButton.Text = "REROLL (250 DNA) [" .. currentRerolls .. "/3]"
            
            if currentRerolls >= MAX_REROLLS then
                rerollButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
                rerollButton.Text = "NO REROLLS LEFT"
            end
        else
            -- Failed (No DNA?)
            rerollButton.Text = "NOT ENOUGH DNA"
            task.wait(1)
            rerollButton.Text = "REROLL (250 DNA) [" .. currentRerolls .. "/3]"
        end
    end)

    -- Timer Logic (Server Synced)
    task.spawn(function()
        while gui.Parent do
            if nextRotationTime > 0 then
                local now = os.time()
                local remaining = math.max(0, nextRotationTime - now)
                local m = math.floor(remaining / 60)
                local s = remaining % 60
                timerLabel.Text = string.format("New mutations in: %02d:%02d", m, s)
            else
                timerLabel.Text = "Synchronizing..."
            end
            
            -- Update Reroll Text
            if currentRerolls < MAX_REROLLS then
                 rerollButton.Text = "REROLL (250 DNA) [" .. currentRerolls .. "/3]"
                 rerollButton.BackgroundColor3 = Color3.fromRGB(255, 100, 50)
            else
                 rerollButton.Text = "NO REROLLS LEFT"
                 rerollButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100)
            end
            
            task.wait(1)
        end
    end)
    
    -- Close/Back Button
    local closeButton = Instance.new("TextButton")
    closeButton.Name = "CloseButton"
    closeButton.Text = "SHOP"
    closeButton.Size = UDim2.new(0, 80, 0, 30)
    closeButton.Position = UDim2.new(0, 10, 0, 10) -- Moved to left
    closeButton.AnchorPoint = Vector2.new(0, 0)
    closeButton.BackgroundColor3 = Color3.fromRGB(0, 255, 150) -- Green like shop
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
