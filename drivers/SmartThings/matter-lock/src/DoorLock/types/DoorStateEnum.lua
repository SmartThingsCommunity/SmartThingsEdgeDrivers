local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DoorStateEnum = {}
local new_mt = UintABC.new_mt({NAME = "DoorStateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.DOOR_OPEN] = "DOOR_OPEN",
    [self.DOOR_CLOSED] = "DOOR_CLOSED",
    [self.DOOR_JAMMED] = "DOOR_JAMMED",
    [self.DOOR_FORCED_OPEN] = "DOOR_FORCED_OPEN",
    [self.DOOR_UNSPECIFIED_ERROR] = "DOOR_UNSPECIFIED_ERROR",
    [self.DOOR_AJAR] = "DOOR_AJAR",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.DOOR_OPEN  = 0x00
new_mt.__index.DOOR_CLOSED  = 0x01
new_mt.__index.DOOR_JAMMED  = 0x02
new_mt.__index.DOOR_FORCED_OPEN  = 0x03
new_mt.__index.DOOR_UNSPECIFIED_ERROR  = 0x04
new_mt.__index.DOOR_AJAR  = 0x05

DoorStateEnum.DOOR_OPEN  = 0x00
DoorStateEnum.DOOR_CLOSED  = 0x01
DoorStateEnum.DOOR_JAMMED  = 0x02
DoorStateEnum.DOOR_FORCED_OPEN  = 0x03
DoorStateEnum.DOOR_UNSPECIFIED_ERROR  = 0x04
DoorStateEnum.DOOR_AJAR  = 0x05

DoorStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DoorStateEnum, new_mt)

return DoorStateEnum