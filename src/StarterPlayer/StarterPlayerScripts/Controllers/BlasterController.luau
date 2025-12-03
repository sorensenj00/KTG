--[[
	BlasterController: Weapon input, viewmodels, client-side raycasting, shot replication
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Blaster = ReplicatedStorage.Blaster
local Constants = require(Blaster.Constants)
local AimAssistController = require(Blaster.Scripts.AimAssistController)
local AimAssistEnum = require(Blaster.Scripts.AimAssistController.AimAssistEnum)
local TouchInputController = require(Blaster.Scripts.TouchInputController)
local ViewModelController = require(Blaster.Scripts.ViewModelController)
local CharacterAnimationController = require(Blaster.Scripts.CharacterAnimationController)
local HitmarkerController = require(Blaster.Scripts.HitmarkerController)
local AudioController = require(Blaster.Audio.AudioController)
local disconnectAndClear = require(ReplicatedStorage.Utility.disconnectAndClear)
local getRayDirections = require(Blaster.Utility.getRayDirections)
local drawRayResults = require(Blaster.Utility.drawRayResults)
local castRays = require(Blaster.Utility.castRays)
local playSoundFromSource = require(Blaster.Utility.playSoundFromSource)

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local Remotes = Blaster:WaitForChild("Remotes")
local ShootRemote = Remotes:WaitForChild("Shoot")
local ReloadRemote = Remotes:WaitForChild("Reload")
local Random = Random.new()

-- Lazy load to avoid circular dependency
local CameraController
local function getCamera()
	if not CameraController then
		CameraController = require(script.Parent.CameraController)
	end
	return CameraController
end

local BlasterController = {}
BlasterController.__index = BlasterController

--== Constructor ==--

function BlasterController.new(blaster: Tool)
	local self = setmetatable({
		blaster = blaster,
		aimAssist = AimAssistController.new(),
		viewModel = ViewModelController.new(blaster),
		hitmarker = HitmarkerController.new(),
		touchInput = TouchInputController.new(blaster),
		charAnim = CharacterAnimationController.new(blaster),
		audio = AudioController.new(),
		activated = false,
		equipped = false,
		shooting = false,
		ammo = blaster:GetAttribute(Constants.AMMO_ATTRIBUTE),
		reloading = blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE),
		reloadTask = nil,
		humanoid = nil,
		connections = {},
		shootHaptic = blaster:WaitForChild("Haptics"):WaitForChild("ShootHaptic"),
	}, BlasterController)

	self:_bindEvents()
	return self
end

--== State Checks ==--

function BlasterController:_isAlive()
	return self.humanoid and self.humanoid.Health > 0
end

function BlasterController:_canShoot()
	return self:_isAlive() and self.equipped and self.ammo > 0 and not self.reloading
end

function BlasterController:_canReload()
	local magSize = self.blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)
	return self:_isAlive() and self.equipped and self.ammo < magSize and not self.reloading
end

--== Actions ==--

function BlasterController:_applyRecoil()
	local min = self.blaster:GetAttribute(Constants.RECOIL_MIN_ATTRIBUTE)
	local max = self.blaster:GetAttribute(Constants.RECOIL_MAX_ATTRIBUTE)
	local x = min.X + Random:NextNumber() * (max.X - min.X)
	local y = min.Y + Random:NextNumber() * (max.Y - min.Y)
	getCamera().Recoil(Vector2.new(math.rad(-x), math.rad(y)))
end

function BlasterController:_shoot()
	local spread = self.blaster:GetAttribute(Constants.SPREAD_ATTRIBUTE)
	local raysPerShot = self.blaster:GetAttribute(Constants.RAYS_PER_SHOT_ATTRIBUTE)
	local range = self.blaster:GetAttribute(Constants.RANGE_ATTRIBUTE)
	local rayRadius = self.blaster:GetAttribute(Constants.RAY_RADIUS_ATTRIBUTE)

	-- Animations & effects
	self.viewModel:playShootAnimation()
	self.charAnim:playShootAnimation()
	self:_applyRecoil()

	-- Decrement ammo
	self.ammo -= 1

	-- Cast rays
	local now = Workspace:GetServerTimeNow()
	local origin = Camera.CFrame
	local directions = getRayDirections(origin, raysPerShot, math.rad(spread), now)

	for i, dir in directions do
		directions[i] = dir * range
	end

	local results = castRays(Player, origin.Position, directions, rayRadius)

	-- Check for hits
	local didHit = false
	for _, result in results do
		if result.taggedHumanoid then
			didHit = true
			break
		end
	end

	if didHit then
		self.hitmarker:showHitmarker()
		self.audio:playHitMarkerSound()
	end

	-- Send to server
	ShootRemote:FireServer(now, self.blaster, origin)

	-- Draw local laser immediately
	drawRayResults(self.viewModel:getMuzzlePosition(), results)

	-- Camera shake & haptics
	getCamera().ShakeOnShoot()
	self.shootHaptic:Play()
