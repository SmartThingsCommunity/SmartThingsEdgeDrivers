local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local StatusCode = {}
local new_mt = UintABC.new_mt({NAME = "StatusCode", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.CLEANING_IN_PROGRESS] = "CLEANING_IN_PROGRESS",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.CLEANING_IN_PROGRESS  = 0x40

StatusCode.CLEANING_IN_PROGRESS  = 0x40

StatusCode.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(StatusCode, new_mt)

return StatusCode

