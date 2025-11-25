local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Constants = require(ReplicatedStorage.Blaster.Constants)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local playSoundFromSource = require(ReplicatedStorage.Blaster.Utility.playSoundFromSource)
local player = Players.LocalPlayer
local playerGui = player.PlayerGui
local reticleGuiTemplate = ReplicatedStorage.Blaster.Scripts.GuiController.ReticleGui
local hitmarkerSound = ReplicatedStorage.Blaster.Scripts.GuiController.Hitmarker
local audioTarget = SoundService.Audio.Busses.UI.AudioCompressor
local HitmarkerController = {}
HitmarkerController.__index = HitmarkerController
function HitmarkerController.new()
	local reticleGui = reticleGuiTemplate:Clone()
	reticleGui.Enabled = false
	reticleGui.Parent = playerGui
	local scaleTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local transparencyTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local hitmarkerScaleTween = TweenService:Create(reticleGui.Hitmarker.UIScale, scaleTweenInfo, { Scale = 1 })
	local hitmarkerTransparencyTween =
		TweenService:Create(reticleGui.Hitmarker, transparencyTweenInfo, { GroupTransparency = 1 })
	local self = {
		reticleGui = reticleGui,
		hitmarkerScaleTween = hitmarkerScaleTween,
		hitmarkerTransparencyTween = hitmarkerTransparencyTween,
		enabled = false,
	}
	setmetatable(self, HitmarkerController)
	return self
end
function HitmarkerController:showHitmarker()
	-- Slightly delay the hitmarker sound so it doesn't overlap the shooting sound
	task.delay(Constants.HITMARKER_SOUND_DELAY, function()
		playSoundFromSource(hitmarkerSound, audioTarget)
	end)
	if self.hitmarkerScaleTween.PlaybackState == Enum.PlaybackState.Playing then
		self.hitmarkerScaleTween:Cancel()
	end
	if self.hitmarkerTransparencyTween.PlaybackState == Enum.PlaybackState.Playing then
		self.hitmarkerTransparencyTween:Cancel()
	end
	self.reticleGui.Hitmarker.GroupTransparency = 0
	self.reticleGui.Hitmarker.UIScale.Scale = 2
	self.hitmarkerScaleTween:Play()
	self.hitmarkerTransparencyTween:Play()
end
function HitmarkerController:enable()
	if self.enabled then
		return
	end
	self.enabled = true
	self.reticleGui.Enabled = true
	UserInputService.MouseIconEnabled = false
end
function HitmarkerController:disable()
	if not self.enabled then
		return
	end
	self.enabled = false
	self.reticleGui.Enabled = false
	UserInputService.MouseIconEnabled = true
end
function HitmarkerController:destroy()
	self:disable()
	self.reticleGui:Destroy()
end
return HitmarkerController

