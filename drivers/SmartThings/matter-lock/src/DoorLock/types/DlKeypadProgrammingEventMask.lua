local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlKeypadProgrammingEventMask = {}
local new_mt = UintABC.new_mt({NAME = "DlKeypadProgrammingEventMask", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlKeypadProgrammingEventMask.BASE_MASK = 0xFFFF
DlKeypadProgrammingEventMask.UNKNOWN = 0x0001
DlKeypadProgrammingEventMask.PROGRAMMINGPIN_CHANGED = 0x0002
DlKeypadProgrammingEventMask.PIN_ADDED = 0x0004
DlKeypadProgrammingEventMask.PIN_CLEARED = 0x0008
DlKeypadProgrammingEventMask.PIN_CHANGED = 0x0010

DlKeypadProgrammingEventMask.mask_fields = {
  BASE_MASK = 0xFFFF,
  UNKNOWN = 0x0001,
  PROGRAMMINGPIN_CHANGED = 0x0002,
  PIN_ADDED = 0x0004,
  PIN_CLEARED = 0x0008,
  PIN_CHANGED = 0x0010,
}

DlKeypadProgrammingEventMask.is_unknown_set = function(self)
  return (self.value & self.UNKNOWN) ~= 0
end

DlKeypadProgrammingEventMask.set_unknown = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNKNOWN
  else
    self.value = self.UNKNOWN
  end
end

DlKeypadProgrammingEventMask.unset_unknown = function(self)
  self.value = self.value & (~self.UNKNOWN & self.BASE_MASK)
end

DlKeypadProgrammingEventMask.is_programmingpin_changed_set = function(self)
  return (self.value & self.PROGRAMMINGPIN_CHANGED) ~= 0
end

DlKeypadProgrammingEventMask.set_programmingpin_changed = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PROGRAMMINGPIN_CHANGED
  else
    self.value = self.PROGRAMMINGPIN_CHANGED
  end
end

DlKeypadProgrammingEventMask.unset_programmingpin_changed = function(self)
  self.value = self.value & (~self.PROGRAMMINGPIN_CHANGED & self.BASE_MASK)
end

DlKeypadProgrammingEventMask.is_pin_added_set = function(self)
  return (self.value & self.PIN_ADDED) ~= 0
end

DlKeypadProgrammingEventMask.set_pin_added = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PIN_ADDED
  else
    self.value = self.PIN_ADDED
  end
end

DlKeypadProgrammingEventMask.unset_pin_added = function(self)
  self.value = self.value & (~self.PIN_ADDED & self.BASE_MASK)
end

DlKeypadProgrammingEventMask.is_pin_cleared_set = function(self)
  return (self.value & self.PIN_CLEARED) ~= 0
end

DlKeypadProgrammingEventMask.set_pin_cleared = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PIN_CLEARED
  else
    self.value = self.PIN_CLEARED
  end
end

DlKeypadProgrammingEventMask.unset_pin_cleared = function(self)
  self.value = self.value & (~self.PIN_CLEARED & self.BASE_MASK)
end

DlKeypadProgrammingEventMask.is_pin_changed_set = function(self)
  return (self.value & self.PIN_CHANGED) ~= 0
end

DlKeypadProgrammingEventMask.set_pin_changed = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PIN_CHANGED
  else
    self.value = self.PIN_CHANGED
  end
end

DlKeypadProgrammingEventMask.unset_pin_changed = function(self)
  self.value = self.value & (~self.PIN_CHANGED & self.BASE_MASK)
end

DlKeypadProgrammingEventMask.mask_methods = {
  is_unknown_set = DlKeypadProgrammingEventMask.is_unknown_set,
  set_unknown = DlKeypadProgrammingEventMask.set_unknown,
  unset_unknown = DlKeypadProgrammingEventMask.unset_unknown,
  is_programmingpin_changed_set = DlKeypadProgrammingEventMask.is_programmingpin_changed_set,
  set_programmingpin_changed = DlKeypadProgrammingEventMask.set_programmingpin_changed,
  unset_programmingpin_changed = DlKeypadProgrammingEventMask.unset_programmingpin_changed,
  is_pin_added_set = DlKeypadProgrammingEventMask.is_pin_added_set,
  set_pin_added = DlKeypadProgrammingEventMask.set_pin_added,
  unset_pin_added = DlKeypadProgrammingEventMask.unset_pin_added,
  is_pin_cleared_set = DlKeypadProgrammingEventMask.is_pin_cleared_set,
  set_pin_cleared = DlKeypadProgrammingEventMask.set_pin_cleared,
  unset_pin_cleared = DlKeypadProgrammingEventMask.unset_pin_cleared,
  is_pin_changed_set = DlKeypadProgrammingEventMask.is_pin_changed_set,
  set_pin_changed = DlKeypadProgrammingEventMask.set_pin_changed,
  unset_pin_changed = DlKeypadProgrammingEventMask.unset_pin_changed,
}

DlKeypadProgrammingEventMask.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlKeypadProgrammingEventMask, new_mt)

return DlKeypadProgrammingEventMask