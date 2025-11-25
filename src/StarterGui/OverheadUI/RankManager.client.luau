local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScalingConfig = require(ReplicatedStorage.GameLoop.ScalingConfig)

-- UI Configuration
local TEXT_SIZE = 14
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local STROKE_TRANSPARENCY = 0
local OFFSET = Vector3.new(0, 3, 0) -- Above head

local function createOverheadUI()
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RankOverhead"
	billboard.Size = UDim2.fromScale(4, 1)
	billboard.StudsOffset = OFFSET
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100

	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "InfoLabel"
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = TEXT_COLOR
	textLabel.TextStrokeTransparency = STROKE_TRANSPARENCY
	textLabel.TextSize = TEXT_SIZE
	textLabel.Font = Enum.Font.GothamBold
	textLabel.Parent = billboard
	
	return billboard
end

local function updateLabel(player: Player, label: TextLabel)
	local level = player:GetAttribute("Level") or 1
	local xp = player:GetAttribute("XP") or 0
	local requiredXP = ScalingConfig.GetXPRequired(level)
	
	if level >= ScalingConfig.MAX_LEVEL then
		label.Text = "MAX LEVEL (20)"
		label.TextColor3 = ScalingConfig.STAR_MODE_COLOR
	else
		label.Text = string.format("Level %d | XP: %d/%d", level, xp, requiredXP)
		label.TextColor3 = TEXT_COLOR
	end
end

local function setupCharacter(player: Player, character: Model)
	local head = character:WaitForChild("Head", 10)
	if not head then return end
	
	-- Check if already exists (in case of rapid respawn or double call)
	if head:FindFirstChild("RankOverhead") then return end

	local ui = createOverheadUI()
	ui.Adornee = head
	ui.Parent = head
	
	local label = ui.InfoLabel
	updateLabel(player, label)
	
	-- Listen for attribute changes
	player.AttributeChanged:Connect(function(attributeName)
		if attributeName == "Level" or attributeName == "XP" then
			updateLabel(player, label)
		end
	end)
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character)
		setupCharacter(player, character)
	end)
	
	if player.Character then
		setupCharacter(player, player.Character)
	end
end

-- Initialize for all players (so you can see everyone's rank)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
