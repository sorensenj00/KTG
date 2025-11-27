--[[
    Module: CrosshairSignals
    Description: Provides BindableEvents for decoupling Weapon logic from Crosshair UI.
]]

local CrosshairSignals = {}

-- Create events
CrosshairSignals.Shoot = Instance.new("BindableEvent")
CrosshairSignals.Hit = Instance.new("BindableEvent")

return CrosshairSignals
