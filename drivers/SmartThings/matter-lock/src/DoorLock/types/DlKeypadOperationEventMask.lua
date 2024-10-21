local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlKeypadOperationEventMask = {}
local new_mt = UintABC.new_mt({NAME = "DlKeypadOperationEventMask", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlKeypadOperationEventMask.BASE_MASK = 0xFFFF
DlKeypadOperationEventMask.UNKNOWN = 0x0001
DlKeypadOperationEventMask.LOCK = 0x0002
DlKeypadOperationEventMask.UNLOCK = 0x0004
DlKeypadOperationEventMask.LOCK_INVALIDPIN = 0x0008
DlKeypadOperationEventMask.LOCK_INVALID_SCHEDULE = 0x0010
DlKeypadOperationEventMask.UNLOCK_INVALID_CODE = 0x0020
DlKeypadOperationEventMask.UNLOCK_INVALID_SCHEDULE = 0x0040
DlKeypadOperationEventMask.NON_ACCESS_USER_OP_EVENT = 0x0080

DlKeypadOperationEventMask.mask_fields = {
  BASE_MASK = 0xFFFF,
  UNKNOWN = 0x0001,
  LOCK = 0x0002,
  UNLOCK = 0x0004,
  LOCK_INVALIDPIN = 0x0008,
  LOCK_INVALID_SCHEDULE = 0x0010,
  UNLOCK_INVALID_CODE = 0x0020,
  UNLOCK_INVALID_SCHEDULE = 0x0040,
  NON_ACCESS_USER_OP_EVENT = 0x0080,
}

DlKeypadOperationEventMask.is_unknown_set = function(self)
  return (self.value & self.UNKNOWN) ~= 0
end

DlKeypadOperationEventMask.set_unknown = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNKNOWN
  else
    self.value = self.UNKNOWN
  end
end

DlKeypadOperationEventMask.unset_unknown = function(self)
  self.value = self.value & (~self.UNKNOWN & self.BASE_MASK)
end

DlKeypadOperationEventMask.is_lock_set = function(self)
  return (self.value & self.LOCK) ~= 0
end

DlKeypadOperationEventMask.set_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK
  else
    self.value = self.LOCK
  end
end

DlKeypadOperationEventMask.unset_lock = function(self)
  self.value = self.value & (~self.LOCK & self.BASE_MASK)
end

DlKeypadOperationEventMask.is_unlock_set = function(self)
  return (self.value & self.UNLOCK) ~= 0
end

DlKeypadOperationEventMask.set_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK
  else
    self.value = self.UNLOCK
  end
end

DlKeypadOperationEventMask.unset_unlock = function(self)
  self.value = self.value & (~self.UNLOCK & self.BASE_MASK)
end

DlKeypadOperationEventMask.is_lock_invalidpin_set = function(self)
  return (self.value & self.LOCK_INVALIDPIN) ~= 0
end

DlKeypadOperationEventMask.set_lock_invalidpin = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK_INVALIDPIN
  else
    self.value = self.LOCK_INVALIDPIN
  end
end

DlKeypadOperationEventMask.unset_lock_invalidpin = function(self)
  self.value = self.value & (~self.LOCK_INVALIDPIN & self.BASE_MASK)
end

DlKeypadOperationEventMask.is_lock_invalid_schedule_set = function(self)
  return (self.value & self.LOCK_INVALID_SCHEDULE) ~= 0
end

DlKeypadOperationEventMask.set_lock_invalid_schedule = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK_INVALID_SCHEDULE
  else
    self.value = self.LOCK_INVALID_SCHEDULE
  end
end

DlKeypadOperationEventMask.unset_lock_invalid_schedule = function(self)
  self.value = self.value & (~self.LOCK_INVALID_SCHEDULE & self.BASE_MASK)
end

DlKeypadOperationEventMask.is_unlock_invalid_code_set = function(self)
  return (self.value & self.UNLOCK_INVALID_CODE) ~= 0
end

DlKeypadOperationEventMask.set_unlock_invalid_code = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK_INVALID_CODE
  else
    self.value = self.UNLOCK_INVALID_CODE
  end
end

DlKeypadOperationEventMask.unset_unlock_invalid_code = function(self)
  self.value = self.value & (~self.UNLOCK_INVALID_CODE & self.BASE_MASK)
end

DlKeypadOperationEventMask.is_unlock_invalid_schedule_set = function(self)
  return (self.value & self.UNLOCK_INVALID_SCHEDULE) ~= 0
end

DlKeypadOperationEventMask.set_unlock_invalid_schedule = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK_INVALID_SCHEDULE
  else
    self.value = self.UNLOCK_INVALID_SCHEDULE
  end
end

DlKeypadOperationEventMask.unset_unlock_invalid_schedule = function(self)
  self.value = self.value & (~self.UNLOCK_INVALID_SCHEDULE & self.BASE_MASK)
end

DlKeypadOperationEventMask.is_non_access_user_op_event_set = function(self)
  return (self.value & self.NON_ACCESS_USER_OP_EVENT) ~= 0
end

DlKeypadOperationEventMask.set_non_access_user_op_event = function(self)
  if self.value ~= nil then
    self.value = self.value | self.NON_ACCESS_USER_OP_EVENT
  else
    self.value = self.NON_ACCESS_USER_OP_EVENT
  end
end

DlKeypadOperationEventMask.unset_non_access_user_op_event = function(self)
  self.value = self.value & (~self.NON_ACCESS_USER_OP_EVENT & self.BASE_MASK)
end

DlKeypadOperationEventMask.mask_methods = {
  is_unknown_set = DlKeypadOperationEventMask.is_unknown_set,
  set_unknown = DlKeypadOperationEventMask.set_unknown,
  unset_unknown = DlKeypadOperationEventMask.unset_unknown,
  is_lock_set = DlKeypadOperationEventMask.is_lock_set,
  set_lock = DlKeypadOperationEventMask.set_lock,
  unset_lock = DlKeypadOperationEventMask.unset_lock,
  is_unlock_set = DlKeypadOperationEventMask.is_unlock_set,
  set_unlock = DlKeypadOperationEventMask.set_unlock,
  unset_unlock = DlKeypadOperationEventMask.unset_unlock,
  is_lock_invalidpin_set = DlKeypadOperationEventMask.is_lock_invalidpin_set,
  set_lock_invalidpin = DlKeypadOperationEventMask.set_lock_invalidpin,
  unset_lock_invalidpin = DlKeypadOperationEventMask.unset_lock_invalidpin,
  is_lock_invalid_schedule_set = DlKeypadOperationEventMask.is_lock_invalid_schedule_set,
  set_lock_invalid_schedule = DlKeypadOperationEventMask.set_lock_invalid_schedule,
  unset_lock_invalid_schedule = DlKeypadOperationEventMask.unset_lock_invalid_schedule,
  is_unlock_invalid_code_set = DlKeypadOperationEventMask.is_unlock_invalid_code_set,
  set_unlock_invalid_code = DlKeypadOperationEventMask.set_unlock_invalid_code,
  unset_unlock_invalid_code = DlKeypadOperationEventMask.unset_unlock_invalid_code,
  is_unlock_invalid_schedule_set = DlKeypadOperationEventMask.is_unlock_invalid_schedule_set,
  set_unlock_invalid_schedule = DlKeypadOperationEventMask.set_unlock_invalid_schedule,
  unset_unlock_invalid_schedule = DlKeypadOperationEventMask.unset_unlock_invalid_schedule,
  is_non_access_user_op_event_set = DlKeypadOperationEventMask.is_non_access_user_op_event_set,
  set_non_access_user_op_event = DlKeypadOperationEventMask.set_non_access_user_op_event,
  unset_non_access_user_op_event = DlKeypadOperationEventMask.unset_non_access_user_op_event,
}

DlKeypadOperationEventMask.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlKeypadOperationEventMask, new_mt)

return DlKeypadOperationEventMask