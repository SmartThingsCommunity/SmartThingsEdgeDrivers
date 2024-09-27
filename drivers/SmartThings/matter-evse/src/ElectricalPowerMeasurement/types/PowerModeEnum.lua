local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"


local PowerModeEnum = {}
local new_mt = UintABC.new_mt({NAME = "PowerModeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNKNOWN] = "UNKNOWN",
    [self.DC] = "DC",
    [self.AC] = "AC",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNKNOWN  = 0x00
new_mt.__index.DC  = 0x01
new_mt.__index.AC  = 0x02

PowerModeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(PowerModeEnum, new_mt)

return PowerModeEnum
