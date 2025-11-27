local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- === CONFIGURATION ===
local SENSITIVITY = 0.5 -- Adjusted for GetMouseDelta (starts higher)
local CAMERA_OFFSET = Vector3.new(0, 8, 20)

local YeetCannonController = {}
YeetCannonController.__index = YeetCannonController

function YeetCannonController.new()
	local self = setmetatable({}, YeetCannonController)
	self.cannon = nil
	self.seat = nil
	self.isSeated = false
	self.connections = {}
	self.currentPitch = 0
	self.currentYaw = 0
	self.targetPitch = 0
	self.targetYaw = 0
	self.viewmodelBindName = "YeetCannonViewModel"
	self.originalPivot = nil
	self.highlight = nil
	return self
end

function YeetCannonController:findCannon()
	local cannon = Workspace:FindFirstChild("YeetCannon")
	if not cannon then
		return false
	end

	self.cannon = cannon
	self.seat = cannon:FindFirstChildOfClass("VehicleSeat") or cannon:FindFirstChildOfClass("Seat")

	if not self.seat then
		return false
	end

	-- FORCE PRIMARY PART TO SEAT
	self.cannon.PrimaryPart = self.seat

	-- Find prompt
	for _, desc in ipairs(cannon:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			self.prompt = desc
			break
		end
	end

	return true
end

function YeetCannonController:toggleVisuals(isInside)
	local char = player.Character
	if char then
		for _, part in ipairs(char:GetDescendants()) do
			if part:IsA("BasePart") or part:IsA("Decal") then
				part.LocalTransparencyModifier = isInside and 1 or 0
			end
		end
		if isInside then
			local hum = char:FindFirstChild("Humanoid")
			if hum then
				hum:UnequipTools()
			end
		end
	end

	if self.cannon then
		for _, part in ipairs(self.cannon:GetDescendants()) do
			if part:IsA("BasePart") and part ~= self.seat then
				part.LocalTransparencyModifier = isInside and 0.9 or 0
			end
		end
	end
end

function YeetCannonController:onSeated(seat)
	if self.isSeated then
		return
	end
	
	-- Verify this is a YeetCannon seat
	local model = seat:FindFirstAncestorWhichIsA("Model")
	if not model or not string.match(model.Name, "^YeetCannon") then
		return
	end
	
	self.cannon = model
	self.seat = seat
	self.isSeated = true
	
	-- Find prompt (optional, just to disable it locally)
	for _, desc in ipairs(self.cannon:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			self.prompt = desc
			break
		end
	end

	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	self.currentPitch = 0
	self.currentYaw = 0
	self.targetPitch = 0
	self.targetYaw = 0

	self.originalPivot = self.seat.CFrame

	if self.prompt then
		self.prompt.Enabled = false
	end

	self:connectInputEvents()
	self:createHighlight()
	self:toggleVisuals(true)
	self:createViewModel()
end

function YeetCannonController:onUnseated()
	if not self.isSeated then
		return
	end
	self.isSeated = false

	-- 1. Reset Camera Controls
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	camera.CameraType = Enum.CameraType.Custom

	-- 2. Return Camera to Character
	if player.Character and player.Character:FindFirstChild("Humanoid") then
		camera.CameraSubject = player.Character.Humanoid
	end

	-- 3. Re-enable the Prompt so you can sit again later
	if self.prompt then
		self.prompt.Enabled = true
	end

	-- 4. Disconnect Inputs
	local ContextActionService = game:GetService("ContextActionService")
	ContextActionService:UnbindAction("YeetCannonFire")
	
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}

	-- 5. Cleanup Visuals
	self:removeHighlight()
	self:removeViewModel()
	self:toggleVisuals(false)

	-- === 6. RESET CANNON POSITION ===
	-- Snap the cannon back to where it was before we started aiming
	if self.cannon and self.originalPivot then
		self.cannon:PivotTo(self.originalPivot)

		-- Reset internal rotation variables too, so next time starts at 0
		self.currentPitch = 0
		self.currentYaw = 0
		self.targetPitch = 0
		self.targetYaw = 0
	end
	
	-- Clear references
	self.cannon = nil
	self.seat = nil
	self.prompt = nil
	self.originalPivot = nil
end

function YeetCannonController:connectInputEvents()
	-- Use ContextActionService for higher priority input handling
	-- This allows firing to work even when UI is active
	local ContextActionService = game:GetService("ContextActionService")
	
	ContextActionService:BindAction(
		"YeetCannonFire",
		function(actionName, inputState, inputObject)
			if inputState == Enum.UserInputState.Begin then
				if self.isSeated then
					self:fire()
					return Enum.ContextActionResult.Sink
				end
			end
			return Enum.ContextActionResult.Pass
		end,
		false,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.ButtonR2
	)
end

function YeetCannonController:createViewModel()
	RunService:BindToRenderStep(self.viewmodelBindName, Enum.RenderPriority.Camera.Value + 1, function(deltaTime)
		self:updateViewModel(deltaTime)
	end)
end

function YeetCannonController:updateViewModel(deltaTime)
	if not self.isSeated or not self.cannon or not self.originalPivot then
		return
	end

	-- === NEW INPUT METHOD: DIRECT DELTA READING ===
	-- This forces the script to read mouse movement every frame
	local delta = UserInputService:GetMouseDelta()

	-- Apply Delta
	self.targetYaw = self.targetYaw - (delta.X * SENSITIVITY * deltaTime)
	self.targetPitch = self.targetPitch - (delta.Y * SENSITIVITY * deltaTime)
	self.targetPitch = math.clamp(self.targetPitch, math.rad(-10), math.rad(80))

	-- Smooth Lerp
	local lerpSpeed = 0.2
	self.currentPitch = self.currentPitch + (self.targetPitch - self.currentPitch) * lerpSpeed
	self.currentYaw = self.currentYaw + (self.targetYaw - self.currentYaw) * lerpSpeed

	-- Rotate around the SEAT
	local rotationDelta = CFrame.Angles(0, self.currentYaw, 0) * CFrame.Angles(self.currentPitch, 0, 0)
	local finalCFrame = self.originalPivot * rotationDelta

	self.cannon:PivotTo(finalCFrame)

	-- Ensure Mouse Stays Locked (Fix for losing focus)
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

	-- Camera Position
	local pos = finalCFrame.Position
	local lookVector = finalCFrame.LookVector
	local upVector = finalCFrame.UpVector

	-- Camera Logic: Move Back and Up
	local camPos = pos + (lookVector * -20) + (upVector * 10)
	local aimTarget = pos + (lookVector * 1000)

	camera.CFrame = CFrame.lookAt(camPos, aimTarget)
end

function YeetCannonController:removeViewModel()
	RunService:UnbindFromRenderStep(self.viewmodelBindName)
end

function YeetCannonController:fire()
	if not self.isSeated then
		return
	end
	print("yeetcannonfire - attempting to fire")

	local blastFolder = ReplicatedStorage:FindFirstChild("Blaster")
	print("blastFolder:", blastFolder)
	if blastFolder then
		local remotes = blastFolder:FindFirstChild("Remotes")
		print("remotes:", remotes)
		if remotes then
			local fireRemote = remotes:FindFirstChild("YeetCannonFire")
			print("fireRemote:", fireRemote)
			if fireRemote then
				local rotationDelta = CFrame.Angles(0, self.currentYaw, 0) * CFrame.Angles(self.currentPitch, 0, 0)
				local currentSeatCFrame = self.originalPivot * rotationDelta

				-- Send launch data
				local muzzlePos = currentSeatCFrame.Position + (currentSeatCFrame.LookVector * 10)
				print("Firing remote to server! Direction:", currentSeatCFrame.LookVector)
				fireRemote:FireServer(currentSeatCFrame.LookVector, muzzlePos)
			else
				warn("YeetCannonFire remote not found!")
			end
		else
			warn("Remotes folder not found!")
		end
	else
		warn("Blaster folder not found!")
	end
end

function YeetCannonController:createHighlight()
	if not self.cannon then
		return
	end
	if self.highlight then
		self.highlight:Destroy()
	end
	local h = Instance.new("Highlight")
	h.FillTransparency = 1
	h.OutlineColor = Color3.new(0, 1, 0)
	h.Parent = self.cannon
	self.highlight = h
end

function YeetCannonController:removeHighlight()
	if self.highlight then
		self.highlight:Destroy()
		self.highlight = nil
	end
end

function YeetCannonController:start()
	-- Listen for character added to bind Seated event
	local function onCharacterAdded(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then
			hum.Seated:Connect(function(active, seatPart)
				if active and seatPart then
					self:onSeated(seatPart)
				else
					self:onUnseated()
				end
			end)
		end
	end

	if player.Character then
		onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(onCharacterAdded)
end

local controller = YeetCannonController.new()
controller:start()

return YeetCannonController
