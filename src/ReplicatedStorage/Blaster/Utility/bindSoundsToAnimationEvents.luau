local ReplicatedStorage = game:GetService("ReplicatedStorage")
local playSoundFromSource = require(ReplicatedStorage.Blaster.Utility.playSoundFromSource)

local function bindSoundsToAnimationEvents(
	animationTrack: AnimationTrack,
	soundsFolder: Folder,
	audioTarget: AudioFader?
)
	animationTrack:GetMarkerReachedSignal("PlaySound"):Connect(function(soundName: string)
		--print(`[bindSounds] Event triggered! SoundName: '{soundName}'`)

		if not soundsFolder then
			warn("[bindSounds] soundsFolder is nil!")
			return
		end

		local soundOrFolder = soundsFolder:FindFirstChild(soundName)
		if not soundOrFolder then
			warn(`[bindSounds] Could not find sound or folder '{soundName}' in {soundsFolder:GetFullName()}`)
			-- List available children for debugging
			local children = {}
			for _, c in soundsFolder:GetChildren() do
				table.insert(children, c.Name)
			end
			--print("[bindSounds] Available sounds:", table.concat(children, ", "))
			return
		end

		if soundOrFolder:IsA("Folder") then
			-- If it's a folder (like "Shoot"), pick a random sound from inside
			local sounds = soundOrFolder:GetChildren()
			if #sounds > 0 then
				local randomSound = sounds[math.random(1, #sounds)]
				--print(`[bindSounds] Playing random sound: {randomSound.Name} from folder`)
				if randomSound:IsA("Sound") then
					playSoundFromSource(randomSound, audioTarget)
				end
			else
				warn(`[bindSounds] Folder '{soundName}' is empty!`)
			end
		elseif soundOrFolder:IsA("Sound") then
			-- If it's a direct sound file, play it normally
			--print(`[bindSounds] Playing sound: {soundOrFolder.Name}`)
			playSoundFromSource(soundOrFolder, audioTarget)
		end
	end)
end

return bindSoundsToAnimationEvents
