local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ModeTag = {}
local new_mt = UintABC.new_mt({NAME = "ModeTag", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.MANUAL] = "MANUAL",
    [self.TIME_OF_USE] = "TIME_OF_USE",
    [self.SOLAR_CHARGING] = "SOLAR_CHARGING",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.MANUAL  = 0x4000
new_mt.__index.TIME_OF_USE  = 0x4001
new_mt.__index.SOLAR_CHARGING  = 0x4002

ModeTag.MANUAL  = 0x4000
ModeTag.TIME_OF_USE  = 0x4001
ModeTag.SOLAR_CHARGING  = 0x4002

ModeTag.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ModeTag, new_mt)

return ModeTag
