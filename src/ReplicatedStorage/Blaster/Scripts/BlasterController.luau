local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Constants = require(ReplicatedStorage.Blaster.Constants)
local AimAssistController = require(ReplicatedStorage.Blaster.Scripts.AimAssistController)
local AimAssistEnum = require(ReplicatedStorage.Blaster.Scripts.AimAssistController.AimAssistEnum)
local TouchInputController = require(ReplicatedStorage.Blaster.Scripts.TouchInputController)
-- CameraRecoiler removed: ViewModelController now handles all recoil
local CameraShaker = require(ReplicatedStorage.Blaster.Scripts.CameraShaker)
local ViewModelController = require(ReplicatedStorage.Blaster.Scripts.ViewModelController)
local CharacterAnimationController = require(ReplicatedStorage.Blaster.Scripts.CharacterAnimationController)
local HitmarkerController = require(ReplicatedStorage.Blaster.Scripts.HitmarkerController)
local AudioController = require(ReplicatedStorage.Blaster.Audio.AudioController)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local getRayDirections = require(ReplicatedStorage.Blaster.Utility.getRayDirections)
local drawRayResults = require(ReplicatedStorage.Blaster.Utility.drawRayResults)
local castRays = require(ReplicatedStorage.Blaster.Utility.castRays)
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local remotes = ReplicatedStorage.Blaster:WaitForChild("Remotes")
local shootRemote = remotes:WaitForChild("Shoot")
local reloadRemote = remotes:WaitForChild("Reload")
-- random removed: no longer needed since recoil is handled by ViewModelController
local BlasterController = {}
BlasterController.__index = BlasterController
function BlasterController.new(blaster: Tool)
	local aimAssistController = AimAssistController.new()
	local viewModelController = ViewModelController.new(blaster)
	local hitmarkerController = HitmarkerController.new()
	local touchInputController = TouchInputController.new(blaster)
	local characterAnimationController = CharacterAnimationController.new(blaster)
	local audioController = AudioController.new()
	local self = {
		blaster = blaster,
		aimAssistController = aimAssistController,
		viewModelController = viewModelController,
		hitmarkerController = hitmarkerController,
		touchInputController = touchInputController,
		characterAnimationController = characterAnimationController,
		audioController = audioController,
		activated = false,
		equipped = false,
		shooting = false,
		ammo = blaster:GetAttribute(Constants.AMMO_ATTRIBUTE),
		reloading = blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE),
		connections = {},
		shootHaptic = blaster:WaitForChild("Haptics"):WaitForChild("ShootHaptic"),
	}
	setmetatable(self, BlasterController)
	self:initialize()
	return self
end
function BlasterController:isHumanoidAlive(): boolean
	return self.humanoid and self.humanoid.Health > 0
end
function BlasterController:canShoot(): boolean
	return self:isHumanoidAlive() and self.equipped and self.ammo > 0 and not self.reloading
end
function BlasterController:canReload(): boolean
	local magazineSize = self.blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
	return self:isHumanoidAlive() and self.equipped and self.ammo < magazineSize and not self.reloading
end
function BlasterController:recoil()
	-- DISABLED: Camera recoil is now handled entirely by ViewModelController
	-- ViewModelController applies visual recoil to the weapon model using Spring physics
	-- This prevents the camera from being forced to look at the ground when shooting
	
	-- Recoil calculation kept for potential future use
	-- local xDif = self.recoilMax.X - self.recoilMin.X
	-- local yDif = self.recoilMax.Y - self.recoilMin.Y
	-- local x = self.recoilMin.X + random:NextNumber() * xDif
	-- local y = self.recoilMin.Y + random:NextNumber() * yDif
	-- local recoil = Vector2.new(math.rad(-x), math.rad(y))
	-- CameraRecoiler.recoil(recoil)
