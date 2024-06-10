local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local NumberOfRinsesEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NONE] = "NONE",
    [self.NORMAL] = "NORMAL",
    [self.EXTRA] = "EXTRA",
    [self.MAX] = "MAX",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NONE  = 0x00
new_mt.__index.NORMAL  = 0x01
new_mt.__index.EXTRA  = 0x02
new_mt.__index.MAX  = 0x03

NumberOfRinsesEnum.NONE  = 0x00
NumberOfRinsesEnum.NORMAL  = 0x01
NumberOfRinsesEnum.EXTRA  = 0x02
NumberOfRinsesEnum.MAX  = 0x03

NumberOfRinsesEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(NumberOfRinsesEnum, new_mt)

return NumberOfRinsesEnum
