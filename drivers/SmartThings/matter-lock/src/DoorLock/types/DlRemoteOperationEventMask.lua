local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlRemoteOperationEventMask = {}
local new_mt = UintABC.new_mt({NAME = "DlRemoteOperationEventMask", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlRemoteOperationEventMask.BASE_MASK = 0xFFFF
DlRemoteOperationEventMask.UNKNOWN = 0x0001
DlRemoteOperationEventMask.LOCK = 0x0002
DlRemoteOperationEventMask.UNLOCK = 0x0004
DlRemoteOperationEventMask.LOCK_INVALID_CODE = 0x0008
DlRemoteOperationEventMask.LOCK_INVALID_SCHEDULE = 0x0010
DlRemoteOperationEventMask.UNLOCK_INVALID_CODE = 0x0020
DlRemoteOperationEventMask.UNLOCK_INVALID_SCHEDULE = 0x0040

DlRemoteOperationEventMask.mask_fields = {
  BASE_MASK = 0xFFFF,
  UNKNOWN = 0x0001,
  LOCK = 0x0002,
  UNLOCK = 0x0004,
  LOCK_INVALID_CODE = 0x0008,
  LOCK_INVALID_SCHEDULE = 0x0010,
  UNLOCK_INVALID_CODE = 0x0020,
  UNLOCK_INVALID_SCHEDULE = 0x0040,
}

DlRemoteOperationEventMask.is_unknown_set = function(self)
  return (self.value & self.UNKNOWN) ~= 0
end

DlRemoteOperationEventMask.set_unknown = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNKNOWN
  else
    self.value = self.UNKNOWN
  end
end

DlRemoteOperationEventMask.unset_unknown = function(self)
  self.value = self.value & (~self.UNKNOWN & self.BASE_MASK)
end

DlRemoteOperationEventMask.is_lock_set = function(self)
  return (self.value & self.LOCK) ~= 0
end

DlRemoteOperationEventMask.set_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK
  else
    self.value = self.LOCK
  end
end

DlRemoteOperationEventMask.unset_lock = function(self)
  self.value = self.value & (~self.LOCK & self.BASE_MASK)
end

DlRemoteOperationEventMask.is_unlock_set = function(self)
  return (self.value & self.UNLOCK) ~= 0
end

DlRemoteOperationEventMask.set_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK
  else
    self.value = self.UNLOCK
  end
end

DlRemoteOperationEventMask.unset_unlock = function(self)
  self.value = self.value & (~self.UNLOCK & self.BASE_MASK)
end

DlRemoteOperationEventMask.is_lock_invalid_code_set = function(self)
  return (self.value & self.LOCK_INVALID_CODE) ~= 0
end

DlRemoteOperationEventMask.set_lock_invalid_code = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK_INVALID_CODE
  else
    self.value = self.LOCK_INVALID_CODE
  end
end

DlRemoteOperationEventMask.unset_lock_invalid_code = function(self)
  self.value = self.value & (~self.LOCK_INVALID_CODE & self.BASE_MASK)
end

DlRemoteOperationEventMask.is_lock_invalid_schedule_set = function(self)
  return (self.value & self.LOCK_INVALID_SCHEDULE) ~= 0
end

DlRemoteOperationEventMask.set_lock_invalid_schedule = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK_INVALID_SCHEDULE
  else
    self.value = self.LOCK_INVALID_SCHEDULE
  end
end

DlRemoteOperationEventMask.unset_lock_invalid_schedule = function(self)
  self.value = self.value & (~self.LOCK_INVALID_SCHEDULE & self.BASE_MASK)
end

DlRemoteOperationEventMask.is_unlock_invalid_code_set = function(self)
  return (self.value & self.UNLOCK_INVALID_CODE) ~= 0
end

DlRemoteOperationEventMask.set_unlock_invalid_code = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK_INVALID_CODE
  else
    self.value = self.UNLOCK_INVALID_CODE
  end
end

DlRemoteOperationEventMask.unset_unlock_invalid_code = function(self)
  self.value = self.value & (~self.UNLOCK_INVALID_CODE & self.BASE_MASK)
end

DlRemoteOperationEventMask.is_unlock_invalid_schedule_set = function(self)
  return (self.value & self.UNLOCK_INVALID_SCHEDULE) ~= 0
end

DlRemoteOperationEventMask.set_unlock_invalid_schedule = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK_INVALID_SCHEDULE
  else
    self.value = self.UNLOCK_INVALID_SCHEDULE
  end
end

DlRemoteOperationEventMask.unset_unlock_invalid_schedule = function(self)
  self.value = self.value & (~self.UNLOCK_INVALID_SCHEDULE & self.BASE_MASK)
end

DlRemoteOperationEventMask.mask_methods = {
  is_unknown_set = DlRemoteOperationEventMask.is_unknown_set,
  set_unknown = DlRemoteOperationEventMask.set_unknown,
  unset_unknown = DlRemoteOperationEventMask.unset_unknown,
  is_lock_set = DlRemoteOperationEventMask.is_lock_set,
  set_lock = DlRemoteOperationEventMask.set_lock,
  unset_lock = DlRemoteOperationEventMask.unset_lock,
  is_unlock_set = DlRemoteOperationEventMask.is_unlock_set,
  set_unlock = DlRemoteOperationEventMask.set_unlock,
  unset_unlock = DlRemoteOperationEventMask.unset_unlock,
  is_lock_invalid_code_set = DlRemoteOperationEventMask.is_lock_invalid_code_set,
  set_lock_invalid_code = DlRemoteOperationEventMask.set_lock_invalid_code,
  unset_lock_invalid_code = DlRemoteOperationEventMask.unset_lock_invalid_code,
  is_lock_invalid_schedule_set = DlRemoteOperationEventMask.is_lock_invalid_schedule_set,
  set_lock_invalid_schedule = DlRemoteOperationEventMask.set_lock_invalid_schedule,
  unset_lock_invalid_schedule = DlRemoteOperationEventMask.unset_lock_invalid_schedule,
  is_unlock_invalid_code_set = DlRemoteOperationEventMask.is_unlock_invalid_code_set,
  set_unlock_invalid_code = DlRemoteOperationEventMask.set_unlock_invalid_code,
  unset_unlock_invalid_code = DlRemoteOperationEventMask.unset_unlock_invalid_code,
  is_unlock_invalid_schedule_set = DlRemoteOperationEventMask.is_unlock_invalid_schedule_set,
  set_unlock_invalid_schedule = DlRemoteOperationEventMask.set_unlock_invalid_schedule,
  unset_unlock_invalid_schedule = DlRemoteOperationEventMask.unset_unlock_invalid_schedule,
}

DlRemoteOperationEventMask.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlRemoteOperationEventMask, new_mt)

return DlRemoteOperationEventMask