local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ModeTag = {}
local new_mt = UintABC.new_mt({NAME = "ModeTag", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NO_OPTIMIZATION] = "NO_OPTIMIZATION",
    [self.DEVICE_OPTIMIZATION] = "DEVICE_OPTIMIZATION",
    [self.LOCAL_OPTIMIZATION] = "LOCAL_OPTIMIZATION",
    [self.GRID_OPTIMIZATION] = "GRID_OPTIMIZATION",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NO_OPTIMIZATION  = 0x4000
new_mt.__index.DEVICE_OPTIMIZATION  = 0x4001
new_mt.__index.LOCAL_OPTIMIZATION  = 0x4002
new_mt.__index.GRID_OPTIMIZATION  = 0x4003

ModeTag.NO_OPTIMIZATION  = 0x4000
ModeTag.DEVICE_OPTIMIZATION  = 0x4001
ModeTag.LOCAL_OPTIMIZATION  = 0x4002
ModeTag.GRID_OPTIMIZATION  = 0x4003

ModeTag.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ModeTag, new_mt)

return ModeTag
