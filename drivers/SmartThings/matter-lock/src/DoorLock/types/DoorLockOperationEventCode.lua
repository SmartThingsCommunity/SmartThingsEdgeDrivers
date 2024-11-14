local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DoorLockOperationEventCode = {}
local new_mt = UintABC.new_mt({NAME = "DoorLockOperationEventCode", ID = data_types.name_to_id_map["Uint8"]}, 1)
new_mt.__index.pretty_print = function(self)
  local name_lookup = {
    [self.UNKNOWN_OR_MFG_SPECIFIC] = "UNKNOWN_OR_MFG_SPECIFIC",
    [self.LOCK] = "LOCK",
    [self.UNLOCK] = "UNLOCK",
    [self.LOCK_INVALID_PIN_OR_ID] = "LOCK_INVALID_PIN_OR_ID",
    [self.LOCK_INVALID_SCHEDULE] = "LOCK_INVALID_SCHEDULE",
    [self.UNLOCK_INVALID_PIN_OR_ID] = "UNLOCK_INVALID_PIN_OR_ID",
    [self.UNLOCK_INVALID_SCHEDULE] = "UNLOCK_INVALID_SCHEDULE",
    [self.ONE_TOUCH_LOCK] = "ONE_TOUCH_LOCK",
    [self.KEY_LOCK] = "KEY_LOCK",
    [self.KEY_UNLOCK] = "KEY_UNLOCK",
    [self.AUTO_LOCK] = "AUTO_LOCK",
    [self.SCHEDULE_LOCK] = "SCHEDULE_LOCK",
    [self.SCHEDULE_UNLOCK] = "SCHEDULE_UNLOCK",
    [self.MANUAL_LOCK] = "MANUAL_LOCK",
    [self.MANUAL_UNLOCK] = "MANUAL_UNLOCK",
  }
  return string.format("%s: %s", self.field_name or self.NAME, name_lookup[self.value] or string.format("%d", self.value))
end
new_mt.__tostring = new_mt.__index.pretty_print

new_mt.__index.UNKNOWN_OR_MFG_SPECIFIC  = 0x00
new_mt.__index.LOCK  = 0x01
new_mt.__index.UNLOCK  = 0x02
new_mt.__index.LOCK_INVALID_PIN_OR_ID  = 0x03
new_mt.__index.LOCK_INVALID_SCHEDULE  = 0x04
new_mt.__index.UNLOCK_INVALID_PIN_OR_ID  = 0x05
new_mt.__index.UNLOCK_INVALID_SCHEDULE  = 0x06
new_mt.__index.ONE_TOUCH_LOCK  = 0x07
new_mt.__index.KEY_LOCK  = 0x08
new_mt.__index.KEY_UNLOCK  = 0x09
new_mt.__index.AUTO_LOCK  = 0x0A
new_mt.__index.SCHEDULE_LOCK  = 0x0B
new_mt.__index.SCHEDULE_UNLOCK  = 0x0C
new_mt.__index.MANUAL_LOCK  = 0x0D
new_mt.__index.MANUAL_UNLOCK  = 0x0E

DoorLockOperationEventCode.UNKNOWN_OR_MFG_SPECIFIC  = 0x00
DoorLockOperationEventCode.LOCK  = 0x01
DoorLockOperationEventCode.UNLOCK  = 0x02
DoorLockOperationEventCode.LOCK_INVALID_PIN_OR_ID  = 0x03
DoorLockOperationEventCode.LOCK_INVALID_SCHEDULE  = 0x04
DoorLockOperationEventCode.UNLOCK_INVALID_PIN_OR_ID  = 0x05
DoorLockOperationEventCode.UNLOCK_INVALID_SCHEDULE  = 0x06
DoorLockOperationEventCode.ONE_TOUCH_LOCK  = 0x07
DoorLockOperationEventCode.KEY_LOCK  = 0x08
DoorLockOperationEventCode.KEY_UNLOCK  = 0x09
DoorLockOperationEventCode.AUTO_LOCK  = 0x0A
DoorLockOperationEventCode.SCHEDULE_LOCK  = 0x0B
DoorLockOperationEventCode.SCHEDULE_UNLOCK  = 0x0C
DoorLockOperationEventCode.MANUAL_LOCK  = 0x0D
DoorLockOperationEventCode.MANUAL_UNLOCK  = 0x0E

DoorLockOperationEventCode.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DoorLockOperationEventCode, new_mt)

return DoorLockOperationEventCode