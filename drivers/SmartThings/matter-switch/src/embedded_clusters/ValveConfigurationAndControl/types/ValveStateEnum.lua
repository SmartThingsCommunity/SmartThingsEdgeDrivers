local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"
local ValveStateEnum = {}
local new_mt = UintABC.new_mt({NAME = "ValveStateEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.CLOSED] = "CLOSED",
    [self.OPEN] = "OPEN",
    [self.TRANSITIONING] = "TRANSITIONING",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.CLOSED  = 0x00
new_mt.__index.OPEN  = 0x01
new_mt.__index.TRANSITIONING  = 0x02

ValveStateEnum.CLOSED  = 0x00
ValveStateEnum.OPEN  = 0x01
ValveStateEnum.TRANSITIONING  = 0x02

ValveStateEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ValveStateEnum, new_mt)

return ValveStateEnum
