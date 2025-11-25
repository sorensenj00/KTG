--!nocheck
-- Impact "Crunch" Effects with debris, sparks, and light emission

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Constants = require(ReplicatedStorage.Blaster.Constants)

local function createImpactEffect(position: Vector3, normal: Vector3, isHit: boolean)
	-- Create impact container
	local impactPart = Instance.new("Part")
	impactPart.Name = "ImpactEffect"
	impactPart.Size = Vector3.new(0.1, 0.1, 0.1)
	impactPart.Anchored = true
	impactPart.CanCollide = false
	impactPart.Transparency = 1
	impactPart.CFrame = CFrame.lookAt(position, position + normal)
	impactPart.Parent = Workspace

	-- Create attachment for particles
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 0, 0)
	attachment.Parent = impactPart

	-- Detect material type
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = { impactPart }

	local raycastResult = Workspace:Raycast(position - normal * 0.1, normal * 0.2, raycastParams)
	local material = Enum.Material.Plastic
	if raycastResult and raycastResult.Material then
		material = raycastResult.Material
	end

	-- PARTICLE BURST: Spark particles
	local sparkEmitter = Instance.new("ParticleEmitter")
	sparkEmitter.Name = "SparkEmitter"
	sparkEmitter.Parent = attachment

	if material == Enum.Material.Metal or material == Enum.Material.Neon then
		-- Metal/Neon: Bright sparks
		sparkEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkEmitter.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 200)), -- Yellow-white
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 200, 0)), -- Orange
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0)), -- Red-orange
		})
		sparkEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.5, 0.2),
			NumberSequenceKeypoint.new(1, 0),
		})
		sparkEmitter.Lifetime = NumberRange.new(0.3, 0.6)
		sparkEmitter.Rate = 0
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
			ColorSequenceKeypoint.new(0, Color3.fromRGB(150, 150, 150)), -- Gray
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 100)), -- Dark gray
		})
		sparkEmitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 1.5),
		})
		sparkEmitter.Lifetime = NumberRange.new(0.5, 1)
		sparkEmitter.Rate = 0
		sparkEmitter.Speed = NumberRange.new(3, 8)
		sparkEmitter.SpreadAngle = Vector2.new(30, 30)
		sparkEmitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.5),
			NumberSequenceKeypoint.new(0.5, 0.7),
			NumberSequenceKeypoint.new(1, 1),
		})
		sparkEmitter:Emit(6)
	end

	-- LIGHT EMISSION: Temporary PointLight
	local pointLight = Instance.new("PointLight")
	pointLight.Brightness = Constants.IMPACT_LIGHT_BRIGHTNESS
	pointLight.Color = Color3.fromRGB(255, 200, 100)
	pointLight.Range = 5
	pointLight.Parent = impactPart

	-- Fade out light quickly
	local lightTween = TweenService:Create(
		pointLight,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Brightness = 0 }
	)
	lightTween:Play()

	-- SCORCH DECAL: Burn mark
	if raycastResult and raycastResult.Instance then
		local hitPart = raycastResult.Instance
		if hitPart:IsA("BasePart") then
			local decal = Instance.new("Decal")
			decal.Name = "ScorchMark"
			decal.Texture = "rbxasset://textures/particles/smoke_main.dds" -- Using smoke as scorch texture
			decal.Color3 = Color3.fromRGB(50, 50, 50) -- Dark scorch
			decal.Transparency = 0.3
			decal.Face = Enum.NormalId.Front
			-- TextureSize removed because Decals do not support it - they stretch to fit the face

			-- Orient decal to hit surface
			local surfaceCFrame = CFrame.lookAt(position, position + normal)
			local decalCFrame = surfaceCFrame * CFrame.new(0, 0, -0.01) -- Slightly offset from surface

			-- Find the correct face
			local faces = {
				Enum.NormalId.Top,
				Enum.NormalId.Bottom,
				Enum.NormalId.Front,
				Enum.NormalId.Back,
				Enum.NormalId.Left,
				Enum.NormalId.Right,
			}

			-- Use the face closest to the normal
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

			-- Fade out decal over time (optional - can keep permanent)
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

	-- Clean up after particles finish
	task.delay(1.5, function()
		if sparkEmitter.Parent then
			sparkEmitter.Enabled = false
		end
		Debris:AddItem(impactPart, 0.5)
	end)
end

return createImpactEffect
