--[[
    Utility: HighlightManager
    Description: Provides methods to highlight UI elements and point arrows at 3D objects.
]]

local TweenService = game:GetService("TweenService")

local HighlightManager = {}

local currentHighlight = nil
local currentArrow = nil

-- === UI Highlighting === --

function HighlightManager.HighlightUI(element: GuiObject)
	HighlightManager.ClearUIHighlight()
	
	if not element then return end
	
	-- Create a pulsating effect using a UIStroke or similar
	local stroke = element:FindFirstChild("TutorialHighlight") or Instance.new("UIStroke")
	stroke.Name = "TutorialHighlight"
	stroke.Color = Color3.fromRGB(255, 255, 0) -- Yellow
	stroke.Thickness = 0
	stroke.Transparency = 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = element
	
	local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(stroke, tweenInfo, {Thickness = 6, Transparency = 0.5})
	tween:Play()
	
	currentHighlight = {
		element = element,
		stroke = stroke,
		tween = tween
	}
end

function HighlightManager.ClearUIHighlight()
	if currentHighlight then
		if currentHighlight.tween then
			currentHighlight.tween:Cancel()
		end
		if currentHighlight.stroke then
			currentHighlight.stroke:Destroy()
		end
		currentHighlight = nil
	end
end

-- === 3D Arrow Pointing === --

function HighlightManager.PointArrowAt(target: Instance)
	HighlightManager.Clear3DArrow()
	
	if not target then return end
	
	-- Simple 3D Arrow using a Part or Attachment with a Beam/Trail or BillboardGui
	-- For simplicity, let's use a BillboardGui with an arrow image that points down
	local attachment = Instance.new("Attachment")
	attachment.Name = "TutorialArrowAttachment"
	
	if target:IsA("BasePart") then
		attachment.Parent = target
		attachment.Position = Vector3.new(0, 5, 0) -- Above the part
	elseif target:IsA("Model") then
		attachment.Parent = target.PrimaryPart or target:FindFirstChildWhichIsA("BasePart", true)
		if attachment.Parent then
			attachment.Position = Vector3.new(0, 5, 0)
		else
			attachment:Destroy()
			return
		end
	else
		attachment:Destroy()
		return
	end
	
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "TutorialArrow"
	billboard.Size = UDim2.fromOffset(50, 50)
	billboard.Adornee = attachment
	billboard.AlwaysOnTop = true
	billboard.Parent = attachment
	
	local arrow = Instance.new("ImageLabel")
	arrow.Size = UDim2.fromScale(1, 1)
	arrow.BackgroundTransparency = 1
	arrow.Image = "rbxassetid://6031094678" -- Downward arrow icon
	arrow.ImageColor3 = Color3.fromRGB(255, 255, 0)
	arrow.Parent = billboard
	
	-- Pulsate scale
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(arrow, tweenInfo, {Size = UDim2.fromScale(1.2, 1.2)})
	tween:Play()
	
	currentArrow = {
		attachment = attachment,
		tween = tween
	}
end

function HighlightManager.Clear3DArrow()
	if currentArrow then
		if currentArrow.tween then
			currentArrow.tween:Cancel()
		end
		if currentArrow.attachment then
			currentArrow.attachment:Destroy()
		end
		currentArrow = nil
	end
end

function HighlightManager.ClearAll()
	HighlightManager.ClearUIHighlight()
	HighlightManager.Clear3DArrow()
end

return HighlightManager
