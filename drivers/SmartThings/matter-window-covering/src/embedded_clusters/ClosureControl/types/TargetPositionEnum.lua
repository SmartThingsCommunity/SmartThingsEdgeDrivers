local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local TargetPositionEnum = {}
local new_mt = UintABC.new_mt({NAME = "TargetPositionEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.MOVE_TO_FULLY_CLOSED] = "MOVE_TO_FULLY_CLOSED",
    [self.MOVE_TO_FULLY_OPEN] = "MOVE_TO_FULLY_OPEN",
    [self.MOVE_TO_PEDESTRIAN_POSITION] = "MOVE_TO_PEDESTRIAN_POSITION",
    [self.MOVE_TO_VENTILATION_POSITION] = "MOVE_TO_VENTILATION_POSITION",
    [self.MOVE_TO_SIGNATURE_POSITION] = "MOVE_TO_SIGNATURE_POSITION",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.MOVE_TO_FULLY_CLOSED  = 0x00
new_mt.__index.MOVE_TO_FULLY_OPEN  = 0x01
new_mt.__index.MOVE_TO_PEDESTRIAN_POSITION  = 0x02
new_mt.__index.MOVE_TO_VENTILATION_POSITION  = 0x03
new_mt.__index.MOVE_TO_SIGNATURE_POSITION  = 0x04

TargetPositionEnum.MOVE_TO_FULLY_CLOSED  = 0x00
TargetPositionEnum.MOVE_TO_FULLY_OPEN  = 0x01
TargetPositionEnum.MOVE_TO_PEDESTRIAN_POSITION  = 0x02
TargetPositionEnum.MOVE_TO_VENTILATION_POSITION  = 0x03
TargetPositionEnum.MOVE_TO_SIGNATURE_POSITION  = 0x04

TargetPositionEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(TargetPositionEnum, new_mt)

return TargetPositionEnum
