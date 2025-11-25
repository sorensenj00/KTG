--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")



local Constants = require(ReplicatedStorage.Blaster.Constants)

local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)

local lerp = require(ReplicatedStorage.Utility.lerp)

local bindSoundsToAnimationEvents = require(script.Parent.Parent.Utility.bindSoundsToAnimationEvents)

local Spring = require(ReplicatedStorage.Utility.Spring)



local camera = Workspace.CurrentCamera

local viewModels = ReplicatedStorage.Blaster:WaitForChild("ViewModels")

local audioTarget = SoundService.Audio.Busses.World.AudioCompressor

local player = Players.LocalPlayer



local ViewModelController = {}

ViewModelController.__index = ViewModelController



function ViewModelController.new(blaster: Tool)

	-- Despite the blaster streaming mode being set to Atomic, objects outside of workspace are not streamed.

	-- This means we need to WaitForChild, since the blaster will be parented to the player's Backpack initially.

	local handle = blaster:WaitForChild("Handle")

	local sounds = blaster:WaitForChild("Sounds")



	local viewModelName = blaster:GetAttribute(Constants.VIEW_MODEL_ATTRIBUTE)

	local viewModelTemplate = viewModels[viewModelName]



	local viewModel = viewModelTemplate:Clone()

	local muzzle = viewModel:FindFirstChild("MuzzleAttachment", true)

	assert(muzzle, `{viewModel} is missing MuzzleAttachment!`)



	local animator = viewModel.AnimationController.Animator

	local animationsFolder = viewModel.Animations



	-- The viewModel needs to be parented to the DataModel in order to load animations, otherwise it will throw an error

	viewModel.Parent = ReplicatedStorage



	local animations = {}

	for _, animation in animationsFolder:GetChildren() do

		local animationTrack = animator:LoadAnimation(animation)

		animations[animation.Name] = animationTrack



		-- Sounds will all be driven by animation events

		bindSoundsToAnimationEvents(animationTrack, sounds, audioTarget)

	end



	-- Spring physics for recoil and sway
	local recoilSpringX = Spring.new(Constants.SWAY_SMOOTHNESS, Constants.RECOIL_RECOVERY_SPEED * 10)
	local recoilSpringY = Spring.new(Constants.SWAY_SMOOTHNESS, Constants.RECOIL_RECOVERY_SPEED * 10)
	local recoilSpringZ = Spring.new(Constants.SWAY_SMOOTHNESS, Constants.RECOIL_RECOVERY_SPEED * 10)
	
	local swaySpringX = Spring.new(Constants.SWAY_SMOOTHNESS, 50)
	local swaySpringY = Spring.new(Constants.SWAY_SMOOTHNESS, 50)
	local swaySpringZ = Spring.new(Constants.SWAY_SMOOTHNESS, 50)
	
	local landingSpring = Spring.new(15, 200)
	
	-- Track previous camera state for look sway
	local previousCameraCFrame = camera.CFrame
	local previousCameraRotation = previousCameraCFrame.Rotation
	
	-- Track humanoid for movement and landing detection
	local humanoid = nil
	local rootPart = nil
	local wasInAir = false
	
	local self = {

		enabled = false,

		blaster = blaster,

		handle = handle,

		model = viewModel,

		muzzle = muzzle,

		animations = animations,

		toolInstances = {},

		connections = {},

		stride = 0,

		bobbing = 0,
		
		-- Spring physics
		recoilSpringX = recoilSpringX,
		recoilSpringY = recoilSpringY,
		recoilSpringZ = recoilSpringZ,
		swaySpringX = swaySpringX,
		swaySpringY = swaySpringY,
		swaySpringZ = swaySpringZ,
		landingSpring = landingSpring,
		
		-- Camera tracking
		previousCameraCFrame = previousCameraCFrame,
		previousCameraRotation = previousCameraRotation,
		
		-- Humanoid tracking
		humanoid = humanoid,
		rootPart = rootPart,
		wasInAir = wasInAir,

	}

	setmetatable(self, ViewModelController)



	return self

end



