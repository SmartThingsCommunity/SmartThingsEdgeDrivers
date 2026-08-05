local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlLockState = {}
local new_mt = UintABC.new_mt({NAME = "DlLockState", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NOT_FULLY_LOCKED] = "NOT_FULLY_LOCKED",
    [self.LOCKED] = "LOCKED",
    [self.UNLOCKED] = "UNLOCKED",
    [self.UNLATCHED] = "UNLATCHED",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NOT_FULLY_LOCKED  = 0x00
new_mt.__index.LOCKED  = 0x01
new_mt.__index.UNLOCKED  = 0x02
new_mt.__index.UNLATCHED  = 0x03

DlLockState.NOT_FULLY_LOCKED  = 0x00
DlLockState.LOCKED  = 0x01
DlLockState.UNLOCKED  = 0x02
DlLockState.UNLATCHED  = 0x03

DlLockState.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlLockState, new_mt)

return DlLockState