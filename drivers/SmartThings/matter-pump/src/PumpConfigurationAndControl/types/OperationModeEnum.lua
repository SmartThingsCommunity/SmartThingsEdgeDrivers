local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local OperationModeEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NORMAL] = "NORMAL",
    [self.MINIMUM] = "MINIMUM",
    [self.MAXIMUM] = "MAXIMUM",
    [self.LOCAL] = "LOCAL",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NORMAL  = 0x00
new_mt.__index.MINIMUM  = 0x01
new_mt.__index.MAXIMUM  = 0x02
new_mt.__index.LOCAL  = 0x03

OperationModeEnum.NORMAL  = 0x00
OperationModeEnum.MINIMUM  = 0x01
OperationModeEnum.MAXIMUM  = 0x02
OperationModeEnum.LOCAL  = 0x03

OperationModeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(OperationModeEnum, new_mt)

return OperationModeEnum
