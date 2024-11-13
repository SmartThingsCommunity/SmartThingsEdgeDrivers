local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlManualOperationEventMask = {}
local new_mt = UintABC.new_mt({NAME = "DlManualOperationEventMask", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlManualOperationEventMask.BASE_MASK = 0xFFFF
DlManualOperationEventMask.UNKNOWN = 0x0001
DlManualOperationEventMask.THUMBTURN_LOCK = 0x0002
DlManualOperationEventMask.THUMBTURN_UNLOCK = 0x0004
DlManualOperationEventMask.ONE_TOUCH_LOCK = 0x0008
DlManualOperationEventMask.KEY_LOCK = 0x0010
DlManualOperationEventMask.KEY_UNLOCK = 0x0020
DlManualOperationEventMask.AUTO_LOCK = 0x0040
DlManualOperationEventMask.SCHEDULE_LOCK = 0x0080
DlManualOperationEventMask.SCHEDULE_UNLOCK = 0x0100
DlManualOperationEventMask.MANUAL_LOCK = 0x0200
DlManualOperationEventMask.MANUAL_UNLOCK = 0x0400

DlManualOperationEventMask.mask_fields = {
  BASE_MASK = 0xFFFF,
  UNKNOWN = 0x0001,
  THUMBTURN_LOCK = 0x0002,
  THUMBTURN_UNLOCK = 0x0004,
  ONE_TOUCH_LOCK = 0x0008,
  KEY_LOCK = 0x0010,
  KEY_UNLOCK = 0x0020,
  AUTO_LOCK = 0x0040,
  SCHEDULE_LOCK = 0x0080,
  SCHEDULE_UNLOCK = 0x0100,
  MANUAL_LOCK = 0x0200,
  MANUAL_UNLOCK = 0x0400,
}

DlManualOperationEventMask.is_unknown_set = function(self)
  return (self.value & self.UNKNOWN) ~= 0
end

DlManualOperationEventMask.set_unknown = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNKNOWN
  else
    self.value = self.UNKNOWN
  end
end

DlManualOperationEventMask.unset_unknown = function(self)
  self.value = self.value & (~self.UNKNOWN & self.BASE_MASK)
end

DlManualOperationEventMask.is_thumbturn_lock_set = function(self)
  return (self.value & self.THUMBTURN_LOCK) ~= 0
end

DlManualOperationEventMask.set_thumbturn_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.THUMBTURN_LOCK
  else
    self.value = self.THUMBTURN_LOCK
  end
end

DlManualOperationEventMask.unset_thumbturn_lock = function(self)
  self.value = self.value & (~self.THUMBTURN_LOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_thumbturn_unlock_set = function(self)
  return (self.value & self.THUMBTURN_UNLOCK) ~= 0
end

DlManualOperationEventMask.set_thumbturn_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.THUMBTURN_UNLOCK
  else
    self.value = self.THUMBTURN_UNLOCK
  end
end

DlManualOperationEventMask.unset_thumbturn_unlock = function(self)
  self.value = self.value & (~self.THUMBTURN_UNLOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_one_touch_lock_set = function(self)
  return (self.value & self.ONE_TOUCH_LOCK) ~= 0
end

DlManualOperationEventMask.set_one_touch_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ONE_TOUCH_LOCK
  else
    self.value = self.ONE_TOUCH_LOCK
  end
end

DlManualOperationEventMask.unset_one_touch_lock = function(self)
  self.value = self.value & (~self.ONE_TOUCH_LOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_key_lock_set = function(self)
  return (self.value & self.KEY_LOCK) ~= 0
end

DlManualOperationEventMask.set_key_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.KEY_LOCK
  else
    self.value = self.KEY_LOCK
  end
end

DlManualOperationEventMask.unset_key_lock = function(self)
  self.value = self.value & (~self.KEY_LOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_key_unlock_set = function(self)
  return (self.value & self.KEY_UNLOCK) ~= 0
end

DlManualOperationEventMask.set_key_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.KEY_UNLOCK
  else
    self.value = self.KEY_UNLOCK
  end
end

DlManualOperationEventMask.unset_key_unlock = function(self)
  self.value = self.value & (~self.KEY_UNLOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_auto_lock_set = function(self)
  return (self.value & self.AUTO_LOCK) ~= 0
end

DlManualOperationEventMask.set_auto_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.AUTO_LOCK
  else
    self.value = self.AUTO_LOCK
  end
end

DlManualOperationEventMask.unset_auto_lock = function(self)
  self.value = self.value & (~self.AUTO_LOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_schedule_lock_set = function(self)
  return (self.value & self.SCHEDULE_LOCK) ~= 0
end

DlManualOperationEventMask.set_schedule_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SCHEDULE_LOCK
  else
    self.value = self.SCHEDULE_LOCK
  end
end

DlManualOperationEventMask.unset_schedule_lock = function(self)
  self.value = self.value & (~self.SCHEDULE_LOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_schedule_unlock_set = function(self)
  return (self.value & self.SCHEDULE_UNLOCK) ~= 0
end

DlManualOperationEventMask.set_schedule_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SCHEDULE_UNLOCK
  else
    self.value = self.SCHEDULE_UNLOCK
  end
end

DlManualOperationEventMask.unset_schedule_unlock = function(self)
  self.value = self.value & (~self.SCHEDULE_UNLOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_manual_lock_set = function(self)
  return (self.value & self.MANUAL_LOCK) ~= 0
end

DlManualOperationEventMask.set_manual_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MANUAL_LOCK
  else
    self.value = self.MANUAL_LOCK
  end
end

DlManualOperationEventMask.unset_manual_lock = function(self)
  self.value = self.value & (~self.MANUAL_LOCK & self.BASE_MASK)
end

DlManualOperationEventMask.is_manual_unlock_set = function(self)
  return (self.value & self.MANUAL_UNLOCK) ~= 0
end

DlManualOperationEventMask.set_manual_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MANUAL_UNLOCK
  else
    self.value = self.MANUAL_UNLOCK
  end
end

DlManualOperationEventMask.unset_manual_unlock = function(self)
  self.value = self.value & (~self.MANUAL_UNLOCK & self.BASE_MASK)
end

DlManualOperationEventMask.mask_methods = {
  is_unknown_set = DlManualOperationEventMask.is_unknown_set,
  set_unknown = DlManualOperationEventMask.set_unknown,
  unset_unknown = DlManualOperationEventMask.unset_unknown,
  is_thumbturn_lock_set = DlManualOperationEventMask.is_thumbturn_lock_set,
  set_thumbturn_lock = DlManualOperationEventMask.set_thumbturn_lock,
  unset_thumbturn_lock = DlManualOperationEventMask.unset_thumbturn_lock,
  is_thumbturn_unlock_set = DlManualOperationEventMask.is_thumbturn_unlock_set,
  set_thumbturn_unlock = DlManualOperationEventMask.set_thumbturn_unlock,
  unset_thumbturn_unlock = DlManualOperationEventMask.unset_thumbturn_unlock,
  is_one_touch_lock_set = DlManualOperationEventMask.is_one_touch_lock_set,
  set_one_touch_lock = DlManualOperationEventMask.set_one_touch_lock,
  unset_one_touch_lock = DlManualOperationEventMask.unset_one_touch_lock,
  is_key_lock_set = DlManualOperationEventMask.is_key_lock_set,
  set_key_lock = DlManualOperationEventMask.set_key_lock,
  unset_key_lock = DlManualOperationEventMask.unset_key_lock,
  is_key_unlock_set = DlManualOperationEventMask.is_key_unlock_set,
  set_key_unlock = DlManualOperationEventMask.set_key_unlock,
  unset_key_unlock = DlManualOperationEventMask.unset_key_unlock,
  is_auto_lock_set = DlManualOperationEventMask.is_auto_lock_set,
  set_auto_lock = DlManualOperationEventMask.set_auto_lock,
  unset_auto_lock = DlManualOperationEventMask.unset_auto_lock,
  is_schedule_lock_set = DlManualOperationEventMask.is_schedule_lock_set,
  set_schedule_lock = DlManualOperationEventMask.set_schedule_lock,
  unset_schedule_lock = DlManualOperationEventMask.unset_schedule_lock,
  is_schedule_unlock_set = DlManualOperationEventMask.is_schedule_unlock_set,
  set_schedule_unlock = DlManualOperationEventMask.set_schedule_unlock,
  unset_schedule_unlock = DlManualOperationEventMask.unset_schedule_unlock,
  is_manual_lock_set = DlManualOperationEventMask.is_manual_lock_set,
  set_manual_lock = DlManualOperationEventMask.set_manual_lock,
  unset_manual_lock = DlManualOperationEventMask.unset_manual_lock,
  is_manual_unlock_set = DlManualOperationEventMask.is_manual_unlock_set,
  set_manual_unlock = DlManualOperationEventMask.set_manual_unlock,
  unset_manual_unlock = DlManualOperationEventMask.unset_manual_unlock,
}

DlManualOperationEventMask.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlManualOperationEventMask, new_mt)

return DlManualOperationEventMask