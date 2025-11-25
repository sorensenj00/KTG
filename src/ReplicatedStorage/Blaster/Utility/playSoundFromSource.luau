local SoundService = game:GetService("SoundService")

local function playSoundFromSource(soundTemplate: Sound, audioTarget: AudioFader?)
	local sound = soundTemplate:Clone()
	
	-- Set up 3D audio properties if not already set
	if sound:IsA("Sound") then
		-- Ensure the sound uses 3D spatial audio
		if sound.RollOffMode == Enum.RollOffMode.InverseTapered then
			-- Already set, keep it
		else
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
		end
		
		-- Set reasonable distance falloff if not already configured
		if sound.RollOffMinDistance == 0 then
			sound.RollOffMinDistance = 10
		end
		if sound.RollOffMaxDistance == 0 then
			sound.RollOffMaxDistance = 500
		end
	end
	
	if audioTarget then
		-- If we have an AudioEmitter, parent the sound to the part containing it
		-- This ensures proper 3D spatial audio positioning
		local emitterPart = audioTarget:FindFirstAncestorOfClass("BasePart")
		if emitterPart then
			sound.Parent = emitterPart
		else
			-- Fallback: parent to the AudioEmitter's parent
			sound.Parent = audioTarget.Parent
		end
		
		-- Create wire connection for AudioEmitter
		local wire = Instance.new("Wire")
		wire.SourceInstance = sound
		wire.TargetInstance = audioTarget
		wire.Parent = sound
	else
		-- No AudioEmitter, use SoundService (global audio)
		sound.Parent = SoundService
	end

	if sound:IsA("Sound") then
		sound.PlayOnRemove = true
	end

	sound:Destroy()
end

return playSoundFromSource
