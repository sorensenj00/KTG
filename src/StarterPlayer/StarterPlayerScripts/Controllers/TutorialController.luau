local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local HighlightManager = require(script.Parent.Parent.Utility.HighlightManager)


local TutorialController = {}

local player = Players.LocalPlayer

-- Tutorial States
local STATES = {
	MOVEMENT = 1,
	COMBAT = 2,
	COLLECTION = 3,
	YEETCANNON = 4,
	SHOP = 5,
	EVOLUTION = 6,
	COMPLETE = 7,
}

local MISSIONS = {
	[STATES.MOVEMENT] = "Use WASD or Joystick to move around!",
	[STATES.COMBAT] = "Find a bot and shoot them to earn Biomass!",
	[STATES.COLLECTION] = "Collect the orbs they dropped to grow big!",
	[STATES.YEETCANNON] = "Go to the YeetCannon to launch yourself to a new island!",
	[STATES.SHOP] = "Click the 'Mutation Lab' button to open the shop!",
	[STATES.EVOLUTION] = "Buy your first mutation to evolve!",
	[STATES.COMPLETE] = "",
}

local currentState = STATES.MOVEMENT
local tutorialActive = false
local hudController = nil

-- === Helper Functions ===

local function getNearestBot()
	local bots = CollectionService:GetTagged("BotAI")
	local nearestBot = nil
	local shortestDistance = math.huge
	local char = player.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	
	for _, bot in bots do
		if bot:IsA("Model") and bot.PrimaryPart then
			local dist = (bot.PrimaryPart.Position - root.Position).Magnitude
			if dist < shortestDistance then
				shortestDistance = dist
				nearestBot = bot
			end
		end
	end
	return nearestBot
end

-- === Public API ===

function TutorialController.Init(hc)
	hudController = hc
end

function TutorialController.Start()
	-- Don't restart if already complete in this session
	if player:GetAttribute("TutorialComplete") then
		return
	end

	currentState = STATES.MOVEMENT
	tutorialActive = true
	TutorialController.UpdateUI()

	-- 1. Movement Check
	task.spawn(function()
		while tutorialActive and currentState == STATES.MOVEMENT do
			local moveVec = UserInputService:GetMoveVector()
			if moveVec.Magnitude > 0.1 then
				task.wait(1) -- Short delay to ensure they actually moved
				if currentState == STATES.MOVEMENT then
					TutorialController.Advance()
				end
				break
			end
			task.wait(0.2)
		end
	end)

	-- 2. Collection Check
	local connection
	connection = player:GetAttributeChangedSignal("Biomass"):Connect(function()
		if tutorialActive and currentState == STATES.COLLECTION then
			local biomass = player:GetAttribute("Biomass") or 0
			if biomass > 10 then -- Gained at least one orb
				TutorialController.Advance()
				connection:Disconnect()
			end
		end
	end)
end

function TutorialController.OnEnemyHit()
	if tutorialActive and currentState == STATES.COMBAT then
		TutorialController.Advance()
	end
end

function TutorialController.OnOrbCollected()
	if tutorialActive and currentState == STATES.COLLECTION then
		TutorialController.Advance()
	end
end

function TutorialController.OnYeetCannonEntered()
	if tutorialActive and currentState == STATES.YEETCANNON then
		TutorialController.Advance()
	end
end

function TutorialController.OnShopOpened()
	if tutorialActive and currentState == STATES.SHOP then
		TutorialController.Advance()
	end
end

function TutorialController.OnMutationPurchased()
	if tutorialActive and currentState == STATES.EVOLUTION then
		TutorialController.Advance()
	end
end

function TutorialController.Advance()
	currentState += 1
	if currentState >= STATES.COMPLETE then
		tutorialActive = false
		player:SetAttribute("TutorialComplete", true)
		HighlightManager.ClearAll()
		print("🎓 Tutorial Complete!")
	end
	TutorialController.UpdateUI()
end

function TutorialController.UpdateUI()
	HighlightManager.ClearAll()
	
	if not hudController or not hudController.SetTutorialText then
		return
	end

	local missionText = MISSIONS[currentState] or ""
	hudController.SetTutorialText(missionText)
	
	if not tutorialActive then return end
	
	-- Visual Indicators Trigger
	if currentState == STATES.COMBAT then
		task.spawn(function()
			local lastBot = nil
			while tutorialActive and currentState == STATES.COMBAT do
				local bot = getNearestBot()
				if bot and bot ~= lastBot then
					HighlightManager.PointArrowAt(bot)
					lastBot = bot
				end
				task.wait(2)
			end
		end)
	elseif currentState == STATES.YEETCANNON then
		local yeetCannon = Workspace:FindFirstChild("YeetCannon")
		if yeetCannon then
			HighlightManager.PointArrowAt(yeetCannon)
		end
	elseif currentState == STATES.SHOP then
		if hudController.GetButton then
			local shopButton = hudController.GetButton("MutationsButton")
			if shopButton then
				HighlightManager.HighlightUI(shopButton)
			end
		end
	end
end

function TutorialController.Reset()
	player:SetAttribute("TutorialComplete", false)
	TutorialController.Start()
end

return TutorialController
