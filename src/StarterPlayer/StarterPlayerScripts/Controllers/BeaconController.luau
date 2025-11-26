local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local BeaconController = {}

-- Constants
local TITAN_LEVEL_REQ = 20
local BEACON_VISIBLE_DISTANCE = 1000
local UPDATE_INTERVAL = 0.1 -- Update visibility every 0.1s to save performance

-- State
local activeBeacons = {} -- [Model] = BillboardGui
local localPlayer = Players.LocalPlayer

-- Assets
local BEACON_COLOR = Color3.fromRGB(255, 50, 50) -- Red warning color

local function createBeacon(targetChar: Model)
	if activeBeacons[targetChar] then return end
	
	local head = targetChar:FindFirstChild("Head")
	if not head then return end
	
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TitanBeacon"
	billboard.Adornee = head
	billboard.Size = UDim2.fromOffset(200, 100)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Enabled = false -- Hidden by default until distance check
	
	local container = Instance.new("Frame")
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = billboard
	
	local icon = Instance.new("ImageLabel")
	icon.Size = UDim2.fromOffset(40, 40)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.AnchorPoint = Vector2.new(0.5, 1)
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://11563251" -- Generic warning/target icon (placeholder)
	icon.ImageColor3 = BEACON_COLOR
	icon.Parent = container
	
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 0.3)
	text.Position = UDim2.fromScale(0.5, 0.5)
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.BackgroundTransparency = 1
	text.Text = "TITAN"
	text.TextColor3 = BEACON_COLOR
	text.TextStrokeTransparency = 0
	text.Font = Enum.Font.GothamBlack
	text.TextSize = 24
	text.Parent = container
	
	-- Add arrow pointing down
	local arrow = Instance.new("ImageLabel")
	arrow.Size = UDim2.fromOffset(30, 30)
	arrow.Position = UDim2.fromScale(0.5, 0.8)
	arrow.AnchorPoint = Vector2.new(0.5, 0)
	arrow.BackgroundTransparency = 1
	arrow.Image = "rbxassetid://6031091004" -- Down arrow
	arrow.ImageColor3 = BEACON_COLOR
	arrow.Parent = container
	
	-- Animate the arrow
	local tweenInfo = TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = game:GetService("TweenService"):Create(arrow, tweenInfo, {Position = UDim2.fromScale(0.5, 0.9)})
	tween:Play()
	
	billboard.Parent = targetChar
	activeBeacons[targetChar] = billboard
	
	-- Cleanup when character is removed
	targetChar.AncestryChanged:Connect(function(_, parent)
		if not parent then
			if activeBeacons[targetChar] then
				activeBeacons[targetChar]:Destroy()
				activeBeacons[targetChar] = nil
			end
		end
	end)
end

local function removeBeacon(targetChar: Model)
	if activeBeacons[targetChar] then
		activeBeacons[targetChar]:Destroy()
		activeBeacons[targetChar] = nil
	end
end

local function checkTitanStatus(targetChar: Model)
	if targetChar == localPlayer.Character then return end -- Don't show beacon on self (optional, maybe user wants it?)
	
	local level = targetChar:GetAttribute("Level") or 1
	if level > TITAN_LEVEL_REQ then
		createBeacon(targetChar)
	else
		removeBeacon(targetChar)
	end
end

local function setupCharacter(character: Model)
	-- Initial check
	checkTitanStatus(character)
	
	-- Listen for level changes
	character:GetAttributeChangedSignal("Level"):Connect(function()
		checkTitanStatus(character)
	end)
end

function BeaconController.Start()
	print("BeaconController started")
	
	-- 1. Track Players
	local function onPlayerAdded(p)
		p.CharacterAdded:Connect(setupCharacter)
		if p.Character then
			setupCharacter(p.Character)
		end
	end
	
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayerAdded(p)
	end
	
	-- 2. Track Bots (via CollectionService)
	CollectionService:GetInstanceAddedSignal("BotAI"):Connect(setupCharacter)
	for _, bot in ipairs(CollectionService:GetTagged("BotAI")) do
		setupCharacter(bot)
	end
	
	-- 3. Update Loop (Visibility & Distance)
	local lastUpdate = 0
	RunService.Heartbeat:Connect(function(dt)
		lastUpdate += dt
		if lastUpdate < UPDATE_INTERVAL then return end
		lastUpdate = 0
		
		local myChar = localPlayer.Character
		local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
		
		if not myRoot then return end
		
		for char, billboard in pairs(activeBeacons) do
			if char.Parent and billboard.Parent then
				local targetRoot = char:FindFirstChild("HumanoidRootPart")
				if targetRoot then
					local dist = (targetRoot.Position - myRoot.Position).Magnitude
					if dist <= BEACON_VISIBLE_DISTANCE then
						billboard.Enabled = true
						
						-- Optional: Scale opacity by distance?
						-- For now, just toggle visibility
					else
						billboard.Enabled = false
					end
				end
			else
				-- Cleanup invalid entries
				activeBeacons[char] = nil
			end
		end
	end)
end

return BeaconController
