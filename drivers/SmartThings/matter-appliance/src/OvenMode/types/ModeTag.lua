local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local ModeTag = {}
local new_mt = UintABC.new_mt({NAME = "ModeTag", ID = data_types.name_to_id_map["Uint16"]}, 2)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.BAKE] = "BAKE",
    [self.CONVECTION] = "CONVECTION",
    [self.GRILL] = "GRILL",
    [self.ROAST] = "ROAST",
    [self.CLEAN] = "CLEAN",
    [self.CONVECTION_BAKE] = "CONVECTION_BAKE",
    [self.CONVECTION_ROAST] = "CONVECTION_ROAST",
    [self.WARMING] = "WARMING",
    [self.PROOFING] = "PROOFING",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.BAKE  = 0x4000
new_mt.__index.CONVECTION  = 0x4001
new_mt.__index.GRILL  = 0x4002
new_mt.__index.ROAST  = 0x4003
new_mt.__index.CLEAN  = 0x4004
new_mt.__index.CONVECTION_BAKE  = 0x4005
new_mt.__index.CONVECTION_ROAST  = 0x4006
new_mt.__index.WARMING  = 0x4007
new_mt.__index.PROOFING  = 0x4008

ModeTag.BAKE  = 0x4000
ModeTag.CONVECTION  = 0x4001
ModeTag.GRILL  = 0x4002
ModeTag.ROAST  = 0x4003
ModeTag.CLEAN  = 0x4004
ModeTag.CONVECTION_BAKE  = 0x4005
ModeTag.CONVECTION_ROAST  = 0x4006
ModeTag.WARMING  = 0x4007
ModeTag.PROOFING  = 0x4008

ModeTag.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(ModeTag, new_mt)

return ModeTag