function ViewModelController:update(deltaTime: number)

	-- Hide tool instances

	for _, instance in self.toolInstances do

		instance.LocalTransparencyModifier = 1

	end
	
	-- Update humanoid reference if needed
	if not self.humanoid or not self.humanoid.Parent then
		local character = self.blaster.Parent
		if character then
			self.humanoid = character:FindFirstChildOfClass("Humanoid")
			self.rootPart = character:FindFirstChild("HumanoidRootPart")
		end
	end
	
	-- Detect landing impact
	if self.humanoid and self.rootPart then
		local isInAir = self.humanoid.FloorMaterial == Enum.Material.Air
		if self.wasInAir and not isInAir then
			-- Just landed - apply downward spring impulse
			self.landingSpring:impulse(-0.3)
		end
		self.wasInAir = isInAir
	end
	
	-- Update all springs
	self.recoilSpringX:update(deltaTime)
	self.recoilSpringY:update(deltaTime)
	self.recoilSpringZ:update(deltaTime)
	self.swaySpringX:update(deltaTime)
	self.swaySpringY:update(deltaTime)
	self.swaySpringZ:update(deltaTime)
	self.landingSpring:update(deltaTime)
	
	-- Look Sway: Track camera rotation delta
	local currentCameraCFrame = camera.CFrame
	local currentCameraRotation = currentCameraCFrame.Rotation
	
	-- Calculate rotation delta
	local rotationDelta = self.previousCameraRotation:Inverse() * currentCameraRotation
	local _, yaw, pitch = rotationDelta:ToEulerAnglesXYZ()
	
	-- Apply look sway (banking on Z-axis when looking quickly)
	local lookSwayAmount = Constants.SWAY_AMOUNT
	self.swaySpringZ:setTarget(-yaw * lookSwayAmount * 0.5) -- Banking effect
	
	-- Move Sway: When strafing, drag gun opposite direction
	local moveSwayX = 0
	local moveSwayY = 0
	if self.humanoid then
		local moveDirection = self.humanoid.MoveDirection
		local moveMagnitude = moveDirection.Magnitude
		
		if moveMagnitude > 0.1 then
			-- Get camera right vector to determine strafe direction
			local cameraRight = currentCameraCFrame.RightVector
			local strafeDot = moveDirection:Dot(cameraRight)
			
			-- When strafing left (negative dot), drag gun right (positive sway)
			moveSwayX = -strafeDot * Constants.SWAY_AMOUNT * 0.3
		end
	end
	
	self.swaySpringX:setTarget(moveSwayX)
	
	-- Update previous camera state
	self.previousCameraCFrame = currentCameraCFrame
	self.previousCameraRotation = currentCameraRotation

	-- Movement bobbing using Humanoid.MoveDirection
	local moveSpeed = 0
	if self.humanoid then
		moveSpeed = self.humanoid.MoveDirection.Magnitude
	end
	
	local bobbingSpeed = moveSpeed * Constants.WALK_BOB_SPEED
	local bobbing = math.min(bobbingSpeed, 1)

	self.stride = (self.stride + bobbingSpeed * deltaTime) % (math.pi * 2)

	self.bobbing = lerp(self.bobbing, bobbing, math.min(deltaTime * Constants.VIEW_MODEL_BOBBING_TRANSITION_SPEED, 1))

	-- Bob up/down and left/right
	local x = math.sin(self.stride)
	local y = math.sin(self.stride * 2)
	local bobbingOffset = Vector3.new(x, y, 0) * Constants.WALK_BOB_MAGNITUDE * self.bobbing

	-- Combine all offsets
	local recoilOffset = Vector3.new(
		self.recoilSpringX:getPosition(),
		self.recoilSpringY:getPosition(),
		self.recoilSpringZ:getPosition()
	)
	
	local swayOffset = Vector3.new(
		self.swaySpringX:getPosition(),
		self.swaySpringY:getPosition(),
		self.swaySpringZ:getPosition()
	)
	
	local landingOffset = Vector3.new(0, self.landingSpring:getPosition(), 0)
	
	-- Apply recoil rotation (kick up and back)
	local recoilRotation = CFrame.Angles(
		math.rad(self.recoilSpringY:getPosition()),
		0,
		math.rad(self.recoilSpringZ:getPosition())
	)
	
	-- Apply sway rotation (banking)
	local swayRotation = CFrame.Angles(
		0,
		0,
		math.rad(self.swaySpringZ:getPosition())
	)
	
	-- Combine all transforms
	local totalOffset = bobbingOffset + swayOffset + landingOffset
	local totalCFrame = CFrame.new(totalOffset) * recoilRotation * swayRotation

	self.model:PivotTo(camera.CFrame * Constants.VIEW_MODEL_OFFSET * totalCFrame)

