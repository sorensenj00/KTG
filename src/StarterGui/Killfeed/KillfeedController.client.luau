local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Configuration
local MAX_ENTRIES = 4
local ENTRY_LIFETIME = 5 -- seconds before fade out
local FADE_IN_TIME = 0.25
local FADE_OUT_TIME = 0.3

-- Color definitions
local COLORS = {
	KillerPlayer = Color3.fromRGB(135, 206, 250), -- Light cyan
	KillerBot = Color3.fromRGB(255, 215, 0), -- Yellow/Gold
	VictimPlayer = Color3.fromRGB(255, 50, 50), -- Red
	VictimBot = Color3.fromRGB(255, 165, 0), -- Orange
	Level = Color3.fromRGB(180, 180, 180), -- Gray
	Separator = Color3.fromRGB(255, 255, 255), -- White
}

-- State
local killfeedGui = nil
local entriesContainer = nil
local entries = {} -- Table to track entries: {frame, timer, tween}

-- Create Killfeed UI
local function createKillfeedUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Killfeed"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10 -- Ensure it's visible
	screenGui.Enabled = true
	screenGui.Parent = playerGui

	-- Container Frame (top-right)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.new(0, 400, 0, 0) -- Width fixed, height auto
	container.Position = UDim2.new(0.98, 0, 0.02, 0) -- Top-right
	container.AnchorPoint = Vector2.new(1, 0) -- Anchor to top-right
	container.BackgroundTransparency = 1
	container.Visible = true
	container.Parent = screenGui

	-- Layout for entries (vertical, top to bottom)
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4) -- 4px spacing between entries
	listLayout.Parent = container

	return screenGui, container
end

