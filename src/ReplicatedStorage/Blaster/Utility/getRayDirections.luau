--[[
    Module: getRayDirections
    Description: Generates random ray directions within a cone spread pattern for weapon projectiles.
    
    Dependencies: None
    
    Public API:
    - getRayDirections(origin: CFrame, numberOfRays: number, spreadAngle: number, seed: number): {Vector3}
        Generates an array of normalized direction vectors within a cone defined by the origin CFrame's look direction.
        Uses random roll and pitch angles within the spread cone for realistic bullet spread.
        Seed is multiplied by 100,000 to ensure unique randomness per timestamp.
    
    Algorithm:
    - For each ray, generates random roll (0 to 2π) and pitch (0 to spreadAngle)
    - Applies rotations to origin CFrame to get final direction vector
    - Returns array of normalized direction vectors
    
    Author: System
    Last Updated: 2025-01-20
]]

local function getRayDirections(origin: CFrame, numberOfRays: number, spreadAngle: number, seed: number): { Vector3 }

	-- Random seeds are ints. Since we'll generally be passing in a timestamp as the seed,

	-- we need to multiply it to make sure it isn't the same for an entire second.

	local random = Random.new(seed * 100_000)



	local rays = {}



	for _ = 1, numberOfRays do

		local roll = random:NextNumber() * math.pi * 2

		local pitch = random:NextNumber() * spreadAngle



		local rayCFrame = origin * CFrame.Angles(0, 0, roll) * CFrame.Angles(pitch, 0, 0)

		table.insert(rays, rayCFrame.LookVector)

	end



	return rays

end



return getRayDirections