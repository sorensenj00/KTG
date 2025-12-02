--[[
    Config: SafeZoneConfig
    Description: Shared configuration for Safe Zones.
]]

local SafeZoneConfig = {}

SafeZoneConfig.SAFE_ZONE_SIZE = Vector3.new(120, 120, 120)
SafeZoneConfig.SAFE_ZONE_LOCATIONS = {
    Vector3.new(2998, 105, 280), -- Original
    Vector3.new(2208, 104, -611) -- Second Zone
}

SafeZoneConfig.MAX_LEVEL = 5 -- Players above this level are kicked out of safe zone logic

return SafeZoneConfig
