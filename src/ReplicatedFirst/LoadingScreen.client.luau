--[[
	Loading Screen
	Description: Runs immediately in ReplicatedFirst to cover initialization.
	Waits for Client.client.luau to set "GameLoaded" attribute on LocalPlayer.
]]

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

-- Remove default Roblox loading screen
ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Create Loading UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "LoadingScreen"
screenGui.DisplayOrder = 1000 -- On top of everything
screenGui.IgnoreGuiInset = true
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local bg = Instance.new("Frame")
bg.Name = "Background"
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.fromRGB(10, 14, 20) -- Match Lobby Theme
bg.BorderSizePixel = 0
bg.Parent = screenGui

local loadingText = Instance.new("TextLabel")
loadingText.Text = "LOADING..."
loadingText.Size = UDim2.new(1, 0, 0, 50)
loadingText.Position = UDim2.fromScale(0.5, 0.5)
loadingText.AnchorPoint = Vector2.new(0.5, 0.5)
loadingText.BackgroundTransparency = 1
loadingText.TextColor3 = Color3.fromRGB(200, 170, 110) -- Gold
loadingText.Font = Enum.Font.GothamBold
loadingText.TextSize = 24
loadingText.Parent = bg

-- Animate Text
task.spawn(function()
	while screenGui.Parent do
		loadingText.TextTransparency = 0.5
		TweenService:Create(loadingText, TweenInfo.new(0.5), {TextTransparency = 0}):Play()
		task.wait(0.5)
		TweenService:Create(loadingText, TweenInfo.new(0.5), {TextTransparency = 0.5}):Play()
		task.wait(0.5)
	end
end)

-- Wait for Game Load
if not player:GetAttribute("GameLoaded") then
	player:GetAttributeChangedSignal("GameLoaded"):Wait()
end

-- Fade Out
local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local tween = TweenService:Create(bg, fadeInfo, {BackgroundTransparency = 1})
TweenService:Create(loadingText, fadeInfo, {TextTransparency = 1}):Play()

tween:Play()
tween.Completed:Connect(function()
	screenGui:Destroy()
end)
