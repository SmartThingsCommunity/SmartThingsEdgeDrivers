local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DlRFIDProgrammingEventMask = {}
local new_mt = UintABC.new_mt({NAME = "DlRFIDProgrammingEventMask", ID = data_types.name_to_id_map["Uint16"]}, 2)

DlRFIDProgrammingEventMask.BASE_MASK = 0xFFFF
DlRFIDProgrammingEventMask.UNKNOWN = 0x0001
DlRFIDProgrammingEventMask.RFID_CODE_ADDED = 0x0020
DlRFIDProgrammingEventMask.RFID_CODE_CLEARED = 0x0040

DlRFIDProgrammingEventMask.mask_fields = {
  BASE_MASK = 0xFFFF,
  UNKNOWN = 0x0001,
  RFID_CODE_ADDED = 0x0020,
  RFID_CODE_CLEARED = 0x0040,
}

DlRFIDProgrammingEventMask.is_unknown_set = function(self)
  return (self.value & self.UNKNOWN) ~= 0
end

DlRFIDProgrammingEventMask.set_unknown = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNKNOWN
  else
    self.value = self.UNKNOWN
  end
end

DlRFIDProgrammingEventMask.unset_unknown = function(self)
  self.value = self.value & (~self.UNKNOWN & self.BASE_MASK)
end

DlRFIDProgrammingEventMask.is_rfid_code_added_set = function(self)
  return (self.value & self.RFID_CODE_ADDED) ~= 0
end

DlRFIDProgrammingEventMask.set_rfid_code_added = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RFID_CODE_ADDED
  else
    self.value = self.RFID_CODE_ADDED
  end
end

DlRFIDProgrammingEventMask.unset_rfid_code_added = function(self)
  self.value = self.value & (~self.RFID_CODE_ADDED & self.BASE_MASK)
end

DlRFIDProgrammingEventMask.is_rfid_code_cleared_set = function(self)
  return (self.value & self.RFID_CODE_CLEARED) ~= 0
end

DlRFIDProgrammingEventMask.set_rfid_code_cleared = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RFID_CODE_CLEARED
  else
    self.value = self.RFID_CODE_CLEARED
  end
end

DlRFIDProgrammingEventMask.unset_rfid_code_cleared = function(self)
  self.value = self.value & (~self.RFID_CODE_CLEARED & self.BASE_MASK)
end

DlRFIDProgrammingEventMask.mask_methods = {
  is_unknown_set = DlRFIDProgrammingEventMask.is_unknown_set,
  set_unknown = DlRFIDProgrammingEventMask.set_unknown,
  unset_unknown = DlRFIDProgrammingEventMask.unset_unknown,
  is_rfid_code_added_set = DlRFIDProgrammingEventMask.is_rfid_code_added_set,
  set_rfid_code_added = DlRFIDProgrammingEventMask.set_rfid_code_added,
  unset_rfid_code_added = DlRFIDProgrammingEventMask.unset_rfid_code_added,
  is_rfid_code_cleared_set = DlRFIDProgrammingEventMask.is_rfid_code_cleared_set,
  set_rfid_code_cleared = DlRFIDProgrammingEventMask.set_rfid_code_cleared,
  unset_rfid_code_cleared = DlRFIDProgrammingEventMask.unset_rfid_code_cleared,
}

DlRFIDProgrammingEventMask.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DlRFIDProgrammingEventMask, new_mt)

return DlRFIDProgrammingEventMask