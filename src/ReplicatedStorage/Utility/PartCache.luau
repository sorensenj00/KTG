--!nocheck
-- Object Pooling System for Beams and Impact Effects
-- Pre-creates parts to avoid instantiation lag

local Workspace = game:GetService("Workspace")

local PartCache = {}
PartCache.__index = PartCache

-- Pool sizes
local BEAM_POOL_SIZE = 50
local IMPACT_POOL_SIZE = 50

-- Hidden storage location (under map)
local function getStorageLocation()
	return Vector3.new(0, -1000, 0)
end

function PartCache.new()
	local self = setmetatable({}, PartCache)
	
	-- Beam pool
	self.beamPool = {}
	self.activeBeams = {}
	
	-- Impact pool
	self.impactPool = {}
	self.activeImpacts = {}
	
	-- Initialize pools
	self:initializePools()
	
	return self
end

-- Initialize object pools
function PartCache:initializePools()
	local storagePos = getStorageLocation()
	
	-- Create beam pool
	for i = 1, BEAM_POOL_SIZE do
		local container = Instance.new("Part")
		container.Name = "PooledBeam"
		container.Size = Vector3.new(0.1, 0.1, 0.1)
		container.Anchored = true
		container.CanCollide = false
		container.Transparency = 1
		container.CFrame = CFrame.new(storagePos)
		container.Parent = Workspace
		
		-- Create attachments
		local startAttachment = Instance.new("Attachment")
		startAttachment.Position = Vector3.new(0, 0, 0)
		startAttachment.Parent = container
		
		local endAttachment = Instance.new("Attachment")
		endAttachment.Position = Vector3.new(0, 0, -10)
		endAttachment.Parent = container
		
		-- Create inner beam
		local innerBeam = Instance.new("Beam")
		innerBeam.Name = "InnerBeam"
		innerBeam.Attachment0 = startAttachment
		innerBeam.Attachment1 = endAttachment
		innerBeam.Enabled = false
		innerBeam.Parent = container
		
		-- Create outer beam
		local outerBeam = Instance.new("Beam")
		outerBeam.Name = "OuterBeam"
		outerBeam.Attachment0 = startAttachment
		outerBeam.Attachment1 = endAttachment
		outerBeam.Enabled = false
		outerBeam.Parent = container
		
		-- Create orbs
		local startOrb = Instance.new("Part")
		startOrb.Name = "StartOrb"
		startOrb.Size = Vector3.new(0.2, 0.2, 0.2)
		startOrb.Shape = Enum.PartType.Ball
		startOrb.Material = Enum.Material.Neon
		startOrb.Anchored = true
		startOrb.CanCollide = false
		startOrb.Transparency = 1
		startOrb.CFrame = CFrame.new(storagePos)
		startOrb.Parent = container
		
		local endOrb = Instance.new("Part")
		endOrb.Name = "EndOrb"
		endOrb.Size = Vector3.new(0.15, 0.15, 0.15)
		endOrb.Shape = Enum.PartType.Ball
		endOrb.Material = Enum.Material.Neon
		endOrb.Anchored = true
		endOrb.CanCollide = false
		endOrb.Transparency = 1
		endOrb.CFrame = CFrame.new(storagePos)
		endOrb.Parent = container
		
		table.insert(self.beamPool, container)
	end
	
	-- Create impact pool
	for i = 1, IMPACT_POOL_SIZE do
		local container = Instance.new("Part")
		container.Name = "PooledImpact"
		container.Size = Vector3.new(0.1, 0.1, 0.1)
		container.Anchored = true
		container.CanCollide = false
		container.Transparency = 1
		container.CFrame = CFrame.new(storagePos)
		container.Parent = Workspace
		
		-- Create attachment
		local attachment = Instance.new("Attachment")
		attachment.Position = Vector3.new(0, 0, 0)
		attachment.Parent = container
		
		-- Create particle emitter
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "ImpactEmitter"
		emitter.Enabled = false
		emitter.Parent = attachment
		
		table.insert(self.impactPool, container)
	end
end

-- Get a beam from pool
function PartCache:getBeam()
	local beam = table.remove(self.beamPool, 1)
	
	if not beam then
		-- Pool exhausted, create new one (shouldn't happen with proper sizing)
		warn("PartCache: Beam pool exhausted!")
		return nil
	end
	
	table.insert(self.activeBeams, beam)
	return beam
end

-- Return beam to pool
function PartCache:returnBeam(beam)
	if not beam then
		return
	end
	
	-- Disable all effects
	for _, child in ipairs(beam:GetDescendants()) do
		if child:IsA("Beam") then
			child.Enabled = false
		elseif child:IsA("Part") and child.Name:match("Orb") then
			child.Transparency = 1
			child.Size = Vector3.new(0.2, 0.2, 0.2)
		end
	end
	
	-- Move to storage
	beam.CFrame = CFrame.new(getStorageLocation())
	
	-- Remove from active
	local index = table.find(self.activeBeams, beam)
	if index then
		table.remove(self.activeBeams, index)
	end
	
	-- Return to pool
	table.insert(self.beamPool, beam)
end

-- Get an impact from pool
function PartCache:getImpact()
	local impact = table.remove(self.impactPool, 1)
	
	if not impact then
		-- Pool exhausted
		warn("PartCache: Impact pool exhausted!")
		return nil
	end
	
	table.insert(self.activeImpacts, impact)
	return impact
end

-- Return impact to pool
function PartCache:returnImpact(impact)
	if not impact then
		return
	end
	
	-- Disable emitter
	local emitter = impact:FindFirstChild("ImpactEmitter", true)
	if emitter then
		emitter.Enabled = false
	end
	
	-- Move to storage
	impact.CFrame = CFrame.new(getStorageLocation())
	
	-- Remove from active
	local index = table.find(self.activeImpacts, impact)
	if index then
		table.remove(self.activeImpacts, index)
	end
	
	-- Return to pool
	table.insert(self.impactPool, impact)
end

-- Clean up all pools
function PartCache:destroy()
	-- Clean up beams
	for _, beam in ipairs(self.beamPool) do
		beam:Destroy()
	end
	for _, beam in ipairs(self.activeBeams) do
		beam:Destroy()
	end
	
	-- Clean up impacts
	for _, impact in ipairs(self.impactPool) do
		impact:Destroy()
	end
	for _, impact in ipairs(self.activeImpacts) do
		impact:Destroy()
	end
	
	table.clear(self.beamPool)
	table.clear(self.activeBeams)
	table.clear(self.impactPool)
	table.clear(self.activeImpacts)
end

return PartCache

