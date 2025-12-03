--[[
	Utility: bindToInstanceDestroyed
	Description: Binds a callback to run when an instance is destroyed.
]]

local function bindToInstanceDestroyed(instance: Instance, callback: () -> ())
	local connection
	connection = instance.Destroying:Connect(function()
		if connection then
			connection:Disconnect()
		end
		callback()
	end)
	return connection
end

return bindToInstanceDestroyed
