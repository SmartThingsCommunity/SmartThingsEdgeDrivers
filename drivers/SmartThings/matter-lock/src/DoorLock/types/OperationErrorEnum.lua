local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local OperationErrorEnum = {}
local new_mt = UintABC.new_mt({NAME = "OperationErrorEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNSPECIFIED] = "UNSPECIFIED",
    [self.INVALID_CREDENTIAL] = "INVALID_CREDENTIAL",
    [self.DISABLED_USER_DENIED] = "DISABLED_USER_DENIED",
    [self.RESTRICTED] = "RESTRICTED",
    [self.INSUFFICIENT_BATTERY] = "INSUFFICIENT_BATTERY",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNSPECIFIED  = 0x00
new_mt.__index.INVALID_CREDENTIAL  = 0x01
new_mt.__index.DISABLED_USER_DENIED  = 0x02
new_mt.__index.RESTRICTED  = 0x03
new_mt.__index.INSUFFICIENT_BATTERY  = 0x04

OperationErrorEnum.UNSPECIFIED  = 0x00
OperationErrorEnum.INVALID_CREDENTIAL  = 0x01
OperationErrorEnum.DISABLED_USER_DENIED  = 0x02
OperationErrorEnum.RESTRICTED  = 0x03
OperationErrorEnum.INSUFFICIENT_BATTERY  = 0x04

OperationErrorEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(OperationErrorEnum, new_mt)

return OperationErrorEnum