end

function BlasterController:_startShooting()
	if self.ammo == 0 then
		self:_reload()
		return
	end

	if not self:_canShoot() or self.shooting then
		return
	end

	local fireMode = self.blaster:GetAttribute(Constants.FIRE_MODE_ATTRIBUTE)
	local rateOfFire = self.blaster:GetAttribute(Constants.RATE_OF_FIRE_ATTRIBUTE)
	local fireDelay = 60 / rateOfFire

	if fireMode == Constants.FIRE_MODE.SEMI then
		self.shooting = true
		self:_shoot()
		task.delay(fireDelay, function()
			self.shooting = false
			if self.ammo == 0 then
				self:_reload()
			end
		end)
	elseif fireMode == Constants.FIRE_MODE.AUTO then
		task.spawn(function()
			self.shooting = true
			while self.activated and self:_canShoot() do
				self:_shoot()
				task.wait(fireDelay)
			end
			self.shooting = false
			if self.ammo == 0 then
				self:_reload()
			end
		end)
	end
end

function BlasterController:_reload()
	if not self:_canReload() then
		return
	end

	local reloadTime = self.blaster:GetAttribute(Constants.RELOAD_TIME_ATTRIBUTE)
	local magSize = self.blaster:GetAttribute(Constants.MAGAZINE_SIZE_ATTRIBUTE)

	self.viewModel:playReloadAnimation(reloadTime)
	self.charAnim:playReloadAnimation(reloadTime)
	self.reloading = true

	ReloadRemote:FireServer(self.blaster)

	self.reloadTask = task.delay(reloadTime, function()
		self.ammo = magSize
		self.reloading = false
		self.reloadTask = nil
	end)
end

--== Input Handlers ==--

function BlasterController:_activate()
	if self.activated then
		return
	end
	self.activated = true
	self:_startShooting()
end

function BlasterController:_deactivate()
	if not self.activated then
		return
	end
	self.activated = false
end

--== Equip/Unequip ==--

function BlasterController:_equip()
	if self.equipped then
		return
	end
	self.equipped = true

	-- Sync state
	self.ammo = self.blaster:GetAttribute(Constants.AMMO_ATTRIBUTE)
	self.reloading = self.blaster:GetAttribute(Constants.RELOADING_ATTRIBUTE)
	self.humanoid = self.blaster.Parent:FindFirstChildOfClass("Humanoid")

	-- Setup aim assist
	local aa = self.aimAssist
	aa:setSubject(Camera)
	aa:setRange(self.blaster:GetAttribute(Constants.AIM_ASSIST_RANGE_ATTRIBUTE))
	aa:setFieldOfView(self.blaster:GetAttribute(Constants.AIM_ASSIST_FOV_ATTRIBUTE))
	aa:addTargetTag(Constants.AIM_ASSIST_TARGET_TAG)
	aa:addPlayerTargets(true, true)

	local friction = self.blaster:GetAttribute(Constants.AIM_ASSIST_FRICTION_STRENGTH_ATTRIBUTE)
	local tracking = self.blaster:GetAttribute(Constants.AIM_ASSIST_TRACKING_STRENGTH_ATTRIBUTE)
	aa:setMethodStrength(AimAssistEnum.AimAssistMethod.Friction, friction)
	aa:setMethodStrength(AimAssistEnum.AimAssistMethod.Tracking, tracking)
	aa:setMethodStrength(AimAssistEnum.AimAssistMethod.Centering, tracking)

	aa:setEasingFunc(AimAssistEnum.AimAssistEasingAttribute.Distance, function(dist)
		return dist < Constants.AIM_ASSIST_MIN_RANGE and 0 or 1
	end)

	aa:setDebug(false)
	aa:enable()

	-- Enable controllers
	self.viewModel:enable()
	self.hitmarker:enable()
	self.touchInput:enable()
	self.charAnim:enable()
end

