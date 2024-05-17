local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AirQualityEnum = {}
local new_mt = UintABC.new_mt({NAME = "AirQualityEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
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

local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.AirQuality.types.AirQualityEnum")
if has_aliases then
  aliases:add_to_class(AirQualityEnum)
end

return AirQualityEnum