end



function ViewModelController:checkForToolInstance(instance: Instance)

	if not (instance:IsA("BasePart") or instance:IsA("Decal")) then

		return

	end



	local tool = instance:FindFirstAncestorOfClass("Tool")

	if not tool then

		return

	end



	table.insert(self.toolInstances, instance)

end



function ViewModelController:hideToolInstances()

	local character = self.blaster.Parent



	table.insert(

		self.connections,

		character.DescendantAdded:Connect(function(descendant: Instance)

			self:checkForToolInstance(descendant)

		end)

	)



	table.insert(

		self.connections,

		character.DescendantRemoving:Connect(function(descendant: Instance)

			local index = table.find(self.toolInstances, descendant)

			if index then

				table.remove(self.toolInstances, index)

			end

		end)

	)



	for _, descendant in character:GetDescendants() do

		self:checkForToolInstance(descendant)

	end

end



function ViewModelController:stopHidingToolInstances()

	table.clear(self.toolInstances)

	disconnectAndClear(self.connections)

end



function ViewModelController:getMuzzlePosition(): Vector3

	return self.muzzle.WorldPosition

end



function ViewModelController:playShootAnimation()

	self.animations.Shoot:Play(0)

	self.muzzle.FlashEmitter:Emit(1)

	self.muzzle.CircleEmitter:Emit(1)
	
	-- Apply recoil impulse (kick gun up and back)
	self.recoilSpringY:impulse(Constants.RECOIL_KICK_UP)
	self.recoilSpringZ:impulse(-Constants.RECOIL_KICK_BACK)

end



function ViewModelController:playReloadAnimation(reloadTime: number)

	self.animations.Shoot:Stop()

	local speed = self.animations.Reload.Length / reloadTime

	self.animations.Reload:Play(Constants.VIEW_MODEL_RELOAD_FADE_TIME, 1, speed)

end



function ViewModelController:enable()

	if self.enabled then

		return

	end

	self.enabled = true



	RunService:BindToRenderStep(

		Constants.VIEW_MODEL_BIND_NAME,

		Enum.RenderPriority.Camera.Value + 2, -- after aim assist

		function(deltaTime: number)

			self:update(deltaTime)

		end

	)

	self.model.Parent = Workspace

	self:hideToolInstances()



	-- Play equip and idle animations

	self.animations.Idle:Play()

	self.animations.Equip:Play(0)

end



function ViewModelController:disable()

	if not self.enabled then

		return

	end

	self.enabled = false



	RunService:UnbindFromRenderStep(Constants.VIEW_MODEL_BIND_NAME)

	self.model.Parent = nil

	self:stopHidingToolInstances()



	for _, animation in self.animations do

		animation:Stop(0)

	end

end



function ViewModelController:destroy()

	disconnectAndClear(self.connections)

	self:disable()

	-- Clean up springs
	if self.recoilSpringX then
		self.recoilSpringX = nil
	end
	if self.recoilSpringY then
		self.recoilSpringY = nil
	end
	if self.recoilSpringZ then
		self.recoilSpringZ = nil
	end
	if self.swaySpringX then
		self.swaySpringX = nil
	end
	if self.swaySpringY then
		self.swaySpringY = nil
	end
	if self.swaySpringZ then
		self.swaySpringZ = nil
	end
	if self.landingSpring then
		self.landingSpring = nil
	end

	self.model:Destroy()

end



return ViewModelController