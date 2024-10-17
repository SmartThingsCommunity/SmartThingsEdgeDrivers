local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DoorLockUserType = {}
local new_mt = UintABC.new_mt({NAME = "DoorLockUserType", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNRESTRICTED] = "UNRESTRICTED",
    [self.YEAR_DAY_SCHEDULE_USER] = "YEAR_DAY_SCHEDULE_USER",
    [self.WEEK_DAY_SCHEDULE_USER] = "WEEK_DAY_SCHEDULE_USER",
    [self.MASTER_USER] = "MASTER_USER",
    [self.NON_ACCESS_USER] = "NON_ACCESS_USER",
    [self.NOT_SUPPORTED] = "NOT_SUPPORTED",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNRESTRICTED  = 0x00
new_mt.__index.YEAR_DAY_SCHEDULE_USER  = 0x01
new_mt.__index.WEEK_DAY_SCHEDULE_USER  = 0x02
new_mt.__index.MASTER_USER  = 0x03
new_mt.__index.NON_ACCESS_USER  = 0x04
new_mt.__index.NOT_SUPPORTED  = 0xFF

DoorLockUserType.UNRESTRICTED  = 0x00
DoorLockUserType.YEAR_DAY_SCHEDULE_USER  = 0x01
DoorLockUserType.WEEK_DAY_SCHEDULE_USER  = 0x02
DoorLockUserType.MASTER_USER  = 0x03
DoorLockUserType.NON_ACCESS_USER  = 0x04
DoorLockUserType.NOT_SUPPORTED  = 0xFF

DoorLockUserType.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DoorLockUserType, new_mt)

return DoorLockUserType