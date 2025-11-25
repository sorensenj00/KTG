--[[
    Controller: BlasterController
    Description: Manages weapon input, viewmodels, client-side raycasting, and shot replication.
    Handles mouse input, plays local sounds/animations, applies camera recoil, and fires server events.
    Also listens for ReplicateShot to draw beams for other players' shots.
    
    Dependencies:
    - Players (Roblox Service)
    - ReplicatedStorage (Roblox Service)
    - UserInputService (Roblox Service)
    - Workspace (Roblox Service)
    - ReplicatedStorage.Blaster.Constants
    - ReplicatedStorage.Blaster.Scripts.AimAssistController
    - ReplicatedStorage.Blaster.Scripts.TouchInputController
    - ReplicatedStorage.Blaster.Scripts.ViewModelController
    - ReplicatedStorage.Blaster.Scripts.CharacterAnimationController
    - ReplicatedStorage.Blaster.Scripts.HitmarkerController
    - ReplicatedStorage.Blaster.Audio.AudioController
    - ReplicatedStorage.Blaster.Utility.getRayDirections
    - ReplicatedStorage.Blaster.Utility.drawRayResults
    - ReplicatedStorage.Blaster.Utility.castRays
    - ReplicatedStorage.Blaster.Utility.playSoundFromSource
    - ReplicatedStorage.Utility.disconnectAndClear
    - Controllers.CameraController
    - ReplicatedStorage.Blaster.Remotes.Shoot (RemoteEvent)
    - ReplicatedStorage.Blaster.Remotes.Reload (RemoteEvent)
    - ReplicatedStorage.Blaster.Remotes.ReplicateShot (RemoteEvent)
    - ReplicatedStorage.Blaster.Remotes.Killfeed (RemoteEvent)
    
    Public API:
    - Start(): void - Initialize the controller and set up ReplicateShot listener
    - new(blaster: Tool): BlasterController - Create a new BlasterController instance for a tool
    
    Author: System
    Last Updated: 2025-01-20
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local AimAssistController = require(ReplicatedStorage.Blaster.Scripts.AimAssistController)
local AimAssistEnum = require(ReplicatedStorage.Blaster.Scripts.AimAssistController.AimAssistEnum)
local TouchInputController = require(ReplicatedStorage.Blaster.Scripts.TouchInputController)
local ViewModelController = require(ReplicatedStorage.Blaster.Scripts.ViewModelController)
local CharacterAnimationController = require(ReplicatedStorage.Blaster.Scripts.CharacterAnimationController)
local HitmarkerController = require(ReplicatedStorage.Blaster.Scripts.HitmarkerController)
local AudioController = require(ReplicatedStorage.Blaster.Audio.AudioController)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local getRayDirections = require(ReplicatedStorage.Blaster.Utility.getRayDirections)
local drawRayResults = require(ReplicatedStorage.Blaster.Utility.drawRayResults)
local castRays = require(ReplicatedStorage.Blaster.Utility.castRays)
local playSoundFromSource = require(ReplicatedStorage.Blaster.Utility.playSoundFromSource)

-- Lazy load CameraController to avoid circular dependency
local CameraController = nil
local function getCameraController()
	if not CameraController then
		CameraController = require(script.Parent.CameraController)
	end
	return CameraController
end

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local remotes = ReplicatedStorage.Blaster:WaitForChild("Remotes")
local shootRemote = remotes:WaitForChild("Shoot")
local reloadRemote = remotes:WaitForChild("Reload")
local random = Random.new()

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
	local recoilMin = self.blaster:GetAttribute(Constants.RECOIL_MIN_ATTRIBUTE)
	local recoilMax = self.blaster:GetAttribute(Constants.RECOIL_MAX_ATTRIBUTE)
	local xDif = recoilMax.X - recoilMin.X
	local yDif = recoilMax.Y - recoilMin.Y
	local x = recoilMin.X + random:NextNumber() * xDif
	local y = recoilMin.Y + random:NextNumber() * yDif
	local recoil = Vector2.new(math.rad(-x), math.rad(y))
	getCameraController().Recoil(recoil)
end

function BlasterController:shoot()
	local spread = self.blaster:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = self.blaster:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = self.blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local rayRadius = self.blaster:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)
	self.viewModelController:playShootAnimation()
	self.characterAnimationController:playShootAnimation()
	self:recoil()
	self.ammo -= 1
	local now = Workspace:GetServerTimeNow()
	local origin = camera.CFrame
	local rayDirections = getRayDirections(origin, raysPerShot, math.rad(spread), now)
	for index, direction in rayDirections do
		rayDirections[index] = direction * range
	end
	local rayResults = castRays(player, origin.Position, rayDirections, rayRadius)
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

	-- INSTANT FEEDBACK: Draw Local Laser
	drawRayResults(muzzlePosition, rayResults)

	getCameraController().ShakeOnShoot()
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
			killfeedRemote.OnClientEvent:Connect(
				function(killerName, _killerLevel, killerIsBot, _victimName, _victimLevel, _victimIsBot)
					-- If local player got a kill, shake camera
					if killerName == player.Name and not killerIsBot then
						getCameraController().ShakeOnKill()
					end
				end
			)
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

-- === CLIENT REPLICATION ===
-- Draws lasers for OTHER players
local function onReplicateShotEvent(blaster: Tool, position: Vector3, rayResults: { any })
	if not blaster or not blaster:IsDescendantOf(game) then
		return
	end

	-- SKIPS LOCAL PLAYER (Already drew instant laser in shoot())
	local char = blaster.Parent
	if char == player.Character then
		return
	end

	local handle = blaster:FindFirstChild("Handle")
	local sounds = blaster:FindFirstChild("Sounds")
	if not handle or not sounds then
		return
	end

	local emitter = handle:FindFirstChild("AudioEmitter")
	local muzzle = blaster:FindFirstChild("MuzzleAttachment", true)

	if muzzle then
		position = muzzle.WorldPosition
		muzzle.FlashEmitter:Emit(1)
	else
		position = blaster:GetPivot().Position
	end

	-- Play SFX for others
	local shootSound = sounds:FindFirstChild("Shoot")
	if shootSound then
		if shootSound:IsA("Folder") then
			local soundList = shootSound:GetChildren()
			if #soundList > 0 then
				local randomSound = soundList[math.random(1, #soundList)]
				if randomSound:IsA("Sound") then
					playSoundFromSource(randomSound, emitter)
				end
			end
		elseif shootSound:IsA("Sound") then
			playSoundFromSource(shootSound, emitter)
		end
	end

	drawRayResults(position, rayResults)
end

function BlasterController.Start()
	-- Set up ReplicateShot listener
	local replicateShotRemote = remotes:WaitForChild("ReplicateShot")
	replicateShotRemote.OnClientEvent:Connect(onReplicateShotEvent)

	-- Set up tool initialization (tools will create BlasterController instances when equipped)
	-- This is handled by the tool's Equipped event, which calls BlasterController.new()

	print("✅ BlasterController: Initialized and listening for ReplicateShot events")
end

return BlasterController
