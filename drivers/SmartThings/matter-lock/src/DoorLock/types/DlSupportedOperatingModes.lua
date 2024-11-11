local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlSupportedOperatingModes = {}
local new_mt = UintABC.new_mt({NAME = "DlSupportedOperatingModes", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlSupportedOperatingModes.BASE_MASK = 0xFFFF
DlSupportedOperatingModes.NORMAL = 0x0001
DlSupportedOperatingModes.VACATION = 0x0002
DlSupportedOperatingModes.PRIVACY = 0x0004
DlSupportedOperatingModes.NO_REMOTE_LOCK_UNLOCK = 0x0008
DlSupportedOperatingModes.PASSAGE = 0x0010

DlSupportedOperatingModes.mask_fields = {
  BASE_MASK = 0xFFFF,
  NORMAL = 0x0001,
  VACATION = 0x0002,
  PRIVACY = 0x0004,
  NO_REMOTE_LOCK_UNLOCK = 0x0008,
  PASSAGE = 0x0010,
}

DlSupportedOperatingModes.is_normal_set = function(self)
  return (self.value & self.NORMAL) ~= 0
end

DlSupportedOperatingModes.set_normal = function(self)
  if self.value ~= nil then
    self.value = self.value | self.NORMAL
  else
    self.value = self.NORMAL
  end
end

DlSupportedOperatingModes.unset_normal = function(self)
  self.value = self.value & (~self.NORMAL & self.BASE_MASK)
end

DlSupportedOperatingModes.is_vacation_set = function(self)
  return (self.value & self.VACATION) ~= 0
end

DlSupportedOperatingModes.set_vacation = function(self)
  if self.value ~= nil then
    self.value = self.value | self.VACATION
  else
    self.value = self.VACATION
  end
end

DlSupportedOperatingModes.unset_vacation = function(self)
  self.value = self.value & (~self.VACATION & self.BASE_MASK)
end

DlSupportedOperatingModes.is_privacy_set = function(self)
  return (self.value & self.PRIVACY) ~= 0
end

DlSupportedOperatingModes.set_privacy = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PRIVACY
  else
    self.value = self.PRIVACY
  end
end

DlSupportedOperatingModes.unset_privacy = function(self)
  self.value = self.value & (~self.PRIVACY & self.BASE_MASK)
end

DlSupportedOperatingModes.is_no_remote_lock_unlock_set = function(self)
  return (self.value & self.NO_REMOTE_LOCK_UNLOCK) ~= 0
end

DlSupportedOperatingModes.set_no_remote_lock_unlock = function(self)
  if self.value ~= nil then
    self.value = self.value | self.NO_REMOTE_LOCK_UNLOCK
  else
    self.value = self.NO_REMOTE_LOCK_UNLOCK
  end
end

DlSupportedOperatingModes.unset_no_remote_lock_unlock = function(self)
  self.value = self.value & (~self.NO_REMOTE_LOCK_UNLOCK & self.BASE_MASK)
end

DlSupportedOperatingModes.is_passage_set = function(self)
  return (self.value & self.PASSAGE) ~= 0
end

DlSupportedOperatingModes.set_passage = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PASSAGE
  else
    self.value = self.PASSAGE
  end
end

DlSupportedOperatingModes.unset_passage = function(self)
  self.value = self.value & (~self.PASSAGE & self.BASE_MASK)
end

DlSupportedOperatingModes.mask_methods = {
  is_normal_set = DlSupportedOperatingModes.is_normal_set,
  set_normal = DlSupportedOperatingModes.set_normal,
  unset_normal = DlSupportedOperatingModes.unset_normal,
  is_vacation_set = DlSupportedOperatingModes.is_vacation_set,
  set_vacation = DlSupportedOperatingModes.set_vacation,
  unset_vacation = DlSupportedOperatingModes.unset_vacation,
  is_privacy_set = DlSupportedOperatingModes.is_privacy_set,
  set_privacy = DlSupportedOperatingModes.set_privacy,
  unset_privacy = DlSupportedOperatingModes.unset_privacy,
  is_no_remote_lock_unlock_set = DlSupportedOperatingModes.is_no_remote_lock_unlock_set,
  set_no_remote_lock_unlock = DlSupportedOperatingModes.set_no_remote_lock_unlock,
  unset_no_remote_lock_unlock = DlSupportedOperatingModes.unset_no_remote_lock_unlock,
  is_passage_set = DlSupportedOperatingModes.is_passage_set,
  set_passage = DlSupportedOperatingModes.set_passage,
  unset_passage = DlSupportedOperatingModes.unset_passage,
}

DlSupportedOperatingModes.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlSupportedOperatingModes, new_mt)

return DlSupportedOperatingModes