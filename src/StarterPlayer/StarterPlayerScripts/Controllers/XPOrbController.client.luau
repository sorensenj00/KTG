--[[
    Controller: XPOrbController
    Description: Client-side vacuum/magnet controller for XP Orbs.
                 Handles detection, physics override, and Bezier curve animation.

    Author: System
    Last Updated: 2025-01-28
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local XPOrbController = {}

-- Constants
local MAGNET_RADIUS = 25
local VACUUM_SPEED_MIN = 20
local VACUUM_SPEED_MAX = 80
local POP_HEIGHT = 8 -- How high it pops up
local POP_OUT_FORCE = 5 -- How far it pushes away initially

-- State
local player = Players.LocalPlayer
local collectingOrbs = {} -- [orb] = true

-- Remotes
local remotesFolder = ReplicatedStorage:WaitForChild("GameLoop"):WaitForChild("Remotes")
local collectOrbRemote = remotesFolder:WaitForChild("CollectOrb")

-- Helper: Quadratic Bezier
local function bezier(t, p0, p1, p2)
	return (1 - t)^2 * p0 + 2 * (1 - t) * t * p1 + t^2 * p2
end

-- Vacuum Animation
local function startVacuum(orb)
	if collectingOrbs[orb] then return end
	collectingOrbs[orb] = true

	-- Disable physics locally
	orb.Anchored = true
	orb.CanCollide = false

	-- Determine path
	local startPos = orb.Position
	local startTime = tick()

	-- Random "Pop Out" Control Point
	-- Direction from player to orb (away)
	local toOrb = (startPos - player.Character.HumanoidRootPart.Position).Unit
	local right = toOrb:Cross(Vector3.new(0, 1, 0))
	local offset = (toOrb * POP_OUT_FORCE) + (right * math.random(-3, 3)) + Vector3.new(0, POP_HEIGHT, 0)
	local controlPoint = startPos + offset

	-- Animation Loop
	local connection
	connection = RunService.RenderStepped:Connect(function()
		if not orb.Parent or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then
			connection:Disconnect()
			collectingOrbs[orb] = nil
			return
		end

		local targetPos = player.Character.HumanoidRootPart.Position
		local distTotal = (startPos - targetPos).Magnitude

		-- Dynamic Speed: Starts slow, gets fast
		-- Determine progress based on distance covered or time?
		-- We use time but mapped exponentially
		local elapsed = tick() - startTime
		local duration = math.clamp(distTotal / 40, 0.4, 1.2) -- Faster for close orbs
		local t = math.clamp(elapsed / duration, 0, 1)

		-- Easing: Exponential In (t^3)
		local easedT = t^3

		local nextPos = bezier(easedT, startPos, controlPoint, targetPos)
		orb.Position = nextPos

		-- Shrink effect
		if t > 0.8 then
			local scale = (1 - t) * 5 -- 1 -> 0
			-- orb.Size = orb.Size * 0.9 -- Dangerous if setting repeatedly? No, we need original size.
			-- Just set transparency
			orb.Transparency = t
		end

		if t >= 1 then
			connection:Disconnect()
			-- Fire Server
			collectOrbRemote:FireServer(orb)
			-- Hide locally (Server will destroy)
			orb.Transparency = 1
			orb.Position = Vector3.new(0, -1000, 0)
			collectingOrbs[orb] = nil
		end
	end)
end

function XPOrbController.Start()
	print("--- Starting XPOrbController (Magnet) ---")

	RunService.Heartbeat:Connect(function()
		if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
		local hrp = player.Character.HumanoidRootPart

		-- Scan for orbs
		-- Using CollectionService is faster than looping Workspace folders
		local orbs = CollectionService:GetTagged("XPOrb")

		for _, orb in ipairs(orbs) do
			if orb and orb.Parent and not collectingOrbs[orb] then
				local dist = (orb.Position - hrp.Position).Magnitude
				if dist < MAGNET_RADIUS then
					startVacuum(orb)
				end
			end
		end
	end)
end

return XPOrbController
