local ServerScriptService = game:GetService("ServerScriptService")

local validateInstance = require(ServerScriptService.Utility.TypeValidation.validateInstance)
local validateNumber = require(ServerScriptService.Utility.TypeValidation.validateNumber)
local validateCFrame = require(ServerScriptService.Utility.TypeValidation.validateCFrame)

local function validateShootArguments(
	timestamp,
	blaster,
	origin
)
	if not validateNumber(timestamp) then
		return false
	end
	if not validateInstance(blaster, "Tool") then
		return false
	end
	if not validateCFrame(origin) then
		return false
	end

	return true
end

return validateShootArguments
