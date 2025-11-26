--[[
    Controller: LeaderboardController
    Description: Manages the custom avatar leaderboard at the top of the screen.
    Shows the top 5 players sorted by Level.
    
    Dependencies:
    - Players
    - StarterGui (to disable default list)
    
    Author: System
    Last Updated: 2025-11-26
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Constants
local MAX_ENTRIES = 5
local UPDATE_RATE = 1 -- Update every 1 second to avoid spam

-- Colors
local COLORS = {
	RANK_1 = Color3.fromRGB(255, 215, 0), -- Gold
	RANK_2 = Color3.fromRGB(192, 192, 192), -- Silver
	RANK_3 = Color3.fromRGB(205, 127, 50), -- Bronze
	RANK_OTHER = Color3.fromRGB(40, 40, 40), -- Dark Grey
	TEXT_WHITE = Color3.fromRGB(255, 255, 255),
}

-- State
local _leaderboardGui = nil
local container = nil
local _entries = {} -- { [userId] = frame }
local lastUpdate = 0

-- --- UI Creation --- --

local function createLeaderboardUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CustomLeaderboard"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.DisplayOrder = 10
	screenGui.Enabled = true
	screenGui.Parent = playerGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "Container"
	mainFrame.Size = UDim2.new(0, 600, 0, 100)
	mainFrame.Position = UDim2.new(0.5, 0, 0, 10) -- Top Center
	mainFrame.AnchorPoint = Vector2.new(0.5, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = screenGui

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = mainFrame

	return screenGui, mainFrame
end

local function createEntry(rank, playerObj, level)
	local entryFrame = Instance.new("Frame")
	entryFrame.Name = "Entry"
	entryFrame.Size = UDim2.fromOffset(80, 100)
	entryFrame.BackgroundTransparency = 1
	entryFrame.LayoutOrder = rank

	-- Avatar Circle Background
	local avatarBg = Instance.new("Frame")
	avatarBg.Name = "AvatarBg"
	avatarBg.Size = UDim2.fromOffset(60, 60)
	avatarBg.Position = UDim2.fromScale(0.5, 0)
	avatarBg.AnchorPoint = Vector2.new(0.5, 0)
	avatarBg.BackgroundColor3 = if rank == 1 then COLORS.RANK_1 elseif rank == 2 then COLORS.RANK_2 elseif rank == 3 then COLORS.RANK_3 else COLORS.RANK_OTHER
	avatarBg.BorderSizePixel = 0
	avatarBg.Parent = entryFrame

	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(1, 0) -- Circle
	avatarCorner.Parent = avatarBg
	
	local avatarStroke = Instance.new("UIStroke")
	avatarStroke.Color = Color3.new(0,0,0)
	avatarStroke.Thickness = 2
	avatarStroke.Parent = avatarBg

	-- Avatar Image
	local avatarImage = Instance.new("ImageLabel")
	avatarImage.Name = "Avatar"
	avatarImage.Size = UDim2.fromScale(0.9, 0.9)
	avatarImage.Position = UDim2.fromScale(0.5, 0.5)
	avatarImage.AnchorPoint = Vector2.new(0.5, 0.5)
	avatarImage.BackgroundTransparency = 1
	avatarImage.Image = ""
	avatarImage.Parent = avatarBg
	
	local avatarImageCorner = Instance.new("UICorner")
	avatarImageCorner.CornerRadius = UDim.new(1, 0)
	avatarImageCorner.Parent = avatarImage

	-- Load Avatar
	task.spawn(function()
		local content, isReady = Players:GetUserThumbnailAsync(playerObj.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		if isReady then
			avatarImage.Image = content
		end
	end)

	-- Rank Label (Top Left of Avatar)
	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "Rank"
	rankLabel.Size = UDim2.fromOffset(20, 20)
	rankLabel.Position = UDim2.new(0, -5, 0, -5)
	rankLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	rankLabel.BackgroundTransparency = 0.5
	rankLabel.Text = "#" .. rank
	rankLabel.TextColor3 = COLORS.TEXT_WHITE
	rankLabel.TextSize = 12
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.Parent = avatarBg
	
	local rankCorner = Instance.new("UICorner")
	rankCorner.CornerRadius = UDim.new(0.5, 0)
	rankCorner.Parent = rankLabel

	-- Level Label (Below Avatar)
	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "Level"
	levelLabel.Size = UDim2.new(1, 0, 0, 30)
	levelLabel.Position = UDim2.new(0, 0, 1, 5)
	levelLabel.BackgroundTransparency = 1
	levelLabel.Text = tostring(level)
	levelLabel.TextColor3 = COLORS.RANK_1 -- Gold text for level
	levelLabel.TextSize = 24
	levelLabel.Font = Enum.Font.LuckiestGuy
	if not pcall(function() levelLabel.Font = Enum.Font.LuckiestGuy end) then
		levelLabel.Font = Enum.Font.GothamBlack
	end
	levelLabel.TextStrokeTransparency = 0
	levelLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	levelLabel.Parent = avatarBg

	return entryFrame
end

-- --- Logic --- --

local function updateLeaderboard()
	if not container then return end

	-- Gather all players and bots (if applicable, but focusing on players for now)
	local playerList = {}
	
	for _, p in ipairs(Players:GetPlayers()) do
		local level = p:GetAttribute("Level") or 1
		table.insert(playerList, {
			Player = p,
			Level = level,
			IsBot = false
		})
	end
	
	-- TODO: Add Bot support if they have accessible attributes or a central registry
	-- For now, just players as per standard leaderboard

	-- Sort by Level Descending
	table.sort(playerList, function(a, b)
		return a.Level > b.Level
	end)

	-- Clear existing
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Create Top Entries
	for i = 1, math.min(#playerList, MAX_ENTRIES) do
		local data = playerList[i]
		local entry = createEntry(i, data.Player, data.Level)
		entry.Parent = container
	end
end

local LeaderboardController = {}

function LeaderboardController.Start()
	print("🏆 LeaderboardController: Starting...")
	_leaderboardGui, container = createLeaderboardUI()
	
	-- Initial Update
	updateLeaderboard()

	-- Listen for updates
	-- We can use a loop or events. Events are better but AttributeChanged on all players can be messy to manage.
	-- A slow loop (1s) is often sufficient for leaderboards and less error prone with player joining/leaving.
	
	RunService.Heartbeat:Connect(function(dt)
		lastUpdate = lastUpdate + dt
		if lastUpdate >= UPDATE_RATE then
			lastUpdate = 0
			updateLeaderboard()
		end
	end)
	
	-- Input Listener
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Tab then
			_leaderboardGui.Enabled = not _leaderboardGui.Enabled
		end
	end)
	
	print("✅ LeaderboardController: Initialized")
end

return LeaderboardController
