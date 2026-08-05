local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local CurrentPositionEnum = {}
local new_mt = UintABC.new_mt({NAME = "CurrentPositionEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.FULLY_CLOSED] = "FULLY_CLOSED",
    [self.FULLY_OPENED] = "FULLY_OPENED",
    [self.PARTIALLY_OPENED] = "PARTIALLY_OPENED",
    [self.OPENED_FOR_PEDESTRIAN] = "OPENED_FOR_PEDESTRIAN",
    [self.OPENED_FOR_VENTILATION] = "OPENED_FOR_VENTILATION",
    [self.OPENED_AT_SIGNATURE] = "OPENED_AT_SIGNATURE",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.FULLY_CLOSED  = 0x00
new_mt.__index.FULLY_OPENED  = 0x01
new_mt.__index.PARTIALLY_OPENED  = 0x02
new_mt.__index.OPENED_FOR_PEDESTRIAN  = 0x03
new_mt.__index.OPENED_FOR_VENTILATION  = 0x04
new_mt.__index.OPENED_AT_SIGNATURE  = 0x05

CurrentPositionEnum.FULLY_CLOSED  = 0x00
CurrentPositionEnum.FULLY_OPENED  = 0x01
CurrentPositionEnum.PARTIALLY_OPENED  = 0x02
CurrentPositionEnum.OPENED_FOR_PEDESTRIAN  = 0x03
CurrentPositionEnum.OPENED_FOR_VENTILATION  = 0x04
CurrentPositionEnum.OPENED_AT_SIGNATURE  = 0x05

CurrentPositionEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(CurrentPositionEnum, new_mt)

return CurrentPositionEnum
