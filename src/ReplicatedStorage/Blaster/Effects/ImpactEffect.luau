--!nocheck
-- Impact "Crunch" Effects with debris, sparks, and light emission
-- Now with object pooling to prevent GC thrashing

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Blaster.Constants)
local PartPool = require(ReplicatedStorage.Utility.PartPool)

-- === OBJECT POOL SETUP ===

local function createImpactTemplate()
	local impactPart = Instance.new("Part")
	impactPart.Name = "ImpactEffect"
	impactPart.Size = Vector3.new(0.1, 0.1, 0.1)
	impactPart.Anchored = true
	impactPart.CanCollide = false
	impactPart.Transparency = 1

	local attachment = Instance.new("Attachment")
	attachment.Name = "MainAttachment"
	attachment.Position = Vector3.new(0, 0, 0)
	attachment.Parent = impactPart

	local sparkEmitter = Instance.new("ParticleEmitter")
	sparkEmitter.Name = "SparkEmitter"
	sparkEmitter.Lifetime = NumberRange.new(0.3, 0.6)
	sparkEmitter.Rate = 0  -- Controlled via :Emit()
	sparkEmitter.Parent = attachment

	local pointLight = Instance.new("PointLight")
	pointLight.Name = "ImpactLight"
	pointLight.Color = Color3.fromRGB(255, 200, 100)
	pointLight.Range = 5
	pointLight.Parent = impactPart

	return impactPart
end

-- Initialize pool
local impactPool = PartPool.new(createImpactTemplate(), 15)

local function createImpactEffect(position: Vector3, normal: Vector3, isHit: boolean)
	-- Get pooled instance
	local impactPart = impactPool:Get()
	
	-- Position and orient
	impactPart.CFrame = CFrame.lookAt(position, position + normal)
	impactPart.Parent = Workspace

	-- Get references
	local attachment = impactPart:FindFirstChild("MainAttachment")
	local sparkEmitter = attachment and attachment:FindFirstChild("SparkEmitter")
	local pointLight = impactPart:FindFirstChild("ImpactLight")

	-- Detect material type
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = { impactPart }

	local raycastResult = Workspace:Raycast(position - normal * 0.1, normal * 0.2, raycastParams)
	local material = Enum.Material.Plastic
	if raycastResult and raycastResult.Material then
		material = raycastResult.Material
	end

	-- Configure spark emitter based on material
	if sparkEmitter then
		if material == Enum.Material.Metal or material == Enum.Material.Neon then
			-- Metal/Neon: Bright sparks
			sparkEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparkEmitter.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 0)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0)),
			})
			sparkEmitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(0.5, 0.2),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkEmitter.Lifetime = NumberRange.new(0.3, 0.6)
			sparkEmitter.Speed = NumberRange.new(8, 15)
			sparkEmitter.SpreadAngle = Vector2.new(45, 45)
			sparkEmitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.5, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			sparkEmitter:Emit(8)
		else
			-- Grass/Dirt: Dust cloud
			sparkEmitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
			sparkEmitter.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 150, 150)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100)),
			})
			sparkEmitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.5, 1),
				NumberSequenceKeypoint.new(1, 1.5),
			})
			sparkEmitter.Lifetime = NumberRange.new(0.5, 1)
			sparkEmitter.Speed = NumberRange.new(3, 8)
			sparkEmitter.SpreadAngle = Vector2.new(30, 30)
			sparkEmitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.5, 0.7),
				NumberSequenceKeypoint.new(1, 1),
			})
			sparkEmitter:Emit(6)
		end
	end

	-- Reset and configure light
	if pointLight then
		pointLight.Brightness = Constants.IMPACT_LIGHT_BRIGHTNESS
		pointLight.Color = Color3.fromRGB(255, 200, 100)
		pointLight.Range = 5

		-- Fade out light quickly
		local lightTween = TweenService:Create(
			pointLight,
			TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Brightness = 0 }
		)
		lightTween:Play()
	end

	-- SCORCH DECAL: Burn mark (Not pooled - created on demand)
	if raycastResult and raycastResult.Instance then
		local hitPart = raycastResult.Instance
		if hitPart:IsA("BasePart") then
			local decal = Instance.new("Decal")
			decal.Name = "ScorchMark"
			decal.Texture = "rbxasset://textures/particles/smoke_main.dds"
			decal.Color3 = Color3.fromRGB(50, 50, 50)
			decal.Transparency = 0.3
			decal.Face = Enum.NormalId.Front

			-- Find the correct face
			local faces = {
				Enum.NormalId.Top,
				Enum.NormalId.Bottom,
				Enum.NormalId.Front,
				Enum.NormalId.Back,
				Enum.NormalId.Left,
				Enum.NormalId.Right,
			}

			local bestFace = Enum.NormalId.Front
			local bestDot = -math.huge
			for _, face in ipairs(faces) do
				local faceNormal = Vector3.FromNormalId(face)
				local worldNormal = hitPart.CFrame:VectorToWorldSpace(faceNormal)
				local dot = worldNormal:Dot(normal)
				if dot > bestDot then
					bestDot = dot
					bestFace = face
				end
			end

			decal.Face = bestFace
			decal.Parent = hitPart

			-- Fade out decal over time
			task.delay(5, function()
				if decal.Parent then
					local fadeTween = TweenService:Create(
						decal,
						TweenInfo.new(2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ Transparency = 1 }
					)
					fadeTween:Play()
					fadeTween.Completed:Connect(function()
						if decal.Parent then
							decal:Destroy()
						end
					end)
				end
			end)
		end
	end

	-- Return to pool after particles finish
	task.delay(1.5, function()
		impactPool:Return(impactPart)
	end)
end

return createImpactEffect
