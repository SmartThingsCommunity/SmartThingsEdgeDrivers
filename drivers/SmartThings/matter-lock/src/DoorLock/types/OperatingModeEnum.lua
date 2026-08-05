local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local OperatingModeEnum = {}
local new_mt = UintABC.new_mt({NAME = "OperatingModeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.NORMAL] = "NORMAL",
    [self.VACATION] = "VACATION",
    [self.PRIVACY] = "PRIVACY",
    [self.NO_REMOTE_LOCK_UNLOCK] = "NO_REMOTE_LOCK_UNLOCK",
    [self.PASSAGE] = "PASSAGE",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.NORMAL  = 0x00
new_mt.__index.VACATION  = 0x01
new_mt.__index.PRIVACY  = 0x02
new_mt.__index.NO_REMOTE_LOCK_UNLOCK  = 0x03
new_mt.__index.PASSAGE  = 0x04

OperatingModeEnum.NORMAL  = 0x00
OperatingModeEnum.VACATION  = 0x01
OperatingModeEnum.PRIVACY  = 0x02
OperatingModeEnum.NO_REMOTE_LOCK_UNLOCK  = 0x03
OperatingModeEnum.PASSAGE  = 0x04

OperatingModeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(OperatingModeEnum, new_mt)

return OperatingModeEnum