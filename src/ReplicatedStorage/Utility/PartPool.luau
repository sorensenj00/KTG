--[[
    Module: PartPool
    Description: Generic object pooling system for Parts with attachments and children.
    Prevents GC thrashing by reusing instances instead of creating/destroying them.
    
    API:
    - PartPool.new(template: Instance, initialSize: number?) -> PartPool
    - pool:Get() -> Instance
    - pool:Return(instance: Instance)
    
    Author: System
    Last Updated: 2025-12-02
]]

local PartPool = {}
PartPool.__index = PartPool

--[[
    Creates a new object pool for a given template.
    @param template - The instance to clone for pooled objects
    @param initialSize - Number of instances to pre-create (default: 10)
]]
function PartPool.new(template: Instance, initialSize: number?)
	local self = setmetatable({}, PartPool)
	
	self._template = template
	self._available = {}
	self._inUse = {}
	
	-- Pre-populate pool
	local size = initialSize or 10
	for i = 1, size do
		local instance = template:Clone()
		instance.Parent = nil
		table.insert(self._available, instance)
	end
	
	return self
end

--[[
    Gets an instance from the pool (creates new one if pool is empty)
]]
function PartPool:Get(): Instance
	local instance
	
	if #self._available > 0 then
		-- Reuse existing
		instance = table.remove(self._available)
	else
		-- Pool exhausted, create new
		instance = self._template:Clone()
	end
	
	self._inUse[instance] = true
	return instance
end

--[[
    Returns an instance to the pool for reuse
]]
function PartPool:Return(instance: Instance)
	if not self._inUse[instance] then
		warn("PartPool: Attempted to return instance not from this pool")
		return
	end
	
	-- Clean up the instance for reuse
	instance.Parent = nil
	
	-- Reset common properties
	if instance:IsA("BasePart") then
		instance.CFrame = CFrame.new(0, 0, 0)
		instance.AssemblyLinearVelocity = Vector3.zero
		instance.AssemblyAngularVelocity = Vector3.zero
	end
	
	-- Reset all descendants (Beams, ParticleEmitters, Lights, etc.)
	for _, child in ipairs(instance:GetDescendants()) do
		if child:IsA("Beam") then
			child.Enabled = true
			child.Transparency = NumberSequence.new(0)
		elseif child:IsA("ParticleEmitter") then
			child.Enabled = false
		elseif child:IsA("Light") then
			child.Enabled = true
		end
	end
	
	self._inUse[instance] = nil
	table.insert(self._available, instance)
end

--[[
    Gets pool statistics for debugging
]]
function PartPool:GetStats(): {Available: number, InUse: number, Total: number}
	local inUseCount = 0
	for _ in pairs(self._inUse) do
		inUseCount += 1
	end
	
	return {
		Available = #self._available,
		InUse = inUseCount,
		Total = #self._available + inUseCount
	}
end

return PartPool
