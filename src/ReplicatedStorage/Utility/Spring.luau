--!nocheck
-- Dampening Spring Physics Module
-- Provides natural overshoot and settle behavior for smooth animations

local Spring = {}
Spring.__index = Spring

-- Create a new spring with damping and stiffness
-- damping: How quickly the spring settles (higher = faster settle, less overshoot)
-- stiffness: How strong the spring is (higher = faster response)
function Spring.new(damping: number, stiffness: number)
	local self = setmetatable({}, Spring)
	
	self.damping = damping or 12
	self.stiffness = stiffness or 100
	self.position = 0
	self.velocity = 0
	self.target = 0
	
	return self
end

-- Update spring physics
function Spring:update(deltaTime: number)
	-- Spring-damper equation: F = -kx - cv
	-- Where k is stiffness, c is damping, x is displacement, v is velocity
	local displacement = self.position - self.target
	local force = -self.stiffness * displacement - self.damping * self.velocity
	
	-- Apply force to velocity (F = ma, assuming m = 1)
	self.velocity = self.velocity + force * deltaTime
	
	-- Update position
	self.position = self.position + self.velocity * deltaTime
end

-- Apply an impulse (sudden force) to the spring
function Spring:impulse(force: number)
	self.velocity = self.velocity + force
end

-- Set target position (spring will smoothly move towards this)
function Spring:setTarget(target: number)
	self.target = target
end

-- Get current position
function Spring:getPosition(): number
	return self.position
end

-- Get current velocity
function Spring:getVelocity(): number
	return self.velocity
end

-- Reset spring to a specific position
function Spring:reset(position: number)
	self.position = position or 0
	self.velocity = 0
	self.target = position or 0
end

return Spring

