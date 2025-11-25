local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

-- Get RemoteEvent
local remotes = ReplicatedStorage:WaitForChild("Blaster"):WaitForChild("Remotes")
local damageNumberRemote = remotes:WaitForChild("DamageNumber")

-- Object pool for damage number labels
local labelPool = {}
local activeLabels = {}
local MAX_POOL_SIZE = 20
local MAX_CONCURRENT_DAMAGE_NUMBERS = 5

-- Animation constants
local FLOAT_DURATION = 1.0
local FLOAT_DISTANCE = 50 -- pixels
local DRIFT_RANGE = 30 -- pixels horizontal drift
local FADE_START = 0.3 -- start fading after this time

-- Color constants
local COLORS = {
	NORMAL = Color3.fromRGB(255, 255, 255), -- White
	KILL = Color3.fromRGB(255, 215, 0), -- Gold
	HIGH_DAMAGE = Color3.fromRGB(255, 100, 100), -- Light red
	HEALING = Color3.fromRGB(0, 255, 0), -- Green
}

-- Create ScreenGui for damage numbers if it doesn't exist
local damageGui = Instance.new("ScreenGui")
damageGui.Name = "DamageNumbers"
damageGui.ResetOnSpawn = false
damageGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
damageGui.Parent = playerGui

-- Create a damage number label
local function createLabel(): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = "DamageNumber"
	label.Size = UDim2.fromOffset(100, 50)
	label.BackgroundTransparency = 1
	label.Text = ""
	label.TextColor3 = COLORS.NORMAL
	label.TextSize = 24
	label.Font = Enum.Font.GothamBold
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.ZIndex = 10
	label.Visible = false
	label.TextScaled = false
	-- AutoSize removed - TextLabel doesn't support AutoSize property
	return label
end

-- Get or create a label from the pool
local function getLabel(): TextLabel
	local label = table.remove(labelPool)
	if not label then
		label = createLabel()
		label.Parent = damageGui
	end
	return label
end

-- Return label to pool
local function returnLabel(label: TextLabel)
	if label and label.Parent then
		label.Visible = false
		label.Text = ""
		label.Position = UDim2.new()
		table.insert(labelPool, label)
	end
end

