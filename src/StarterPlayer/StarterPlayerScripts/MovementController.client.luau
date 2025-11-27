local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- Configuration
local SLIDE_COOLDOWN = 2 -- seconds
local SLIDE_BOOST_FORCE = 100 -- studs/second velocity boost
local SLIDE_DURATION = 0.5 -- seconds

-- State tracking
local lastSlideTime = 0
local isSliding = false
local character = nil
local humanoid = nil
local rootPart = nil
local isSprinting = false
local isCrouching = false

-- Helper to get baseplate center position
local function getBaseplateCenter()
	local baseplate = workspace:FindFirstChild("Baseplate")
	if baseplate then
		if baseplate:IsA("Model") then
			local cf, s = baseplate:GetBoundingBox()
			return cf.Position
		elseif baseplate:IsA("BasePart") then
			return baseplate.Position
		end
	end
	return Vector3.new(0, 0, 0)
end

-- Perform slide
local function performSlide()
	if not character or not rootPart or not humanoid then
		return
	end
	
	if humanoid.Health <= 0 then
		return
	end
	
	local currentTime = tick()
	if currentTime - lastSlideTime < SLIDE_COOLDOWN then
		return
	end
	
	-- Check if player is sprinting AND crouching
	if not isSprinting or not isCrouching then
		return
	end
	
	lastSlideTime = currentTime
	isSliding = true
	
	-- Get movement direction from humanoid
	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude < 0.1 then
		-- If not moving, use camera look direction
		local camera = workspace.CurrentCamera
		if camera then
			local cameraCFrame = camera.CFrame
			moveDirection = cameraCFrame.LookVector
			moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit
		else
			moveDirection = rootPart.CFrame.LookVector
			moveDirection = Vector3.new(moveDirection.X, 0, moveDirection.Z).Unit
		end
	end
	
	-- Apply velocity boost
	local slideVelocity = moveDirection * SLIDE_BOOST_FORCE
	rootPart.AssemblyLinearVelocity = rootPart.AssemblyLinearVelocity + slideVelocity
	
	-- Reset sliding state after duration
	task.delay(SLIDE_DURATION, function()
		isSliding = false
	end)
end

-- Setup character
local function setupCharacter(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid", 5)
	rootPart = character:WaitForChild("HumanoidRootPart", 5)
	
	if not humanoid or not rootPart then
		character = nil
		humanoid = nil
		rootPart = nil
		return
	end
	
	-- Reset slide cooldown on new character
	lastSlideTime = 0
	isSprinting = false
	isCrouching = false
end

-- Track input states
UserInputService.InputBegan:Connect(function(inputObject, gameProcessed)
	if gameProcessed then
		return
	end
	
	-- Track sprint (Shift)
	if inputObject.KeyCode == Enum.KeyCode.LeftShift or inputObject.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = true
		-- Try to slide if also crouching
		if isCrouching then
			performSlide()
		end
	end
	
	-- Track crouch (Ctrl or C)
	if inputObject.KeyCode == Enum.KeyCode.LeftControl 
		or inputObject.KeyCode == Enum.KeyCode.RightControl
		or inputObject.KeyCode == Enum.KeyCode.C then
		isCrouching = true
		if character then
			character:SetAttribute("IsCrouching", true)
		end
		-- Try to slide if also sprinting
		if isSprinting then
			performSlide()
		end
	end
end)

UserInputService.InputEnded:Connect(function(inputObject, gameProcessed)
	if gameProcessed then
		return
	end
	
	-- Track sprint release
	if inputObject.KeyCode == Enum.KeyCode.LeftShift or inputObject.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = false
	end
	
	-- Track crouch release
	if inputObject.KeyCode == Enum.KeyCode.LeftControl 
		or inputObject.KeyCode == Enum.KeyCode.RightControl
		or inputObject.KeyCode == Enum.KeyCode.C then
		isCrouching = false
		if character then
			character:SetAttribute("IsCrouching", false)
		end
	end
end)

-- Initialize
if player.Character then
	setupCharacter(player.Character)
end

player.CharacterAdded:Connect(setupCharacter)

