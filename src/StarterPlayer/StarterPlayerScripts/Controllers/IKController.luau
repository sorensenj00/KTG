--[[
    Controller: IKController
    Description: Implements Inverse Kinematics for foot planting on uneven terrain.
    Supports dynamic character scaling.

    Dependencies:
    - Players, RunService, Workspace

    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local IKController = {}

-- Configuration
local RAYCAST_DISTANCE_DOWN = 10 -- Base distance, scales with character
local SMOOTH_SPEED = 15 -- Lerp speed for foot movement
local FOOT_ANGLE_LIMIT = 45 -- Max angle for foot rotation (degrees)

-- State
local player = Players.LocalPlayer
local character = nil
local humanoid = nil
local rootPart = nil
local ikControls = {}
local targetParts = {}
local connections = {}
local currentScale = 1

-- Raycast Params
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function cleanup()
	for _, conn in ipairs(connections) do
		conn:Disconnect()
	end
	connections = {}

	for _, ik in pairs(ikControls) do
		ik:Destroy()
	end
	ikControls = {}

	for _, part in pairs(targetParts) do
		part:Destroy()
	end
	targetParts = {}

	character = nil
	humanoid = nil
	rootPart = nil
end

local function setupLeg(side: "Left" | "Right")
	if not character then return end

	-- Find limbs
	local foot = character:FindFirstChild(side .. "Foot")
	local lower = character:FindFirstChild(side .. "LowerLeg")
	local upper = character:FindFirstChild(side .. "UpperLeg")

	if not (foot and lower and upper) then return end

	-- Create Target Part (Visualizer/Target for IK)
	-- We use a physical part or Attachment. IKControl works best with an Attachment or BasePart.
	-- Using an Attachment inside the Terrain (or a hidden part) allows for easy positioning.
	-- Let's use a hidden Anchored part for the target to ensure stability.
	local targetPart = Instance.new("Part")
	targetPart.Name = side .. "FootIKTarget"
	targetPart.Size = Vector3.new(0.2, 0.2, 0.2)
	targetPart.Transparency = 1
	targetPart.CanCollide = false
	targetPart.CanQuery = false
	targetPart.CanTouch = false
	targetPart.Anchored = true
	targetPart.Parent = Workspace.CurrentCamera -- Hide in camera/workspace

	targetParts[side] = targetPart

	-- Create IKControl
	local ik = Instance.new("IKControl")
	ik.Name = side .. "LegIK"
	ik.Type = Enum.IKControlType.Position -- We want to place the foot
	ik.EndEffector = foot
	ik.ChainRoot = upper
	ik.Target = targetPart
	ik.SmoothTime = 0.1 -- Built-in smoothing
	ik.Weight = 0 -- Start disabled until we have a valid ground hit
	ik.Parent = humanoid

	ikControls[side] = ik
end

local function updateLeg(dt, side: "Left" | "Right")
	local ik = ikControls[side]
	local target = targetParts[side]

	if not (ik and target and rootPart) then return end

	-- Get current scale
	-- R15 scale can be approximated from HipHeight / BaseHipHeight (2), or just assume HipHeight scales linearly.
	-- Standard R15 HipHeight is 2.
	-- A better metric for this game (which uses ScaleTo) is character:GetScale() but that's a new API.
	-- Let's stick to HipHeight ratio or root part size.
	local scale = 1
	if humanoid then
		scale = humanoid.HipHeight / 2 -- Approx scale relative to standard
	end
	currentScale = scale

	-- Origin for raycast: Top of the leg (Hip)
	-- We want to cast from the hip DOWN to the floor.
	-- The "UpperLeg" position is a good start.
	local upperLeg = character:FindFirstChild(side .. "UpperLeg")
	if not upperLeg then return end

	local rayOrigin = upperLeg.Position
	local rayDirection = Vector3.new(0, -RAYCAST_DISTANCE_DOWN * scale, 0)

	-- Update Filter
	rayParams.FilterDescendantsInstances = {character, targetParts["Left"], targetParts["Right"]}

	local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)

	if result then
		-- Ground found!

		-- 1. Calculate Target Position
		-- We want the foot to be ON the ground.
		-- The IK Target is where the CENTER of the foot should be.
		-- R15 Foot center is roughly height/2 above ground.
		local footHeight = (0.5 * scale) -- Approx foot half-height
		local targetPos = result.Position + Vector3.new(0, footHeight, 0)

		-- Smoothly interpolate target position
		target.CFrame = target.CFrame:Lerp(CFrame.new(targetPos), dt * SMOOTH_SPEED)

		-- 2. Calculate Foot Rotation (Align with Normal)
		-- Get the surface normal
		local normal = result.Normal

		-- Calculate rotation CFrame
		local forward = rootPart.CFrame.LookVector
		local right = forward:Cross(normal)
		local newForward = normal:Cross(right)

		-- CFrame.fromMatrix(pos, right, up, back)
		-- We calculated 'newForward' which points forward. The 3rd vector arg is the BackVector.
		-- So we pass -newForward.
		local targetRotation = CFrame.fromMatrix(targetPos, right, normal, -newForward)

		-- Apply rotation to the target
		-- Note: IKControl Type=Position usually ignores rotation unless we use Transform.
		-- To align foot to slope, we might need Type=Transform.
		-- However, Position + Pole is easier.
		-- Let's try upgrading to Transform if Position isn't enough, but usually,
		-- for basic slope standing, we rely on the IK solver to rotate the foot if we set orientation.
		-- Wait, IKControl Type.Position DOES NOT affect rotation.
		-- We need Type.Transform to control rotation.

		if ik.Type ~= Enum.IKControlType.Transform then
			ik.Type = Enum.IKControlType.Transform
		end

		target.CFrame = target.CFrame:Lerp(targetRotation, dt * SMOOTH_SPEED)

		-- Enable IK
		ik.Weight = math.min(ik.Weight + dt * 5, 1) -- Fade in
	else
		-- No ground (Jumping/Falling)
		ik.Weight = math.max(ik.Weight - dt * 5, 0) -- Fade out
	end
end


local function onCharacterAdded(newChar)
	cleanup()
	character = newChar
	humanoid = character:WaitForChild("Humanoid")
	rootPart = character:WaitForChild("HumanoidRootPart")

	-- Only R15 supported
	if humanoid.RigType == Enum.HumanoidRigType.R15 then
		setupLeg("Left")
		setupLeg("Right")

		local conn = RunService.Stepped:Connect(function(time, dt)
			updateLeg(dt, "Left")
			updateLeg(dt, "Right")
		end)
		table.insert(connections, conn)
	end
end

function IKController.Start()
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end

	print("✅ IKController: Initialized")
end

return IKController
