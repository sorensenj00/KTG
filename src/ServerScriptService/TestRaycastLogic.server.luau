-- ServerScriptService/TestRaycastLogic.server.luau
local Workspace = game:GetService("Workspace")

local function testRaycast()
	print("--- Starting Spherecast Logic Test ---")

	-- 1. Test Safezone (CanCollide = false) -> Should NOT block
	local safezone = Instance.new("Part")
	safezone.Name = "TestSafezone"
	safezone.Size = Vector3.new(10, 10, 1)
	safezone.Position = Vector3.new(0, 5, 0)
	safezone.Transparency = 0.5
	safezone.CanCollide = false
	safezone.Anchored = true
	safezone.Parent = Workspace

	local startPos = Vector3.new(0, 5, -10)
	local direction = Vector3.new(0, 0, 20)
	local botRadius = 2

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}
	rayParams.RespectCanCollide = true -- KEY CHANGE

	local blocked = Workspace:Spherecast(startPos, botRadius, direction, rayParams)

	print("Test 1: Safezone (CanCollide=false)")
	if blocked then
		print("FAILED: Blocked by " .. blocked.Instance.Name)
	else
		print("PASSED: Path Clear (Ignored Safezone)")
	end
	safezone:Destroy()

	-- 2. Test Narrow Gap (CanCollide = true) -> Raycast passes, Spherecast should BLOCK
	local leftWall = Instance.new("Part")
	leftWall.Size = Vector3.new(5, 10, 1)
	leftWall.Position = Vector3.new(-3, 5, 0) -- Gap of 2 studs at center (from -0.5 to 0.5 is clear?)
	-- Wait, if left wall is at -3, width 5, it goes from -5.5 to -0.5.
	-- Right wall at +3, width 5, goes from 0.5 to 5.5.
	-- Gap is 1 stud (-0.5 to 0.5).
	-- Bot radius is 2 (Diameter 4). Should BLOCK.
	leftWall.Anchored = true
	leftWall.Parent = Workspace

	local rightWall = Instance.new("Part")
	rightWall.Size = Vector3.new(5, 10, 1)
	rightWall.Position = Vector3.new(3, 5, 0)
	rightWall.Anchored = true
	rightWall.Parent = Workspace

	local blocked2 = Workspace:Spherecast(startPos, botRadius, direction, rayParams)
	
	print("Test 2: Narrow Gap (1 stud gap, 4 stud bot)")
	if blocked2 then
		print("PASSED: Blocked by " .. blocked2.Instance.Name)
	else
		print("FAILED: Path Clear (Bot would get stuck!)")
	end

	leftWall:Destroy()
	rightWall:Destroy()
	
	print("--- Test Complete ---")
end

task.delay(2, testRaycast)