end
function BlasterController:shoot()
	-- Use cached weapon stats (optimized)
	self.viewModelController:playShootAnimation()
	self.characterAnimationController:playShootAnimation()
	self:recoil()
	self.ammo -= 1
	local now = Workspace:GetServerTimeNow()
	local origin = camera.CFrame
	local rayDirections = getRayDirections(origin, self.raysPerShot, math.rad(self.spread), now)
	for index, direction in rayDirections do
		rayDirections[index] = direction * self.range
	end
	local rayResults = castRays(player, origin.Position, rayDirections, self.rayRadius)
	-- Rather than passing the entire table of rayResults to the server, we'll pass the shot origin and a list of tagged humanoids.
	-- The server will then recalculate the ray directions from the origin and validate the tagged humanoids.
	-- Strings are used for the indices since non-contiguous arrays do not get passed over the network correctly.
	-- (This may be non-contiguous in the case of firing a shotgun, where not all of the rays hit a target)
	local tagged = {}
	local didTag = false
	for index, rayResult in rayResults do
		if rayResult.taggedHumanoid then
			tagged[tostring(index)] = rayResult.taggedHumanoid
			didTag = true
		end
	end
	if didTag then
		self.hitmarkerController:showHitmarker()
		-- Play hit marker sound immediately (no server wait)
		self.audioController:playHitMarkerSound()
	end
	shootRemote:FireServer(now, self.blaster, origin, tagged)
	local muzzlePosition = self.viewModelController:getMuzzlePosition()
	drawRayResults(muzzlePosition, rayResults)
	-- Camera shake on shoot
	CameraShaker:shakeOnShoot()
	-- fire haptic
	self.shootHaptic:Play()
end
function BlasterController:startShooting()
	-- If the player tries to shoot without any ammo, reload instead
	if self.ammo == 0 then
		self:reload()
		return
	end
	if not self:canShoot() then
		return
	end
	if self.shooting then
		return
	end
	local fireMode = self.blaster:GetAttribute(Constants.FIRE_MODE_ATTRIBUTE)
	local rateOfFire = self.blaster:GetAttribute(Constants.RATE_OF_FIRE_ATTRIBUTE)
	if fireMode == Constants.FIRE_MODE.SEMI then
		self.shooting = true
		self:shoot()
		task.delay(60 / rateOfFire, function()
			self.shooting = false
			if self.ammo == 0 then
				self:reload()
			end
		end)
	elseif fireMode == Constants.FIRE_MODE.AUTO then
		task.spawn(function()
			self.shooting = true
			while self.activated and self:canShoot() do
				self:shoot()
				task.wait(60 / rateOfFire)
			end
			self.shooting = false
			if self.ammo == 0 then
				self:reload()
			end
		end)
	end
end
function BlasterController:reload()
	if not self:canReload() then
		return
	end
	local reloadTime = self.blaster:GetAttribute(Constants.RELOAD_TIME_ATTRIBUTE)
	local magazineSize = self.blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
	self.viewModelController:playReloadAnimation(reloadTime)
	self.characterAnimationController:playReloadAnimation(reloadTime)
	self.reloading = true
	reloadRemote:FireServer(self.blaster)
	self.reloadTask = task.delay(reloadTime, function()
		self.ammo = magazineSize
		self.reloading = false
		self.reloadTask = nil
	end)
end
function BlasterController:activate()
	if self.activated then
		return
	end
	self.activated = true
	self:startShooting()
end
function BlasterController:deactivate()
	if not self.activated then
		return
	end
	self.activated = false
end
function BlasterController:equip()
	if self.equipped then
		return
	end
	self.equipped = true
	-- Resync ammo and reloading values
	self.ammo = self.blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
	self.reloading = self.blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE)
	
	-- Cache static weapon stats (optimization - eliminates ~40 lookups/sec during sustained fire)
	self.spread = self.blaster:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	self.raysPerShot = self.blaster:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	self.range = self.blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)
	self.rayRadius = self.blaster:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)
	self.recoilMin = self.blaster:GetAttribute(Constants.RECOIL_MIN_ATTRIBUTE)
	self.recoilMax = self.blaster:GetAttribute(Constants.RECOIL_MAX_ATTRIBUTE)
	
	-- Resync aim assist values
	self.range = self.blaster:GetAttribute(Constants.AIM_ASSIST_RANGE_ATTRIBUTE)
	self.fov = self.blaster:GetAttribute(Constants.AIM_ASSIST_FOV_ATTRIBUTE)
	self.friction = self.blaster:GetAttribute(Constants.AIM_ASSIST_FRICTION_STRENGTH_ATTRIBUTE)
	self.tracking = self.blaster:GetAttribute(Constants.AIM_ASSIST_TRACKING_STRENGTH_ATTRIBUTE)
	self.centering = self.blaster:GetAttribute(Constants.AIM_ASSIST_TRACKING_STRENGTH_ATTRIBUTE)
	-- Set up the Aim Assist Controller
	self.aimAssistController:setSubject(Workspace.CurrentCamera)
	self.aimAssistController:setRange(self.range)
	self.aimAssistController:setFieldOfView(self.fov)
	self.aimAssistController:addTargetTag(Constants.AIM_ASSIST_TARGET_TAG)
	self.aimAssistController:addPlayerTargets(true, true)
	self.aimAssistController:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, self.friction)
	self.aimAssistController:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, self.tracking)
	self.aimAssistController:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, self.centering)
	self.aimAssistController:setEasingFunc(
		AimAssistEnum.AimAssistEasingAttribute.Distance,
		function(distance: number): number
			if distance < Constants.AIM_ASSIST_MIN_RANGE then
				return 0
			else
				return 1
			end
		end
	)
	self.aimAssistController:setDebug(false)
	-- Enable Aim Assist
	self.aimAssistController:enable()
	-- Enable view model
	self.viewModelController:enable()
	-- Enable hitmarker/reticle
	self.hitmarkerController:enable()
	-- Enable touch input controller
	self.touchInputController:enable()
	-- Enable character animations
	self.characterAnimationController:enable()
	-- Keep track of the humanoid in the character currently equipping the blaster.
	-- We need this to make sure the player can't shoot while dead.
	self.humanoid = self.blaster.Parent:FindFirstChildOfClass("Humanoid")
