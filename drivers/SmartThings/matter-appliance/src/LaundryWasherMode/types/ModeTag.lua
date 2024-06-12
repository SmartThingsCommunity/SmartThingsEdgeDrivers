local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ModeTag = {}
local new_mt = UintABC.new_mt({NAME = "ModeTag", ID = data_types.name_to_id_map["Uint16"]}, 2)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NORMAL] = "NORMAL",
    [self.DELICATE] = "DELICATE",
    [self.HEAVY] = "HEAVY",
    [self.WHITES] = "WHITES",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NORMAL  = 0x4000
new_mt.__index.DELICATE  = 0x4001
new_mt.__index.HEAVY  = 0x4002
new_mt.__index.WHITES  = 0x4003

ModeTag.NORMAL  = 0x4000
ModeTag.DELICATE  = 0x4001
ModeTag.HEAVY  = 0x4002
ModeTag.WHITES  = 0x4003

ModeTag.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ModeTag, new_mt)

return ModeTag
