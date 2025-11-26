local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- Map keys to indices
local KEY_MAP = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

local function getTools()
	local tools = {}
	
	-- Get tools from Backpack
	local backpack = player:FindFirstChild("Backpack")
	if backpack then
		for _, item in ipairs(backpack:GetChildren()) do
			if item:IsA("Tool") then
				table.insert(tools, item)
			end
		end
	end
	
	-- Get equipped tool
	local character = player.Character
	if character then
		local equipped = character:FindFirstChildOfClass("Tool")
		if equipped then
			table.insert(tools, equipped)
		end
	end
	
	-- Sort by name to ensure consistent order
	table.sort(tools, function(a, b)
		return a.Name < b.Name
	end)
	
	return tools
end

local function equipTool(index)
	local tools = getTools()
	local targetTool = tools[index]
	
	if not targetTool then return end
	
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- Check if already equipped
	if targetTool.Parent == character then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(targetTool)
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	
	local index = KEY_MAP[input.KeyCode]
	if index then
		equipTool(index)
	end
end)
