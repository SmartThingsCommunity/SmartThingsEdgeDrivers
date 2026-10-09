local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local StepDirectionEnum = {}
local new_mt = UintABC.new_mt({NAME = "StepDirectionEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.DECREASE] = "DECREASE",
    [self.INCREASE] = "INCREASE",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.DECREASE  = 0x00
new_mt.__index.INCREASE  = 0x01

StepDirectionEnum.DECREASE  = 0x00
StepDirectionEnum.INCREASE  = 0x01

StepDirectionEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(StepDirectionEnum, new_mt)

return StepDirectionEnum
