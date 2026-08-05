local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlRFIDOperationEventMask = {}
local new_mt = UintABC.new_mt({NAME = "DlRFIDOperationEventMask", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlRFIDOperationEventMask.BASE_MASK = 0xFFFF
DlRFIDOperationEventMask.UNKNOWN = 0x0001
DlRFIDOperationEventMask.LOCK = 0x0002
DlRFIDOperationEventMask.UNLOCK = 0x0004
DlRFIDOperationEventMask.LOCK_INVALIDRFID = 0x0008
DlRFIDOperationEventMask.LOCK_INVALID_SCHEDULE = 0x0010
DlRFIDOperationEventMask.UNLOCK_INVALIDRFID = 0x0020
DlRFIDOperationEventMask.UNLOCK_INVALID_SCHEDULE = 0x0040

DlRFIDOperationEventMask.mask_fields = {
  BASE_MASK = 0xFFFF,
  UNKNOWN = 0x0001,
  LOCK = 0x0002,
  UNLOCK = 0x0004,
  LOCK_INVALIDRFID = 0x0008,
  LOCK_INVALID_SCHEDULE = 0x0010,
  UNLOCK_INVALIDRFID = 0x0020,
  UNLOCK_INVALID_SCHEDULE = 0x0040,
}

DlRFIDOperationEventMask.is_unknown_set = function(self)
  return (self.value & self.UNKNOWN) ~= 0
end

DlRFIDOperationEventMask.set_unknown = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNKNOWN
  else
    self.value = self.UNKNOWN
  end
end

DlRFIDOperationEventMask.unset_unknown = function(self)
  self.value = self.value & (~self.UNKNOWN & self.BASE_MASK)
end

DlRFIDOperationEventMask.is_lock_set = function(self)
  return (self.value & self.LOCK) ~= 0
end

DlRFIDOperationEventMask.set_lock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK
  else
    self.value = self.LOCK
  end
end

DlRFIDOperationEventMask.unset_lock = function(self)
  self.value = self.value & (~self.LOCK & self.BASE_MASK)
end

DlRFIDOperationEventMask.is_unlock_set = function(self)
  return (self.value & self.UNLOCK) ~= 0
end

DlRFIDOperationEventMask.set_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK
  else
    self.value = self.UNLOCK
  end
end

DlRFIDOperationEventMask.unset_unlock = function(self)
  self.value = self.value & (~self.UNLOCK & self.BASE_MASK)
end

DlRFIDOperationEventMask.is_lock_invalidrfid_set = function(self)
  return (self.value & self.LOCK_INVALIDRFID) ~= 0
end

DlRFIDOperationEventMask.set_lock_invalidrfid = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK_INVALIDRFID
  else
    self.value = self.LOCK_INVALIDRFID
  end
end

DlRFIDOperationEventMask.unset_lock_invalidrfid = function(self)
  self.value = self.value & (~self.LOCK_INVALIDRFID & self.BASE_MASK)
end

DlRFIDOperationEventMask.is_lock_invalid_schedule_set = function(self)
  return (self.value & self.LOCK_INVALID_SCHEDULE) ~= 0
end

DlRFIDOperationEventMask.set_lock_invalid_schedule = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCK_INVALID_SCHEDULE
  else
    self.value = self.LOCK_INVALID_SCHEDULE
  end
end

DlRFIDOperationEventMask.unset_lock_invalid_schedule = function(self)
  self.value = self.value & (~self.LOCK_INVALID_SCHEDULE & self.BASE_MASK)
end

DlRFIDOperationEventMask.is_unlock_invalidrfid_set = function(self)
  return (self.value & self.UNLOCK_INVALIDRFID) ~= 0
end

DlRFIDOperationEventMask.set_unlock_invalidrfid = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK_INVALIDRFID
  else
    self.value = self.UNLOCK_INVALIDRFID
  end
end

DlRFIDOperationEventMask.unset_unlock_invalidrfid = function(self)
  self.value = self.value & (~self.UNLOCK_INVALIDRFID & self.BASE_MASK)
end

DlRFIDOperationEventMask.is_unlock_invalid_schedule_set = function(self)
  return (self.value & self.UNLOCK_INVALID_SCHEDULE) ~= 0
end

DlRFIDOperationEventMask.set_unlock_invalid_schedule = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNLOCK_INVALID_SCHEDULE
  else
    self.value = self.UNLOCK_INVALID_SCHEDULE
  end
end

DlRFIDOperationEventMask.unset_unlock_invalid_schedule = function(self)
  self.value = self.value & (~self.UNLOCK_INVALID_SCHEDULE & self.BASE_MASK)
end

DlRFIDOperationEventMask.mask_methods = {
  is_unknown_set = DlRFIDOperationEventMask.is_unknown_set,
  set_unknown = DlRFIDOperationEventMask.set_unknown,
  unset_unknown = DlRFIDOperationEventMask.unset_unknown,
  is_lock_set = DlRFIDOperationEventMask.is_lock_set,
  set_lock = DlRFIDOperationEventMask.set_lock,
  unset_lock = DlRFIDOperationEventMask.unset_lock,
  is_unlock_set = DlRFIDOperationEventMask.is_unlock_set,
  set_unlock = DlRFIDOperationEventMask.set_unlock,
  unset_unlock = DlRFIDOperationEventMask.unset_unlock,
  is_lock_invalidrfid_set = DlRFIDOperationEventMask.is_lock_invalidrfid_set,
  set_lock_invalidrfid = DlRFIDOperationEventMask.set_lock_invalidrfid,
  unset_lock_invalidrfid = DlRFIDOperationEventMask.unset_lock_invalidrfid,
  is_lock_invalid_schedule_set = DlRFIDOperationEventMask.is_lock_invalid_schedule_set,
  set_lock_invalid_schedule = DlRFIDOperationEventMask.set_lock_invalid_schedule,
  unset_lock_invalid_schedule = DlRFIDOperationEventMask.unset_lock_invalid_schedule,
  is_unlock_invalidrfid_set = DlRFIDOperationEventMask.is_unlock_invalidrfid_set,
  set_unlock_invalidrfid = DlRFIDOperationEventMask.set_unlock_invalidrfid,
  unset_unlock_invalidrfid = DlRFIDOperationEventMask.unset_unlock_invalidrfid,
  is_unlock_invalid_schedule_set = DlRFIDOperationEventMask.is_unlock_invalid_schedule_set,
  set_unlock_invalid_schedule = DlRFIDOperationEventMask.set_unlock_invalid_schedule,
  unset_unlock_invalid_schedule = DlRFIDOperationEventMask.unset_unlock_invalid_schedule,
}

DlRFIDOperationEventMask.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlRFIDOperationEventMask, new_mt)

return DlRFIDOperationEventMask