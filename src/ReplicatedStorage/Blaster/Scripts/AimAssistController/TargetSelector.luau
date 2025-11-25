--!strict
local _ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local AimAssistEnum = require(script.Parent.AimAssistEnum)

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

export type TargetEntry = {
	instance: Instance,
	position: Vector3,
	points: { Vector3 },
	distance: number,
	angle: number,
}

export type SelectTargetResult = {
	instance: Instance,
	bestPosition: Vector3,
	positions: { Vector3 },
	weights: { number },
	distance: number,
	angle: number,
	normalizedDistance: number,
	normalizedAngle: number,
}

export type TargetSelector = {
	range: number,
	fieldOfView: number,
	sortingBehavior: any,
	ignoreLineOfSight: boolean,
	targetTags: { [string]: { string } },
	playerTargets: any,
	targetPoints: {},
	getAllTargetPoints: (self: TargetSelector) -> { TargetEntry },
	selectTarget: (self: TargetSelector, _subject: any) -> SelectTargetResult?,
}

local TargetSelector = {}
TargetSelector.__index = TargetSelector

function TargetSelector.new()
	local self = {
		range = 100 :: number,
		fieldOfView = 90 :: number,
		sortingBehavior = AimAssistEnum.AimAssistSortingBehavior.Distance,
		ignoreLineOfSight = false,
		targetTags = {} :: { [string]: { string } },
		playerTargets = {} :: {
			ignoreLocalPlayer: boolean?,
			ignoreTeammates: boolean?,
			bones: { string }?,
		},
		targetPoints = {},
	}

	setmetatable(self, TargetSelector)
	return self
end

function TargetSelector:setRange(range: number)
	self.range = range
end

function TargetSelector:setFieldOfView(fov: number)
	self.fieldOfView = fov
end

function TargetSelector:setSortingBehavior(behavior: AimAssistEnum.AimAssistSortingBehavior)
	self.sortingBehavior = behavior
end

function TargetSelector:setIgnoreLineOfSight(ignore: boolean)
	self.ignoreLineOfSight = ignore
end

function TargetSelector:addTargetTag(tag: string, _bones: { string }?)
	self.targetTags[tag] = _bones or {}
end

function TargetSelector:removeTargetTag(tag: string)
	self.targetTags[tag] = nil
end

function TargetSelector:addPlayerTargets(ignoreLocalPlayer: boolean?, ignoreTeammates: boolean?, bones: { string }?)
	self.playerTargets = {
		ignoreLocalPlayer = ignoreLocalPlayer,
		ignoreTeammates = ignoreTeammates,
		bones = bones or {},
	}
end

function TargetSelector:removePlayerTargets()
	self.playerTargets = {}
end

function TargetSelector.getAllTargetPoints(self: TargetSelector): { TargetEntry }
	local targets = {}

	-- Add tagged targets
	for tag, _bones in self.targetTags do
		local instances = CollectionService:GetTagged(tag)
		for _, instance in instances do
			local humanoid = instance:FindFirstChildOfClass("Humanoid")
			if humanoid then
				local rootPart = humanoid.RootPart
				if rootPart then
					local distance = (rootPart.Position - camera.CFrame.Position).Magnitude
					local direction = (rootPart.Position - camera.CFrame.Position).Unit
					local angle = math.deg(math.acos(camera.CFrame.LookVector:Dot(direction)))

					if distance <= self.range and angle <= self.fieldOfView / 2 then
						table.insert(targets, {
							instance = humanoid,
							position = rootPart.Position,
							points = { rootPart.Position },
							distance = distance,
							angle = angle,
						})
					end
				end
			end
		end
	end

	-- Add player targets
	if self.playerTargets and next(self.playerTargets) ~= nil then
		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer ~= player or not self.playerTargets.ignoreLocalPlayer then
				local character = otherPlayer.Character
				if character then
					local humanoid = character:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.Health > 0 then
						local rootPart = humanoid.RootPart
						if rootPart then
							local distance = (rootPart.Position - camera.CFrame.Position).Magnitude
							local direction = (rootPart.Position - camera.CFrame.Position).Unit
							local angle = math.deg(math.acos(camera.CFrame.LookVector:Dot(direction)))

							if distance <= self.range and angle <= self.fieldOfView / 2 then
								table.insert(targets, {
									instance = humanoid,
									position = rootPart.Position,
									points = { rootPart.Position },
									distance = distance,
									angle = angle,
								})
							end
						end
					end
				end
			end
		end
	end

	return targets
end

function TargetSelector.selectTarget(self: TargetSelector, _subject): SelectTargetResult?
	local targets = self:getAllTargetPoints()

	if #targets == 0 then
		return nil
	end

	-- Sort targets based on sorting behavior
	if self.sortingBehavior == AimAssistEnum.AimAssistSortingBehavior.Distance then
		table.sort(targets, function(a: TargetEntry, b: TargetEntry)
			return a.distance < b.distance
		end)
	elseif self.sortingBehavior == AimAssistEnum.AimAssistSortingBehavior.Angle then
		table.sort(targets, function(a: TargetEntry, b: TargetEntry)
			return a.angle < b.angle
		end)
	end

	local bestTarget = targets[1]
	local normalizedDistance = math.clamp(bestTarget.distance / self.range, 0, 1)
	local normalizedAngle = math.clamp(bestTarget.angle / (self.fieldOfView / 2), 0, 1)

	return {
		instance = bestTarget.instance,
		bestPosition = bestTarget.position,
		positions = bestTarget.points,
		weights = { 1 },
		distance = bestTarget.distance,
		angle = bestTarget.angle,
		normalizedDistance = normalizedDistance,
		normalizedAngle = normalizedAngle,
	}
end

return TargetSelector
