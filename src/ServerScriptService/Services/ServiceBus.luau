--[[
    Module: ServiceBus
    Description: Central event bus for decoupled service communication.
    
    Usage:
    local ServiceBus = require(ServerScriptService.Services.ServiceBus)
    
    -- Subscribe
    ServiceBus.Get("MyEvent").Event:Connect(function(arg) ... end)
    
    -- Fire
    ServiceBus.Get("MyEvent"):Fire(arg)
]]

local ServiceBus = {}
local Events = {}

function ServiceBus.Get(eventName: string): BindableEvent
	if not Events[eventName] then
		local event = Instance.new("BindableEvent")
		event.Name = eventName
		Events[eventName] = event
	end
	return Events[eventName]
end

return ServiceBus