end
function BlasterController:unequip()
	if not self.equipped then
		return
	end
	self.equipped = false
	-- Force deactivate the blaster when unequipping it
	self:deactivate()
	-- If the blaster is being reloaded, stop it
	if self.reloadTask then
		task.cancel(self.reloadTask)
		self.reloadTask = nil
	end
	-- Disable Aim Assist debug UI
	self.aimAssistController:setDebug(false)
	-- Disable Aim Assist
	self.aimAssistController:disable()
	-- Disable view model
	self.viewModelController:disable()
	-- Disable hitmarker/reticle
	self.hitmarkerController:disable()
	-- Disable touch input controller
	self.touchInputController:disable()
	-- Disable character animations
	self.characterAnimationController:disable()
end
function BlasterController:initialize()
	table.insert(
		self.connections,
		self.blaster.Equipped:Connect(function()
			self:equip()
		end)
	)
	table.insert(
		self.connections,
		self.blaster.Unequipped:Connect(function()
			self:unequip()
		end)
	)
	table.insert(
		self.connections,
		self.blaster.Activated:Connect(function()
			self:activate()
		end)
	)
	table.insert(
		self.connections,
		self.blaster.Deactivated:Connect(function()
			self:deactivate()
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputBegan:Connect(function(inputObject: InputObject, processed: boolean)
			if processed then
				return
			end
			if
				inputObject.KeyCode == Constants.KEYBOARD_RELOAD_KEY_CODE
				or inputObject.KeyCode == Constants.GAMEPAD_RELOAD_KEY_CODE
			then
				self:reload()
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.InputChanged:Connect(function(inputObject: InputObject, _)
			if
				inputObject.UserInputType == Enum.UserInputType.Gamepad1
				and (inputObject.KeyCode == Enum.KeyCode.Thumbstick1 or inputObject.KeyCode == Enum.KeyCode.Thumbstick2)
			then
				self.aimAssistController:updateGamepadEligibility(inputObject.KeyCode, inputObject.Position)
			end
		end)
	)
	table.insert(
		self.connections,
		UserInputService.TouchPan:Connect(function()
			self.aimAssistController:updateTouchEligibility()
		end)
	)
	self.touchInputController:setReloadCallback(function()
		self:reload()
	end)
	
	-- Listen for kills to trigger camera shake
	local killfeedRemote = remotes:FindFirstChild("Killfeed")
	if killfeedRemote then
		table.insert(
			self.connections,
			killfeedRemote.OnClientEvent:Connect(function(
				killerName,
				killerLevel,
				killerIsBot,
				victimName,
				victimLevel,
				victimIsBot
			)
				-- If local player got a kill, shake camera
				if killerName == player.Name and not killerIsBot then
					CameraShaker:shakeOnKill()
				end
			end)
		)
	end
end
function BlasterController:destroy()
	self:unequip()
	disconnectAndClear(self.connections)
	self.aimAssistController:destroy()
	self.viewModelController:destroy()
	self.touchInputController:destroy()
	self.characterAnimationController:destroy()
	self.hitmarkerController:destroy()
	self.audioController:destroy()
end
return BlasterController
