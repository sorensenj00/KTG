--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Spring = require(ReplicatedStorage.Utility.Spring)

local CharacterAnimationController = {}
CharacterAnimationController.__index = CharacterAnimationController

function CharacterAnimationController.new(blaster: Tool)
	local self = {
		enabled = false,
		loadedAnimations = false,
		blaster = blaster,
		animationTracks = {},
		recoilSpring = Spring.new(20, 300), -- Damping, Stiffness
		connection = nil,
		waist = nil,
		originalC0 = nil,
	}
	setmetatable(self, CharacterAnimationController)
	return self
end

function CharacterAnimationController:playShootAnimation()
	self.animationTracks.Shoot:Play(0)
	self:playProceduralRecoil()
end

function CharacterAnimationController:playProceduralRecoil()
	-- Kick back (Z) and up (X rotation)
	self.recoilSpring:impulse(0.4)
end

function CharacterAnimationController:update(dt)
	if not self.waist or not self.originalC0 then
		-- Try to find waist
		local character = self.blaster.Parent
		if character then
			local upperTorso = character:FindFirstChild("UpperTorso")
			if upperTorso then
				self.waist = upperTorso:FindFirstChild("Waist")
				if self.waist then
					self.originalC0 = self.waist.C0
				end
			end
		end
		return
	end
	
	self.recoilSpring:update(dt)
	local recoilVal = self.recoilSpring:getPosition()
	
	-- Apply to Waist C0
	-- Rotate back (pitch)
	self.waist.C0 = self.originalC0 * CFrame.Angles(recoilVal, 0, 0)
end

function CharacterAnimationController:playReloadAnimation(reloadTime: number)
	local speed = self.animationTracks.Reload.Length / reloadTime
	self.animationTracks.Reload:Play(0.1, 1, speed)
end

function CharacterAnimationController:loadAnimations()
	if self.loadedAnimations then
		return
	end
	self.loadedAnimations = true
	local animationsFolder = self.blaster.Animations
	-- This should only be called when the blaster has been equipped
	local humanoid = self.blaster.Parent:FindFirstChildOfClass("Humanoid")
	assert(humanoid, "Blaster is not equipped")
	local animator = humanoid.Animator
	local animationTracks = {}
	for _, animation in animationsFolder:GetChildren() do
		local animationTrack = animator:LoadAnimation(animation)
		animationTracks[animation.Name] = animationTrack
		-- Unlike the ViewModelController, we won't tie any sounds to these animations.
		-- Since we're playing these animations from the client and relying on default replication behavior,
		-- any sounds we played here would overlap the view model sounds and wouldn't replicate.
	end
	self.animationTracks = animationTracks
end

function CharacterAnimationController:enable()
	if self.enabled then
		return
	end
	self.enabled = true
	-- Load animations if they haven't been loaded already
	if not self.loadedAnimations then
		self:loadAnimations()
	end
	self.animationTracks.Idle:Play()
	
	-- Bind to RenderStepped
	self.connection = RunService.RenderStepped:Connect(function(dt)
		self:update(dt)
	end)
end

function CharacterAnimationController:disable()
	if not self.enabled then
		return
	end
	self.enabled = false
	for _, animation in self.animationTracks do
		animation:Stop()
	end
	
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	
	-- Reset waist
	if self.waist and self.originalC0 then
		self.waist.C0 = self.originalC0
		self.waist = nil
		self.originalC0 = nil
	end
end

function CharacterAnimationController:destroy()
	self:disable()
	-- Clear the animationTracks table so we don't keep any references around.
	-- This makes sure the animation tracks get garbage collected correctly and don't cause a memory leak.
	table.clear(self.animationTracks)
end

return CharacterAnimationController