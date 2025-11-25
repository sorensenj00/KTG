local ReplicatedStorage = game:GetService("ReplicatedStorage")
local castRays = require(script.Parent.castRays)

local laserBeamEffect = require(ReplicatedStorage.Blaster.Effects.LaserSystem)

local impactEffect = require(ReplicatedStorage.Blaster.Effects.ImpactEffect)

local function drawRayResults(position: Vector3, rayResults: { castRays.RayResult })

	for _, rayResult in rayResults do

		laserBeamEffect(position, rayResult.position)

		if rayResult.instance then

			impactEffect(rayResult.position, rayResult.normal, rayResult.taggedHumanoid ~= nil)

		end

	end

end

return drawRayResults
