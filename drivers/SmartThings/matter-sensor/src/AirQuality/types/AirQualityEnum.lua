local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AirQualityEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNKNOWN] = "UNKNOWN",
    [self.GOOD] = "GOOD",
    [self.FAIR] = "FAIR",
    [self.MODERATE] = "MODERATE",
    [self.POOR] = "POOR",
    [self.VERY_POOR] = "VERY_POOR",
    [self.EXTREMELY_POOR] = "EXTREMELY_POOR",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNKNOWN  = 0x00
new_mt.__index.GOOD  = 0x01
new_mt.__index.FAIR  = 0x02
new_mt.__index.MODERATE  = 0x03
new_mt.__index.POOR  = 0x04
new_mt.__index.VERY_POOR  = 0x05
new_mt.__index.EXTREMELY_POOR  = 0x06

AirQualityEnum.UNKNOWN  = 0x00
AirQualityEnum.GOOD  = 0x01
AirQualityEnum.FAIR  = 0x02
AirQualityEnum.MODERATE  = 0x03
AirQualityEnum.POOR  = 0x04
AirQualityEnum.VERY_POOR  = 0x05
AirQualityEnum.EXTREMELY_POOR  = 0x06

AirQualityEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(AirQualityEnum, new_mt)

return AirQualityEnum

