local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local TranslationDirectionEnum = {}
local new_mt = UintABC.new_mt({NAME = "TranslationDirectionEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.DOWNWARD] = "DOWNWARD",
    [self.UPWARD] = "UPWARD",
    [self.VERTICAL_MASK] = "VERTICAL_MASK",
    [self.VERTICAL_SYMMETRY] = "VERTICAL_SYMMETRY",
    [self.LEFTWARD] = "LEFTWARD",
    [self.RIGHTWARD] = "RIGHTWARD",
    [self.HORIZONTAL_MASK] = "HORIZONTAL_MASK",
    [self.HORIZONTAL_SYMMETRY] = "HORIZONTAL_SYMMETRY",
    [self.FORWARD] = "FORWARD",
    [self.BACKWARD] = "BACKWARD",
    [self.DEPTH_MASK] = "DEPTH_MASK",
    [self.DEPTH_SYMMETRY] = "DEPTH_SYMMETRY",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.DOWNWARD  = 0x00
new_mt.__index.UPWARD  = 0x01
new_mt.__index.VERTICAL_MASK  = 0x02
new_mt.__index.VERTICAL_SYMMETRY  = 0x03
new_mt.__index.LEFTWARD  = 0x04
new_mt.__index.RIGHTWARD  = 0x05
new_mt.__index.HORIZONTAL_MASK  = 0x06
new_mt.__index.HORIZONTAL_SYMMETRY  = 0x07
new_mt.__index.FORWARD  = 0x08
new_mt.__index.BACKWARD  = 0x09
new_mt.__index.DEPTH_MASK  = 0x0A
new_mt.__index.DEPTH_SYMMETRY  = 0x0B

TranslationDirectionEnum.DOWNWARD  = 0x00
TranslationDirectionEnum.UPWARD  = 0x01
TranslationDirectionEnum.VERTICAL_MASK  = 0x02
TranslationDirectionEnum.VERTICAL_SYMMETRY  = 0x03
TranslationDirectionEnum.LEFTWARD  = 0x04
TranslationDirectionEnum.RIGHTWARD  = 0x05
TranslationDirectionEnum.HORIZONTAL_MASK  = 0x06
TranslationDirectionEnum.HORIZONTAL_SYMMETRY  = 0x07
TranslationDirectionEnum.FORWARD  = 0x08
TranslationDirectionEnum.BACKWARD  = 0x09
TranslationDirectionEnum.DEPTH_MASK  = 0x0A
TranslationDirectionEnum.DEPTH_SYMMETRY  = 0x0B

TranslationDirectionEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(TranslationDirectionEnum, new_mt)

return TranslationDirectionEnum
