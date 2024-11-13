local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local UserTypeEnum = {}
local new_mt = UintABC.new_mt({NAME = "UserTypeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNRESTRICTED_USER] = "UNRESTRICTED_USER",
    [self.YEAR_DAY_SCHEDULE_USER] = "YEAR_DAY_SCHEDULE_USER",
    [self.WEEK_DAY_SCHEDULE_USER] = "WEEK_DAY_SCHEDULE_USER",
    [self.PROGRAMMING_USER] = "PROGRAMMING_USER",
    [self.NON_ACCESS_USER] = "NON_ACCESS_USER",
    [self.FORCED_USER] = "FORCED_USER",
    [self.DISPOSABLE_USER] = "DISPOSABLE_USER",
    [self.EXPIRING_USER] = "EXPIRING_USER",
    [self.SCHEDULE_RESTRICTED_USER] = "SCHEDULE_RESTRICTED_USER",
    [self.REMOTE_ONLY_USER] = "REMOTE_ONLY_USER",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNRESTRICTED_USER  = 0x00
new_mt.__index.YEAR_DAY_SCHEDULE_USER  = 0x01
new_mt.__index.WEEK_DAY_SCHEDULE_USER  = 0x02
new_mt.__index.PROGRAMMING_USER  = 0x03
new_mt.__index.NON_ACCESS_USER  = 0x04
new_mt.__index.FORCED_USER  = 0x05
new_mt.__index.DISPOSABLE_USER  = 0x06
new_mt.__index.EXPIRING_USER  = 0x07
new_mt.__index.SCHEDULE_RESTRICTED_USER  = 0x08
new_mt.__index.REMOTE_ONLY_USER  = 0x09

UserTypeEnum.UNRESTRICTED_USER  = 0x00
UserTypeEnum.YEAR_DAY_SCHEDULE_USER  = 0x01
UserTypeEnum.WEEK_DAY_SCHEDULE_USER  = 0x02
UserTypeEnum.PROGRAMMING_USER  = 0x03
UserTypeEnum.NON_ACCESS_USER  = 0x04
UserTypeEnum.FORCED_USER  = 0x05
UserTypeEnum.DISPOSABLE_USER  = 0x06
UserTypeEnum.EXPIRING_USER  = 0x07
UserTypeEnum.SCHEDULE_RESTRICTED_USER  = 0x08
UserTypeEnum.REMOTE_ONLY_USER  = 0x09

UserTypeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(UserTypeEnum, new_mt)

return UserTypeEnum