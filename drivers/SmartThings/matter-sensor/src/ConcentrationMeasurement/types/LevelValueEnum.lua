local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local LevelValueEnum = {}
-- Note: the name here is intentionally set to Uint8 to maintain backwards compatibility
-- with how types were handled in api < 10.
local new_mt = UintABC.new_mt({NAME = "Uint8", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNKNOWN] = "UNKNOWN",
    [self.LOW] = "LOW",
    [self.MEDIUM] = "MEDIUM",
    [self.HIGH] = "HIGH",
    [self.CRITICAL] = "CRITICAL",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNKNOWN  = 0x00
new_mt.__index.LOW  = 0x01
new_mt.__index.MEDIUM  = 0x02
new_mt.__index.HIGH  = 0x03
new_mt.__index.CRITICAL  = 0x04

LevelValueEnum.UNKNOWN  = 0x00
LevelValueEnum.LOW  = 0x01
LevelValueEnum.MEDIUM  = 0x02
LevelValueEnum.HIGH  = 0x03
LevelValueEnum.CRITICAL  = 0x04

LevelValueEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(LevelValueEnum, new_mt)

return LevelValueEnum

