--[[
    Module: castRays
    Description: Performs spatial raycasting queries for weapon projectiles with bullet magnetism support.
    
    Dependencies:
    - CollectionService (Roblox Service)
    - Workspace (Roblox Service)
    - Constants (ReplicatedStorage.Blaster.Constants)
    - canPlayerDamageHumanoid (ServerScriptService.Utility.canPlayerDamageHumanoid)
    
    Public API:
    - castRays(attacker: Player | Model, position: Vector3, directions: {Vector3}, radius: number, additionalIgnore: {Instance}?): {RayResult}
        Casts multiple rays from a position in given directions with spherecast radius for bullet magnetism.
        Returns array of RayResult objects containing hit information and valid damage targets.
    
    Type Exports:
    - RayResult: { taggedHumanoid: Humanoid?, position: Vector3, normal: Vector3, instance: Instance? }
    
    Author: System
    Last Updated: 2025-01-20
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local canPlayerDamageHumanoid = require(ServerScriptService.Utility.canPlayerDamageHumanoid)

export type RayResult = {
	taggedHumanoid: Humanoid?,
	position: Vector3,
	normal: Vector3,
	instance: Instance?,
}

local function castRays(
	attacker: Player | Model,
	position: Vector3,
	directions: { Vector3 },
	radius: number,
	additionalIgnore: { Instance }?
): { RayResult }
	local exclude = CollectionService:GetTagged(Constants.RAY_EXCLUDE_TAG)

	-- Add additional ignore list if provided
	if additionalIgnore then
		table.move(additionalIgnore, 1, #additionalIgnore, #exclude + 1, exclude)
	end

	local isPlayer = attacker:IsA("Player")
	local isBot = attacker:IsA("Model")

	-- Always include the attacker's character in the exclude list
	if isPlayer then
		local player = attacker :: Player
		if player.Character then
			table.insert(exclude, player.Character)
		end
	elseif isBot then
		table.insert(exclude, attacker)
	end

	local collisionGroup = nil

	-- If the player is on a team, use that team's collision group
	if isPlayer then
		local player = attacker :: Player
		if player.Team and not player.Neutral then
			collisionGroup = player.Team.Name
		end
	end
	-- Bots don't typically have team collision groups yet, but could in future.

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.IgnoreWater = true
	params.FilterDescendantsInstances = exclude
	if collisionGroup then
		params.CollisionGroup = collisionGroup
	end

	local rayResults = {}

	for _, direction in directions do
		-- Spherecast for bullet magnetism
		local raycastResult = Workspace:Spherecast(position, radius, direction, params)
		local rayResult: RayResult = {
			position = position + direction,
			normal = direction.Unit,
		}

		if raycastResult then
			rayResult.position = raycastResult.Position
			rayResult.normal = raycastResult.Normal
			rayResult.instance = raycastResult.Instance

			local hitParent = raycastResult.Instance.Parent
			local humanoid = hitParent:FindFirstChildOfClass("Humanoid")

			-- If no humanoid found, check if we hit a Tool or Accessory (Grandparent check)
			if not humanoid and hitParent.Parent then
				humanoid = hitParent.Parent:FindFirstChildOfClass("Humanoid")
			end

			if humanoid and canPlayerDamageHumanoid(attacker, humanoid) then
				rayResult.taggedHumanoid = humanoid
			end
		end

		table.insert(rayResults, rayResult)
	end

	return rayResults
end

return castRays
