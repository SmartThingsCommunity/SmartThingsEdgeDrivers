local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ClosureErrorEnum = {}
local new_mt = UintABC.new_mt({NAME = "ClosureErrorEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.PHYSICALLY_BLOCKED] = "PHYSICALLY_BLOCKED",
    [self.BLOCKED_BY_SENSOR] = "BLOCKED_BY_SENSOR",
    [self.TEMPERATURE_LIMITED] = "TEMPERATURE_LIMITED",
    [self.MAINTENANCE_REQUIRED] = "MAINTENANCE_REQUIRED",
    [self.INTERNAL_INTERFERENCE] = "INTERNAL_INTERFERENCE",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.PHYSICALLY_BLOCKED  = 0x00
new_mt.__index.BLOCKED_BY_SENSOR  = 0x01
new_mt.__index.TEMPERATURE_LIMITED  = 0x02
new_mt.__index.MAINTENANCE_REQUIRED  = 0x03
new_mt.__index.INTERNAL_INTERFERENCE  = 0x04

ClosureErrorEnum.PHYSICALLY_BLOCKED  = 0x00
ClosureErrorEnum.BLOCKED_BY_SENSOR  = 0x01
ClosureErrorEnum.TEMPERATURE_LIMITED  = 0x02
ClosureErrorEnum.MAINTENANCE_REQUIRED  = 0x03
ClosureErrorEnum.INTERNAL_INTERFERENCE  = 0x04

ClosureErrorEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ClosureErrorEnum, new_mt)

return ClosureErrorEnum
