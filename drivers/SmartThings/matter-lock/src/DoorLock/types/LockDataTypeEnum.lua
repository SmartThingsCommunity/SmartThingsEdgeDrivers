local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local LockDataTypeEnum = {}
local new_mt = UintABC.new_mt({NAME = "LockDataTypeEnum", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNSPECIFIED] = "UNSPECIFIED",
    [self.PROGRAMMING_CODE] = "PROGRAMMING_CODE",
    [self.USER_INDEX] = "USER_INDEX",
    [self.WEEK_DAY_SCHEDULE] = "WEEK_DAY_SCHEDULE",
    [self.YEAR_DAY_SCHEDULE] = "YEAR_DAY_SCHEDULE",
    [self.HOLIDAY_SCHEDULE] = "HOLIDAY_SCHEDULE",
    [self.PIN] = "PIN",
    [self.RFID] = "RFID",
    [self.FINGERPRINT] = "FINGERPRINT",
    [self.FINGER_VEIN] = "FINGER_VEIN",
    [self.FACE] = "FACE",
    [self.ALIRO_CREDENTIAL_ISSUER_KEY] = "ALIRO_CREDENTIAL_ISSUER_KEY",
    [self.ALIRO_EVICTABLE_ENDPOINT_KEY] = "ALIRO_EVICTABLE_ENDPOINT_KEY",
    [self.ALIRO_NON_EVICTABLE_ENDPOINT_KEY] = "ALIRO_NON_EVICTABLE_ENDPOINT_KEY",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNSPECIFIED  = 0x00
new_mt.__index.PROGRAMMING_CODE  = 0x01
new_mt.__index.USER_INDEX  = 0x02
new_mt.__index.WEEK_DAY_SCHEDULE  = 0x03
new_mt.__index.YEAR_DAY_SCHEDULE  = 0x04
new_mt.__index.HOLIDAY_SCHEDULE  = 0x05
new_mt.__index.PIN  = 0x06
new_mt.__index.RFID  = 0x07
new_mt.__index.FINGERPRINT  = 0x08
new_mt.__index.FINGER_VEIN  = 0x09
new_mt.__index.FACE  = 0x0A
new_mt.__index.ALIRO_CREDENTIAL_ISSUER_KEY  = 0x0B
new_mt.__index.ALIRO_EVICTABLE_ENDPOINT_KEY  = 0x0C
new_mt.__index.ALIRO_NON_EVICTABLE_ENDPOINT_KEY  = 0x0D

LockDataTypeEnum.UNSPECIFIED  = 0x00
LockDataTypeEnum.PROGRAMMING_CODE  = 0x01
LockDataTypeEnum.USER_INDEX  = 0x02
LockDataTypeEnum.WEEK_DAY_SCHEDULE  = 0x03
LockDataTypeEnum.YEAR_DAY_SCHEDULE  = 0x04
LockDataTypeEnum.HOLIDAY_SCHEDULE  = 0x05
LockDataTypeEnum.PIN  = 0x06
LockDataTypeEnum.RFID  = 0x07
LockDataTypeEnum.FINGERPRINT  = 0x08
LockDataTypeEnum.FINGER_VEIN  = 0x09
LockDataTypeEnum.FACE  = 0x0A
LockDataTypeEnum.ALIRO_CREDENTIAL_ISSUER_KEY  = 0x0B
LockDataTypeEnum.ALIRO_EVICTABLE_ENDPOINT_KEY  = 0x0C
LockDataTypeEnum.ALIRO_NON_EVICTABLE_ENDPOINT_KEY  = 0x0D

LockDataTypeEnum.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(LockDataTypeEnum, new_mt)

return LockDataTypeEnum