-- Create a single killfeed entry
local function createEntry(killerName, killerLevel, killerIsBot, victimName, victimLevel, victimIsBot, actionText, actionColor)
	local entryFrame = Instance.new("Frame")
	entryFrame.Name = "KillfeedEntry"
	entryFrame.Size = UDim2.new(0, 0, 0, 35) -- Height fixed, width auto
	entryFrame.AutomaticSize = Enum.AutomaticSize.X
	entryFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	entryFrame.BackgroundTransparency = 1 -- Fully transparent initially
	entryFrame.BorderSizePixel = 0
	entryFrame.Parent = entriesContainer

	-- Corner radius for modern look
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = entryFrame

	-- Horizontal layout for entry content
	local horizontalLayout = Instance.new("UIListLayout")
	horizontalLayout.FillDirection = Enum.FillDirection.Horizontal
	horizontalLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	horizontalLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	horizontalLayout.SortOrder = Enum.SortOrder.LayoutOrder
	horizontalLayout.Padding = UDim.new(0, 8) -- Increased padding between elements
	horizontalLayout.Parent = entryFrame

	-- Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.Parent = entryFrame

	-- Killer Name
	local killerNameLabel = Instance.new("TextLabel")
	killerNameLabel.Name = "KillerName"
	killerNameLabel.Size = UDim2.new(0, 0, 1, 0) -- Auto width
	killerNameLabel.AutomaticSize = Enum.AutomaticSize.X
	killerNameLabel.BackgroundTransparency = 1
	killerNameLabel.Text = killerName
	killerNameLabel.TextColor3 = killerIsBot and COLORS.KillerBot or COLORS.KillerPlayer
	killerNameLabel.TextSize = 20
	killerNameLabel.Font = Enum.Font.LuckiestGuy
	if not pcall(function() killerNameLabel.Font = Enum.Font.LuckiestGuy end) then
		killerNameLabel.Font = Enum.Font.GothamBlack
	end
	killerNameLabel.TextStrokeTransparency = 0
	killerNameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	killerNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	killerNameLabel.Parent = entryFrame

	-- Killer Level
	local killerLevelLabel = Instance.new("TextLabel")
	killerLevelLabel.Name = "KillerLevel"
	killerLevelLabel.Size = UDim2.new(0, 0, 1, 0) -- Auto width
	killerLevelLabel.AutomaticSize = Enum.AutomaticSize.X
	killerLevelLabel.BackgroundTransparency = 1
	killerLevelLabel.Text = "Lv" .. tostring(killerLevel)
	killerLevelLabel.TextColor3 = COLORS.Level
	killerLevelLabel.TextSize = 14
	killerLevelLabel.Font = Enum.Font.Gotham
	killerLevelLabel.TextStrokeTransparency = 0
	killerLevelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	killerLevelLabel.TextXAlignment = Enum.TextXAlignment.Left
	killerLevelLabel.Parent = entryFrame

	-- Separator
	local separatorLabel = Instance.new("TextLabel")
	separatorLabel.Name = "Separator"
	separatorLabel.Size = UDim2.new(0, 0, 1, 0) -- Auto width
	separatorLabel.AutomaticSize = Enum.AutomaticSize.X
	separatorLabel.BackgroundTransparency = 1
	separatorLabel.Text = actionText or "oofed"
	separatorLabel.TextColor3 = actionColor or COLORS.Separator
	separatorLabel.TextSize = 20
	separatorLabel.Font = Enum.Font.LuckiestGuy
	if not pcall(function() separatorLabel.Font = Enum.Font.LuckiestGuy end) then
		separatorLabel.Font = Enum.Font.GothamBlack
	end
	separatorLabel.TextStrokeTransparency = 0
	separatorLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	separatorLabel.Parent = entryFrame

	-- Victim Name
	local victimNameLabel = Instance.new("TextLabel")
	victimNameLabel.Name = "VictimName"
	victimNameLabel.Size = UDim2.new(0, 0, 1, 0) -- Auto width
	victimNameLabel.AutomaticSize = Enum.AutomaticSize.X
	victimNameLabel.BackgroundTransparency = 1
	victimNameLabel.Text = victimName
	victimNameLabel.TextColor3 = victimIsBot and COLORS.VictimBot or COLORS.VictimPlayer
	victimNameLabel.TextSize = 20
	victimNameLabel.Font = Enum.Font.LuckiestGuy
	if not pcall(function() victimNameLabel.Font = Enum.Font.LuckiestGuy end) then
		victimNameLabel.Font = Enum.Font.GothamBlack
	end
	victimNameLabel.TextStrokeTransparency = 0
	victimNameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	victimNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	victimNameLabel.Parent = entryFrame

	-- Victim Level
	local victimLevelLabel = Instance.new("TextLabel")
	victimLevelLabel.Name = "VictimLevel"
	victimLevelLabel.Size = UDim2.new(0, 0, 1, 0) -- Auto width
	victimLevelLabel.AutomaticSize = Enum.AutomaticSize.X
	victimLevelLabel.BackgroundTransparency = 1
	victimLevelLabel.Text = "Lv" .. tostring(victimLevel)
	victimLevelLabel.TextColor3 = COLORS.Level
	victimLevelLabel.TextSize = 14
	victimLevelLabel.Font = Enum.Font.Gotham
	victimLevelLabel.TextStrokeTransparency = 0
	victimLevelLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	victimLevelLabel.TextXAlignment = Enum.TextXAlignment.Left
	victimLevelLabel.Parent = entryFrame

	return entryFrame
end

-- Remove entry with animation
local function removeEntry(entryData, index)
	if not entryData or not entryData.frame or not entryData.frame.Parent then
		return
	end

	local frame = entryData.frame

	-- Cancel existing timer if any (safely)
	if entryData.timer then
		local success, _err = pcall(function()
			task.cancel(entryData.timer)
		end)
		if not success then
			-- Timer already completed or invalid, ignore error
		end
		entryData.timer = nil
	end

	-- Cancel existing tween if any
	if entryData.tween then
		entryData.tween:Cancel()
		entryData.tween = nil
	end

	-- Fade out animation
	local fadeOutTween = TweenService:Create(
		frame,
		TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1, BorderSizePixel = 0 }
	)

	-- Fade out all text labels
	for _, child in ipairs(frame:GetDescendants()) do
		if child:IsA("TextLabel") then
			local textFade = TweenService:Create(
				child,
				TweenInfo.new(FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1, TextStrokeTransparency = 1 }
			)
			textFade:Play()
		end
	end

	fadeOutTween:Play()
	fadeOutTween.Completed:Connect(function()
		frame:Destroy()
		table.remove(entries, index)
	end)
