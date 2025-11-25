local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local ProgressionManager = require(script.Parent.ProgressionManager)

local WinnerManager = {}

function WinnerManager.Start()
	print("--- Starting WinnerManager ---")

	local winnerStore = nil
	-- Safely attempt to get DataStore (prevents errors in unpublished Studio places)
	local success, store = pcall(function()
		return DataStoreService:GetDataStore("KillToGrow_WinnerStore_v1")
	end)

	if success then
		winnerStore = store
	else
		if RunService:IsStudio() then
			warn(
				"WinnerManager: DataStoreService is not available in Studio unless published with API Access enabled. Winner saving is disabled."
			)
		else
			warn("WinnerManager: Failed to load DataStoreService:", store)
		end
	end

	-- Visual Constants
	local STAR_POSITION = Vector3.new(0, 200, 0)
	local STAR_SIZE = Vector3.new(20, 20, 2)
	local STAR_COLOR = Color3.fromRGB(255, 215, 0) -- Gold

	-- State
	local currentWinnerName = "None"

	-- Setup Visuals
	local mapVisuals = Workspace:FindFirstChild("MapVisuals") or Instance.new("Folder")
	mapVisuals.Name = "MapVisuals"
	mapVisuals.Parent = Workspace

	local starPart = mapVisuals:FindFirstChild("WinnerStar") or Instance.new("Part")
	starPart.Name = "WinnerStar"
	starPart.Anchored = true
	starPart.CanCollide = false
	starPart.Position = STAR_POSITION
	starPart.Size = STAR_SIZE
	starPart.Color = STAR_COLOR
	starPart.Material = Enum.Material.Neon
	starPart.CastShadow = false
	starPart.Parent = mapVisuals

	local billboard = starPart:FindFirstChild("WinnerUI") or Instance.new("BillboardGui")
	billboard.Name = "WinnerUI"
	billboard.Size = UDim2.new(0, 400, 0, 100)
	billboard.StudsOffset = Vector3.new(0, 15, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = starPart

	local nameLabel = billboard:FindFirstChild("NameLabel") or Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.Text = "Current King: " .. currentWinnerName
	nameLabel.Parent = billboard

	-- Functions
	local function updateWinnerVisual(name)
		currentWinnerName = name
		nameLabel.Text = "Current King: " .. name
		print("👑 New King Crowned: " .. name)
	end

	local function saveWinner(name)
		if not winnerStore then
			return
		end

		local success, err = pcall(function()
			winnerStore:SetAsync("CurrentKing", name)
		end)
		if not success then
			warn("Failed to save winner:", err)
		end
	end

	local function loadWinner()
		if not winnerStore then
			updateWinnerVisual("Local Test")
			return
		end

		local success, savedName = pcall(function()
			return winnerStore:GetAsync("CurrentKing")
		end)

		if success and savedName then
			updateWinnerVisual(savedName)
		else
			updateWinnerVisual("No One Yet")
		end
	end

	-- Listen for Events
	ProgressionManager.PlayerReachedMaxLevel.Event:Connect(function(entity)
		if entity:IsA("Player") then
			local name = entity.Name
			updateWinnerVisual(name)
			saveWinner(name)

			-- Optional: Broadcast Message?
		elseif entity:IsA("Model") then
			-- Bot won?
			updateWinnerVisual("Bot " .. entity.Name)
		end
	end)

	-- Init
	task.spawn(loadWinner)
end

return WinnerManager
