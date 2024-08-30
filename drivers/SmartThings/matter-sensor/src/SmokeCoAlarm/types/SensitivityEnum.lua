local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local SensitivityEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.HIGH] = "HIGH",
    [self.STANDARD] = "STANDARD",
    [self.LOW] = "LOW",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.HIGH  = 0x00
new_mt.__index.STANDARD  = 0x01
new_mt.__index.LOW  = 0x02

SensitivityEnum.HIGH  = 0x00
SensitivityEnum.STANDARD  = 0x01
SensitivityEnum.LOW  = 0x02

SensitivityEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(SensitivityEnum, new_mt)

return SensitivityEnum