end

-- Add new killfeed entry
local function addKillEntry(killerName, killerLevel, killerIsBot, victimName, victimLevel, victimIsBot)
	-- Determine Action Text and Color
	local actionText = "oofed"
	local actionColor = COLORS.Separator
	
	-- Titan (Level 30+) vs Mouse (Level <= 5)
	if killerLevel >= 30 and victimLevel <= 5 then
		actionText = "STOMPED"
		actionColor = Color3.fromRGB(255, 0, 0) -- Red
	end

	-- Create entry
	local entryFrame = createEntry(killerName, killerLevel, killerIsBot, victimName, victimLevel, victimIsBot, actionText, actionColor)

	-- Set initial transparency for fade-in
	entryFrame.BackgroundTransparency = 1
	entryFrame.BorderSizePixel = 0
	for _, child in ipairs(entryFrame:GetDescendants()) do
		if child:IsA("TextLabel") then
			child.TextTransparency = 1
			child.TextStrokeTransparency = 1
		end
	end

	-- Insert at top (newest first)
	entryFrame.Parent = entriesContainer
	entryFrame.LayoutOrder = 0

	-- Update layout orders (push existing entries down)
	for i, entryData in ipairs(entries) do
		if entryData.frame and entryData.frame.Parent then
			entryData.frame.LayoutOrder = i
		end
	end

	-- Fade in animation
	-- Fade in animation (Text only, background stays transparent)
	local fadeInTween = TweenService:Create(
		entryFrame,
		TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1, BorderSizePixel = 0 } -- Keep transparent
	)

	-- Fade in all text labels
	for _, child in ipairs(entryFrame:GetDescendants()) do
		if child:IsA("TextLabel") then
			local textFade = TweenService:Create(
				child,
				TweenInfo.new(FADE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ TextTransparency = 0, TextStrokeTransparency = 0 }
			)
			textFade:Play()
		end
	end

	fadeInTween:Play()

	-- Create entry data
	local entryData = {
		frame = entryFrame,
		timer = nil,
		tween = nil,
	}

	-- Auto-remove after lifetime
	entryData.timer = task.delay(ENTRY_LIFETIME, function()
		-- Check if entry still exists and hasn't been removed
		if not entryData.frame or not entryData.frame.Parent then
			return
		end
		-- Find and remove this entry
		for i, e in ipairs(entries) do
			if e == entryData then
				-- Mark timer as completed before removing
				entryData.timer = nil
				removeEntry(entryData, i)
				break
			end
		end
	end)

	-- Add to entries table at the beginning
	table.insert(entries, 1, entryData)

	-- Remove oldest entry if max exceeded
	if #entries > MAX_ENTRIES then
		local oldestEntry = entries[#entries]
		removeEntry(oldestEntry, #entries)
	end
end

-- Initialize
print("🔵 KillfeedController: Starting initialization...")
killfeedGui, entriesContainer = createKillfeedUI()
print("🔵 KillfeedController: UI created, ScreenGui:", killfeedGui, "Container:", entriesContainer)

-- Listen for kill events
local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
print("🔵 KillfeedController: Remotes folder found")
local killfeedRemote = remotes:WaitForChild("Killfeed")
print("🔵 KillfeedController: Killfeed RemoteEvent found:", killfeedRemote)

killfeedRemote.OnClientEvent:Connect(function(
	killerName,
	killerLevel,
	killerIsBot,
	victimName,
	victimLevel,
	victimIsBot
)
	print("🔵 KillfeedController: Received kill event -", killerName, "→", victimName)
	addKillEntry(killerName, killerLevel, killerIsBot, victimName, victimLevel, victimIsBot)
end)

print("✅ KillfeedController: Initialized and listening for events")

