--[[
    Controller: DynamicCrosshairController
    Description: Procedural Crosshair that reacts to Movement, Stance, and Action.

    Features:
    - Procedural 4-part crosshair (Top, Bottom, Left, Right)
    - Dynamic Gap based on Velocity (Run), Stance (Crouch), and Action (Shoot)
    - Hit Confirmation (Flash Red)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local CrosshairSignals = require(ReplicatedStorage.Blaster.Scripts.CrosshairSignals)
local lerp = require(ReplicatedStorage.Utility.lerp)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DynamicCrosshairController = {}

-- Constants
local BASE_GAP = 6
local THICKNESS = 2
local LENGTH = 8
local COLOR_DEFAULT = Color3.new(1, 1, 1)
local COLOR_HIT = Color3.new(1, 0, 0) -- Red
local HIT_FLASH_DURATION = 0.3 -- Seconds to fade back to white

local GAP_VELOCITY_FACTOR = 0.2 -- How much speed affects gap
local CROUCH_REDUCTION = 4 -- How much gap shrinks when crouching
local BLOOM_PER_SHOT = 6 -- How much gap expands per shot
local BLOOM_DECAY_SPEED = 30 -- How fast bloom recovers

-- State
local currentGap = BASE_GAP
local currentBloom = 0
local hitFlashAlpha = 0 -- 0 = White, 1 = Red
local isRunning = false

-- UI Elements
local screenGui
local container
local topFrame, bottomFrame, leftFrame, rightFrame

local function createCrosshair()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DynamicCrosshair"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 10 -- Above most things
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = playerGui

	container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromOffset(100, 100)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Parent = screenGui

	-- Helper to create line
	local function createLine(name, size, anchor)
		local f = Instance.new("Frame")
		f.Name = name
		f.Size = size
		f.AnchorPoint = anchor
		f.BackgroundColor3 = COLOR_DEFAULT
		f.BorderSizePixel = 0
		f.Parent = container
		return f
	end

	topFrame = createLine("Top", UDim2.fromOffset(THICKNESS, LENGTH), Vector2.new(0.5, 1))
	bottomFrame = createLine("Bottom", UDim2.fromOffset(THICKNESS, LENGTH), Vector2.new(0.5, 0))
	leftFrame = createLine("Left", UDim2.fromOffset(LENGTH, THICKNESS), Vector2.new(1, 0.5))
	rightFrame = createLine("Right", UDim2.fromOffset(LENGTH, THICKNESS), Vector2.new(0, 0.5))
end

local function update(dt)
	local char = player.Character
	if not char then
		container.Visible = false
		return
	end

	local humanoid = char:FindFirstChild("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart")

	if not humanoid or not rootPart or humanoid.Health <= 0 then
		container.Visible = false
		return
	end

	container.Visible = true

	-- 1. Calculate Target Gap
	local velocity = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local isCrouching = char:GetAttribute("IsCrouching") == true

	local targetGap = BASE_GAP + (speed * GAP_VELOCITY_FACTOR)

	if isCrouching then
		targetGap = math.max(0, targetGap - CROUCH_REDUCTION)
	end

	-- Apply Bloom
	targetGap = targetGap + currentBloom

	-- 2. Smoothly interpolate Gap
	currentGap = lerp(currentGap, targetGap, dt * 15) -- 15 is smoothing speed

	-- 3. Update Positions
	local halfGap = currentGap / 2

	-- Top: Moves Up (Negative Y)
	topFrame.Position = UDim2.new(0.5, 0, 0.5, -halfGap)

	-- Bottom: Moves Down (Positive Y)
	bottomFrame.Position = UDim2.new(0.5, 0, 0.5, halfGap)

	-- Left: Moves Left (Negative X)
	leftFrame.Position = UDim2.new(0.5, -halfGap, 0.5, 0)

	-- Right: Moves Right (Positive X)
	rightFrame.Position = UDim2.new(0.5, halfGap, 0.5, 0)

	-- 4. Bloom Decay
	if currentBloom > 0 then
		currentBloom = math.max(0, currentBloom - (BLOOM_DECAY_SPEED * dt))
	end

	-- 5. Hit Flash Decay & Color
	if hitFlashAlpha > 0 then
		hitFlashAlpha = math.max(0, hitFlashAlpha - (dt / HIT_FLASH_DURATION))
		local color = COLOR_DEFAULT:Lerp(COLOR_HIT, hitFlashAlpha)
		topFrame.BackgroundColor3 = color
		bottomFrame.BackgroundColor3 = color
		leftFrame.BackgroundColor3 = color
		rightFrame.BackgroundColor3 = color
	else
		-- Ensure default color
		if topFrame.BackgroundColor3 ~= COLOR_DEFAULT then
			topFrame.BackgroundColor3 = COLOR_DEFAULT
			bottomFrame.BackgroundColor3 = COLOR_DEFAULT
			leftFrame.BackgroundColor3 = COLOR_DEFAULT
			rightFrame.BackgroundColor3 = COLOR_DEFAULT
		end
	end
end

function DynamicCrosshairController.Start()
	createCrosshair()

	-- Connect Events
	CrosshairSignals.Shoot.Event:Connect(function()
		currentBloom = currentBloom + BLOOM_PER_SHOT
	end)

	CrosshairSignals.Hit.Event:Connect(function()
		hitFlashAlpha = 1
	end)

	RunService.RenderStepped:Connect(update)

	print("✅ DynamicCrosshairController: Initialized")
end

return DynamicCrosshairController