function BlasterController:_unequip()
	if not self.equipped then
		return
	end
	self.equipped = false

	self:_deactivate()

	if self.reloadTask then
		task.cancel(self.reloadTask)
		self.reloadTask = nil
	end

	-- Disable controllers
	self.aimAssist:setDebug(false)
	self.aimAssist:disable()
	self.viewModel:disable()
	self.hitmarker:disable()
	self.touchInput:disable()
	self.charAnim:disable()
end

--== Event Binding ==--

function BlasterController:_bindEvents()
	local conns = self.connections

	conns[#conns + 1] = self.blaster.Equipped:Connect(function()
		self:_equip()
	end)

	conns[#conns + 1] = self.blaster.Unequipped:Connect(function()
		self:_unequip()
	end)

	conns[#conns + 1] = self.blaster.Activated:Connect(function()
		self:_activate()
	end)

	conns[#conns + 1] = self.blaster.Deactivated:Connect(function()
		self:_deactivate()
	end)

	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if
			input.KeyCode == Constants.KEYBOARD_RELOAD_KEY_CODE
			or input.KeyCode == Constants.GAMEPAD_RELOAD_KEY_CODE
		then
			self:_reload()
		end
	end)

	conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			if input.KeyCode == Enum.KeyCode.Thumbstick1 or input.KeyCode == Enum.KeyCode.Thumbstick2 then
				self.aimAssist:updateGamepadEligibility(input.KeyCode, input.Position)
			end
		end
	end)

	conns[#conns + 1] = UserInputService.TouchPan:Connect(function()
		self.aimAssist:updateTouchEligibility()
	end)

	self.touchInput:setReloadCallback(function()
		self:_reload()
	end)

	-- Kill camera shake
	local killfeed = Remotes:FindFirstChild("Killfeed")
	if killfeed then
		conns[#conns + 1] = killfeed.OnClientEvent:Connect(function(killerName, _, killerIsBot)
			if killerName == Player.Name and not killerIsBot then
				getCamera().ShakeOnKill()
			end
		end)
	end
end

--== Cleanup ==--

function BlasterController:destroy()
	self:_unequip()
	disconnectAndClear(self.connections)
	self.aimAssist:destroy()
	self.viewModel:destroy()
	self.touchInput:destroy()
	self.charAnim:destroy()
	self.hitmarker:destroy()
	self.audio:destroy()
end

--== Shot Replication (for other players) ==--

local blasterCache = {}

local function processShot(blaster, _origin, results)
	if not blaster or not blaster:IsDescendantOf(game) then
		blasterCache[blaster] = nil
		return
	end

	-- Skip local player (already drew instant laser)
	if blaster.Parent == Player.Character then
		return
	end

	-- Get or create cache
	local cache = blasterCache[blaster]
	if not cache then
		local handle = blaster:FindFirstChild("Handle")
		if not handle then
			return
		end

		cache = {
			Handle = handle,
			AudioEmitter = handle:FindFirstChild("AudioEmitter"),
			Muzzle = blaster:FindFirstChild("MuzzleAttachment", true),
			Sounds = blaster:FindFirstChild("Sounds"),
		}
		blasterCache[blaster] = cache

		blaster.Destroying:Once(function()
			blasterCache[blaster] = nil
		end)
	end

	-- Get muzzle position
	local muzzle = cache.Muzzle
	local pos = muzzle and muzzle.WorldPosition or blaster:GetPivot().Position

	if muzzle then
		local flash = muzzle:FindFirstChild("FlashEmitter")
		if flash then
			flash:Emit(1)
		end
	end

	-- Play shoot sound
	local shootSound = cache.Sounds and cache.Sounds:FindFirstChild("Shoot")
	if shootSound and cache.AudioEmitter then
		if shootSound:IsA("Folder") then
			local sounds = shootSound:GetChildren()
			if #sounds > 0 then
				local sound = sounds[math.random(#sounds)]
				if sound:IsA("Sound") then
					playSoundFromSource(sound, cache.AudioEmitter)
				end
			end
		elseif shootSound:IsA("Sound") then
			playSoundFromSource(shootSound, cache.AudioEmitter)
		end
	end

	drawRayResults(pos, results)
end

local function onReplicateShot(packet)
	if type(packet) ~= "table" or #packet == 0 then
		return
	end

	for _, shot in packet do
		if shot.tool then
			processShot(shot.tool, shot.origin, shot.results)
		end
	end
end

--== Module Start ==--

function BlasterController.Start()
	Remotes:WaitForChild("ReplicateShot").OnClientEvent:Connect(onReplicateShot)
	print("✅ BlasterController initialized")
end

return BlasterController