-- Show a damage number
local function showDamageNumber(damage: number, worldPosition: Vector3, isKill: boolean, xpAmount: number?)
	-- Limit concurrent damage numbers
	if #activeLabels >= MAX_CONCURRENT_DAMAGE_NUMBERS then
		local oldest = table.remove(activeLabels, 1)
		if oldest and oldest.label then
			returnLabel(oldest.label)
		end
	end

	local label = getLabel()
	if not label then
		return
	end

	-- Convert world position to screen space first
	local screenPoint, onScreen = camera:WorldToViewportPoint(worldPosition)
	
	if not onScreen then
		print("⚠️ Damage number off-screen, skipping")
		returnLabel(label)
		return
	end
	
	print("✅ Damage number on-screen at", screenPoint.X, screenPoint.Y)

	-- Check if this is healing (negative damage)
	local isHealing = damage < 0
	local absoluteValue = math.abs(damage)
	
	-- Set text and style
	local damageText
	if isHealing then
		-- Format as "+X HP" for healing
		damageText = "+" .. tostring(math.floor(absoluteValue)) .. " HP"
	else
		damageText = tostring(math.floor(damage))
	end
	
	-- Add XP text if this is a kill and XP amount is provided
	if isKill and xpAmount then
		damageText = damageText .. "\n+" .. tostring(math.floor(xpAmount)) .. " XP"
	end
	
	label.Text = damageText

	-- Style based on healing, kill, or damage amount
	if isHealing then
		label.TextColor3 = Color3.fromRGB(0, 255, 100) -- NEON GREEN
		label.TextSize = 26
		label.TextStrokeColor3 = Color3.fromRGB(0, 50, 0)
	elseif isKill then
		label.TextColor3 = COLORS.KILL
		label.TextSize = 32
		label.TextStrokeColor3 = Color3.fromRGB(100, 0, 0)
	elseif damage >= 50 then
		label.TextColor3 = COLORS.HIGH_DAMAGE
		label.TextSize = 28
	else
		label.TextColor3 = COLORS.NORMAL
		label.TextSize = 24
	end

	-- Ensure label is properly sized and visible
	-- Use a fixed size large enough for damage numbers (removed AutoSize - not supported)
	-- Increase height if showing XP (two lines)
	local labelHeight = (isKill and xpAmount) and 70 or 50
	label.Size = UDim2.fromOffset(150, labelHeight)
	label.TextTransparency = 0
	label.TextStrokeTransparency = 0.3
	
	-- Set initial position
	label.Position = UDim2.new(0, screenPoint.X, 0, screenPoint.Y)
	label.Visible = true

	-- Random horizontal drift
	local random = Random.new()
	local driftAmount = (random:NextNumber() - 0.5) * DRIFT_RANGE
	local endX = screenPoint.X + driftAmount
	local endY = screenPoint.Y - FLOAT_DISTANCE

	-- Create animation
	local startTime = tick()
	local labelData = {
		label = label,
		startX = screenPoint.X,
		startY = screenPoint.Y,
		endX = endX,
		endY = endY,
		startTime = startTime,
		isHealing = isHealing,
		absoluteValue = absoluteValue,
		isKill = isKill,
	}

	table.insert(activeLabels, labelData)

	-- Animate using RunService for smooth updates
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.min(elapsed / FLOAT_DURATION, 1)

		if progress >= 1 or not label.Parent then
			connection:Disconnect()
			-- Remove from active labels
			for i, data in ipairs(activeLabels) do
				if data == labelData then
					table.remove(activeLabels, i)
					break
				end
			end
			returnLabel(label)
			return
		end

		-- Interpolate position
		local currentX = labelData.startX + (labelData.endX - labelData.startX) * progress
		local currentY = labelData.startY + (labelData.endY - labelData.startY) * progress

		-- Easing function (ease out)
		local easedProgress = 1 - math.pow(1 - progress, 3)
		currentY = labelData.startY + (labelData.endY - labelData.startY) * easedProgress

		label.Position = UDim2.new(0, currentX, 0, currentY)

		-- Fade out
		if elapsed > FADE_START then
			local fadeProgress = (elapsed - FADE_START) / (FLOAT_DURATION - FADE_START)
			label.TextTransparency = math.min(fadeProgress, 1)
			label.TextStrokeTransparency = 0.3 + (fadeProgress * 0.7)
		else
			label.TextTransparency = 0
			label.TextStrokeTransparency = 0.3
		end

		-- Scale effect (slight bounce)
		local scale = 1
		if progress < 0.2 then
			-- Bounce in
			local bounceProgress = progress / 0.2
			scale = 0.5 + (bounceProgress * 0.5) * 1.2
		elseif progress < 0.4 then
			-- Settle
			local settleProgress = (progress - 0.2) / 0.2
			scale = 1.2 - (settleProgress * 0.2)
		else
			scale = 1
		end
		-- Calculate base text size (accounting for healing)
		local baseTextSize = 24
		if labelData.isHealing then
			baseTextSize = 26
		elseif labelData.isKill then
			baseTextSize = 32
		elseif labelData.absoluteValue >= 50 then
			baseTextSize = 28
		end
		label.TextSize = baseTextSize * scale
	end)
end

-- Listen for damage number events
damageNumberRemote.OnClientEvent:Connect(function(damage: number, worldPosition: Vector3, isKill: boolean, xpAmount: number?)
	print("🔢 DamageNumberController: Received damage event -", damage, "at", worldPosition, "isKill:", isKill, "XP:", xpAmount)
	showDamageNumber(damage, worldPosition, isKill, xpAmount)
end)

print("✅ DamageNumberController: Initialized and listening for damage events")

-- Cleanup on character removal
player.CharacterRemoving:Connect(function()
	-- Return all active labels to pool
	for _, labelData in ipairs(activeLabels) do
		if labelData.label then
			returnLabel(labelData.label)
		end
	end
	activeLabels = {}
end)

