--!nocheck
-- Audio-Visual Sync Controller
-- Handles pitch variation and immediate hit marker sounds

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local playSoundFromSource = require(ReplicatedStorage.Blaster.Utility.playSoundFromSource)

local AudioController = {}
AudioController.__index = AudioController

function AudioController.new()
	local self = setmetatable({}, AudioController)

	-- Hit marker sound (will be created on first use)
	self.hitMarkerSound = nil

	return self
end

-- Play sound with pitch variation
function AudioController:playSoundWithVariation(sound: Sound, audioTarget: Instance?)
	if not sound then
		return
	end

	-- Randomize pitch between 0.95 and 1.05
	local random = Random.new()
	local pitchVariation = 1 + (random:NextNumber() - 0.5) * 2 * Constants.PITCH_VARIATION
	sound.PlaybackSpeed = pitchVariation

	playSoundFromSource(sound, audioTarget)
end

-- Play hit marker sound immediately (no server wait)
function AudioController:playHitMarkerSound()
	-- Create hit marker sound if it doesn't exist
	if not self.hitMarkerSound then
		self.hitMarkerSound = Instance.new("Sound")
		self.hitMarkerSound.SoundId = "rbxassetid://705502934" -- High-pitched tick/pop sound
		self.hitMarkerSound.Volume = 0.5
		self.hitMarkerSound.PlayOnRemove = false
		self.hitMarkerSound.Parent = SoundService
	end

	-- Play with slight pitch variation
	local random = Random.new()
	self.hitMarkerSound.PlaybackSpeed = 1.2 + (random:NextNumber() - 0.5) * 0.1 -- Higher pitch for "tick"
	self.hitMarkerSound:Play()
end

function AudioController:destroy()
	if self.hitMarkerSound then
		self.hitMarkerSound:Destroy()
		self.hitMarkerSound = nil
	end
end

return AudioController
