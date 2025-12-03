--[[
    Config: SafeZoneConfig
    Description: Shared configuration for Safe Zones.
]]

local SafeZoneConfig = {}

SafeZoneConfig.SAFE_ZONE_SIZE = Vector3.new(240, 240, 240)
SafeZoneConfig.SAFE_ZONE_LOCATIONS = {
	Vector3.new(2998, 105, 280), -- Original
	Vector3.new(2208, 104, -611), -- Second Zone
	Vector3.new(3304, 104, -552), -- Third Zone
}

SafeZoneConfig.MAX_LEVEL = 50 -- Players above this level are kicked out of safe zone logic (set high to allow all players)

return SafeZoneConfig
