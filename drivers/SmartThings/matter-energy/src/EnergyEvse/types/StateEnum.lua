local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local StateEnum = {}
local new_mt = UintABC.new_mt({NAME = "StateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NOT_PLUGGED_IN] = "NOT_PLUGGED_IN",
    [self.PLUGGED_IN_NO_DEMAND] = "PLUGGED_IN_NO_DEMAND",
    [self.PLUGGED_IN_DEMAND] = "PLUGGED_IN_DEMAND",
    [self.PLUGGED_IN_CHARGING] = "PLUGGED_IN_CHARGING",
    [self.PLUGGED_IN_DISCHARGING] = "PLUGGED_IN_DISCHARGING",
    [self.SESSION_ENDING] = "SESSION_ENDING",
    [self.FAULT] = "FAULT",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NOT_PLUGGED_IN  = 0x00
new_mt.__index.PLUGGED_IN_NO_DEMAND  = 0x01
new_mt.__index.PLUGGED_IN_DEMAND  = 0x02
new_mt.__index.PLUGGED_IN_CHARGING  = 0x03
new_mt.__index.PLUGGED_IN_DISCHARGING  = 0x04
new_mt.__index.SESSION_ENDING  = 0x05
new_mt.__index.FAULT  = 0x06

StateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(StateEnum, new_mt)

return StateEnum
