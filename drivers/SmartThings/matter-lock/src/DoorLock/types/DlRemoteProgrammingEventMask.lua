local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlRemoteProgrammingEventMask = {}
local new_mt = UintABC.new_mt({NAME = "DlRemoteProgrammingEventMask", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlRemoteProgrammingEventMask.BASE_MASK = 0xFFFF
DlRemoteProgrammingEventMask.UNKNOWN = 0x0001
DlRemoteProgrammingEventMask.PROGRAMMINGPIN_CHANGED = 0x0002
DlRemoteProgrammingEventMask.PIN_ADDED = 0x0004
DlRemoteProgrammingEventMask.PIN_CLEARED = 0x0008
DlRemoteProgrammingEventMask.PIN_CHANGED = 0x0010
DlRemoteProgrammingEventMask.RFID_CODE_ADDED = 0x0020
DlRemoteProgrammingEventMask.RFID_CODE_CLEARED = 0x0040

DlRemoteProgrammingEventMask.mask_fields = {
  BASE_MASK = 0xFFFF,
  UNKNOWN = 0x0001,
  PROGRAMMINGPIN_CHANGED = 0x0002,
  PIN_ADDED = 0x0004,
  PIN_CLEARED = 0x0008,
  PIN_CHANGED = 0x0010,
  RFID_CODE_ADDED = 0x0020,
  RFID_CODE_CLEARED = 0x0040,
}

DlRemoteProgrammingEventMask.is_unknown_set = function(self)
  return (self.value & self.UNKNOWN) ~= 0
end

DlRemoteProgrammingEventMask.set_unknown = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNKNOWN
  else
    self.value = self.UNKNOWN
  end
end

DlRemoteProgrammingEventMask.unset_unknown = function(self)
  self.value = self.value & (~self.UNKNOWN & self.BASE_MASK)
end

DlRemoteProgrammingEventMask.is_programmingpin_changed_set = function(self)
  return (self.value & self.PROGRAMMINGPIN_CHANGED) ~= 0
end

DlRemoteProgrammingEventMask.set_programmingpin_changed = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PROGRAMMINGPIN_CHANGED
  else
    self.value = self.PROGRAMMINGPIN_CHANGED
  end
end

DlRemoteProgrammingEventMask.unset_programmingpin_changed = function(self)
  self.value = self.value & (~self.PROGRAMMINGPIN_CHANGED & self.BASE_MASK)
end

DlRemoteProgrammingEventMask.is_pin_added_set = function(self)
  return (self.value & self.PIN_ADDED) ~= 0
end

DlRemoteProgrammingEventMask.set_pin_added = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PIN_ADDED
  else
    self.value = self.PIN_ADDED
  end
end

DlRemoteProgrammingEventMask.unset_pin_added = function(self)
  self.value = self.value & (~self.PIN_ADDED & self.BASE_MASK)
end

DlRemoteProgrammingEventMask.is_pin_cleared_set = function(self)
  return (self.value & self.PIN_CLEARED) ~= 0
end

DlRemoteProgrammingEventMask.set_pin_cleared = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PIN_CLEARED
  else
    self.value = self.PIN_CLEARED
  end
end

DlRemoteProgrammingEventMask.unset_pin_cleared = function(self)
  self.value = self.value & (~self.PIN_CLEARED & self.BASE_MASK)
end

DlRemoteProgrammingEventMask.is_pin_changed_set = function(self)
  return (self.value & self.PIN_CHANGED) ~= 0
end

DlRemoteProgrammingEventMask.set_pin_changed = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PIN_CHANGED
  else
    self.value = self.PIN_CHANGED
  end
end

DlRemoteProgrammingEventMask.unset_pin_changed = function(self)
  self.value = self.value & (~self.PIN_CHANGED & self.BASE_MASK)
end

DlRemoteProgrammingEventMask.is_rfid_code_added_set = function(self)
  return (self.value & self.RFID_CODE_ADDED) ~= 0
end

DlRemoteProgrammingEventMask.set_rfid_code_added = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RFID_CODE_ADDED
  else
    self.value = self.RFID_CODE_ADDED
  end
end

DlRemoteProgrammingEventMask.unset_rfid_code_added = function(self)
  self.value = self.value & (~self.RFID_CODE_ADDED & self.BASE_MASK)
end

DlRemoteProgrammingEventMask.is_rfid_code_cleared_set = function(self)
  return (self.value & self.RFID_CODE_CLEARED) ~= 0
end

DlRemoteProgrammingEventMask.set_rfid_code_cleared = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RFID_CODE_CLEARED
  else
    self.value = self.RFID_CODE_CLEARED
  end
end

DlRemoteProgrammingEventMask.unset_rfid_code_cleared = function(self)
  self.value = self.value & (~self.RFID_CODE_CLEARED & self.BASE_MASK)
end

DlRemoteProgrammingEventMask.mask_methods = {
  is_unknown_set = DlRemoteProgrammingEventMask.is_unknown_set,
  set_unknown = DlRemoteProgrammingEventMask.set_unknown,
  unset_unknown = DlRemoteProgrammingEventMask.unset_unknown,
  is_programmingpin_changed_set = DlRemoteProgrammingEventMask.is_programmingpin_changed_set,
  set_programmingpin_changed = DlRemoteProgrammingEventMask.set_programmingpin_changed,
  unset_programmingpin_changed = DlRemoteProgrammingEventMask.unset_programmingpin_changed,
  is_pin_added_set = DlRemoteProgrammingEventMask.is_pin_added_set,
  set_pin_added = DlRemoteProgrammingEventMask.set_pin_added,
  unset_pin_added = DlRemoteProgrammingEventMask.unset_pin_added,
  is_pin_cleared_set = DlRemoteProgrammingEventMask.is_pin_cleared_set,
  set_pin_cleared = DlRemoteProgrammingEventMask.set_pin_cleared,
  unset_pin_cleared = DlRemoteProgrammingEventMask.unset_pin_cleared,
  is_pin_changed_set = DlRemoteProgrammingEventMask.is_pin_changed_set,
  set_pin_changed = DlRemoteProgrammingEventMask.set_pin_changed,
  unset_pin_changed = DlRemoteProgrammingEventMask.unset_pin_changed,
  is_rfid_code_added_set = DlRemoteProgrammingEventMask.is_rfid_code_added_set,
  set_rfid_code_added = DlRemoteProgrammingEventMask.set_rfid_code_added,
  unset_rfid_code_added = DlRemoteProgrammingEventMask.unset_rfid_code_added,
  is_rfid_code_cleared_set = DlRemoteProgrammingEventMask.is_rfid_code_cleared_set,
  set_rfid_code_cleared = DlRemoteProgrammingEventMask.set_rfid_code_cleared,
  unset_rfid_code_cleared = DlRemoteProgrammingEventMask.unset_rfid_code_cleared,
}

DlRemoteProgrammingEventMask.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlRemoteProgrammingEventMask, new_mt)

return DlRemoteProgrammingEventMask