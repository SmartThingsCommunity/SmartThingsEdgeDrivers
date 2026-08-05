local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DoorLockDayOfWeek = {}
local new_mt = UintABC.new_mt({NAME = "DoorLockDayOfWeek", ID = data_types.name_to_id_map["Uint8"]}, 1)

DoorLockDayOfWeek.BASE_MASK = 0xFFFF
DoorLockDayOfWeek.SUNDAY = 0x0001
DoorLockDayOfWeek.MONDAY = 0x0002
DoorLockDayOfWeek.TUESDAY = 0x0004
DoorLockDayOfWeek.WEDNESDAY = 0x0008
DoorLockDayOfWeek.THURSDAY = 0x0010
DoorLockDayOfWeek.FRIDAY = 0x0020
DoorLockDayOfWeek.SATURDAY = 0x0040

DoorLockDayOfWeek.mask_fields = {
  BASE_MASK = 0xFFFF,
  SUNDAY = 0x0001,
  MONDAY = 0x0002,
  TUESDAY = 0x0004,
  WEDNESDAY = 0x0008,
  THURSDAY = 0x0010,
  FRIDAY = 0x0020,
  SATURDAY = 0x0040,
}

DoorLockDayOfWeek.is_sunday_set = function(self)
  return (self.value & self.SUNDAY) ~= 0
end

DoorLockDayOfWeek.set_sunday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SUNDAY
  else
    self.value = self.SUNDAY
  end
end

DoorLockDayOfWeek.unset_sunday = function(self)
  self.value = self.value & (~self.SUNDAY & self.BASE_MASK)
end

DoorLockDayOfWeek.is_monday_set = function(self)
  return (self.value & self.MONDAY) ~= 0
end

DoorLockDayOfWeek.set_monday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MONDAY
  else
    self.value = self.MONDAY
  end
end

DoorLockDayOfWeek.unset_monday = function(self)
  self.value = self.value & (~self.MONDAY & self.BASE_MASK)
end

DoorLockDayOfWeek.is_tuesday_set = function(self)
  return (self.value & self.TUESDAY) ~= 0
end

DoorLockDayOfWeek.set_tuesday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TUESDAY
  else
    self.value = self.TUESDAY
  end
end

DoorLockDayOfWeek.unset_tuesday = function(self)
  self.value = self.value & (~self.TUESDAY & self.BASE_MASK)
end

DoorLockDayOfWeek.is_wednesday_set = function(self)
  return (self.value & self.WEDNESDAY) ~= 0
end

DoorLockDayOfWeek.set_wednesday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.WEDNESDAY
  else
    self.value = self.WEDNESDAY
  end
end

DoorLockDayOfWeek.unset_wednesday = function(self)
  self.value = self.value & (~self.WEDNESDAY & self.BASE_MASK)
end

DoorLockDayOfWeek.is_thursday_set = function(self)
  return (self.value & self.THURSDAY) ~= 0
end

DoorLockDayOfWeek.set_thursday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.THURSDAY
  else
    self.value = self.THURSDAY
  end
end

DoorLockDayOfWeek.unset_thursday = function(self)
  self.value = self.value & (~self.THURSDAY & self.BASE_MASK)
end

DoorLockDayOfWeek.is_friday_set = function(self)
  return (self.value & self.FRIDAY) ~= 0
end

DoorLockDayOfWeek.set_friday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.FRIDAY
  else
    self.value = self.FRIDAY
  end
end

DoorLockDayOfWeek.unset_friday = function(self)
  self.value = self.value & (~self.FRIDAY & self.BASE_MASK)
end

DoorLockDayOfWeek.is_saturday_set = function(self)
  return (self.value & self.SATURDAY) ~= 0
end

DoorLockDayOfWeek.set_saturday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SATURDAY
  else
    self.value = self.SATURDAY
  end
end

DoorLockDayOfWeek.unset_saturday = function(self)
  self.value = self.value & (~self.SATURDAY & self.BASE_MASK)
end

DoorLockDayOfWeek.mask_methods = {
  is_sunday_set = DoorLockDayOfWeek.is_sunday_set,
  set_sunday = DoorLockDayOfWeek.set_sunday,
  unset_sunday = DoorLockDayOfWeek.unset_sunday,
  is_monday_set = DoorLockDayOfWeek.is_monday_set,
  set_monday = DoorLockDayOfWeek.set_monday,
  unset_monday = DoorLockDayOfWeek.unset_monday,
  is_tuesday_set = DoorLockDayOfWeek.is_tuesday_set,
  set_tuesday = DoorLockDayOfWeek.set_tuesday,
  unset_tuesday = DoorLockDayOfWeek.unset_tuesday,
  is_wednesday_set = DoorLockDayOfWeek.is_wednesday_set,
  set_wednesday = DoorLockDayOfWeek.set_wednesday,
  unset_wednesday = DoorLockDayOfWeek.unset_wednesday,
  is_thursday_set = DoorLockDayOfWeek.is_thursday_set,
  set_thursday = DoorLockDayOfWeek.set_thursday,
  unset_thursday = DoorLockDayOfWeek.unset_thursday,
  is_friday_set = DoorLockDayOfWeek.is_friday_set,
  set_friday = DoorLockDayOfWeek.set_friday,
  unset_friday = DoorLockDayOfWeek.unset_friday,
  is_saturday_set = DoorLockDayOfWeek.is_saturday_set,
  set_saturday = DoorLockDayOfWeek.set_saturday,
  unset_saturday = DoorLockDayOfWeek.unset_saturday,
}

DoorLockDayOfWeek.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DoorLockDayOfWeek, new_mt)

return DoorLockDayOfWeek