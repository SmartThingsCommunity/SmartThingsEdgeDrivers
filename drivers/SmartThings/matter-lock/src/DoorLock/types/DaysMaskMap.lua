local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local DaysMaskMap = {}
local new_mt = UintABC.new_mt({NAME = "DaysMaskMap", ID = data_types.name_to_id_map["Uint8"]}, 1)

DaysMaskMap.BASE_MASK = 0xFFFF
DaysMaskMap.SUNDAY = 0x0001
DaysMaskMap.MONDAY = 0x0002
DaysMaskMap.TUESDAY = 0x0004
DaysMaskMap.WEDNESDAY = 0x0008
DaysMaskMap.THURSDAY = 0x0010
DaysMaskMap.FRIDAY = 0x0020
DaysMaskMap.SATURDAY = 0x0040

DaysMaskMap.mask_fields = {
  BASE_MASK = 0xFFFF,
  SUNDAY = 0x0001,
  MONDAY = 0x0002,
  TUESDAY = 0x0004,
  WEDNESDAY = 0x0008,
  THURSDAY = 0x0010,
  FRIDAY = 0x0020,
  SATURDAY = 0x0040,
}

DaysMaskMap.is_sunday_set = function(self)
  return (self.value & self.SUNDAY) ~= 0
end

DaysMaskMap.set_sunday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SUNDAY
  else
    self.value = self.SUNDAY
  end
end

DaysMaskMap.unset_sunday = function(self)
  self.value = self.value & (~self.SUNDAY & self.BASE_MASK)
end

DaysMaskMap.is_monday_set = function(self)
  return (self.value & self.MONDAY) ~= 0
end

DaysMaskMap.set_monday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MONDAY
  else
    self.value = self.MONDAY
  end
end

DaysMaskMap.unset_monday = function(self)
  self.value = self.value & (~self.MONDAY & self.BASE_MASK)
end

DaysMaskMap.is_tuesday_set = function(self)
  return (self.value & self.TUESDAY) ~= 0
end

DaysMaskMap.set_tuesday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TUESDAY
  else
    self.value = self.TUESDAY
  end
end

DaysMaskMap.unset_tuesday = function(self)
  self.value = self.value & (~self.TUESDAY & self.BASE_MASK)
end

DaysMaskMap.is_wednesday_set = function(self)
  return (self.value & self.WEDNESDAY) ~= 0
end

DaysMaskMap.set_wednesday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.WEDNESDAY
  else
    self.value = self.WEDNESDAY
  end
end

DaysMaskMap.unset_wednesday = function(self)
  self.value = self.value & (~self.WEDNESDAY & self.BASE_MASK)
end

DaysMaskMap.is_thursday_set = function(self)
  return (self.value & self.THURSDAY) ~= 0
end

DaysMaskMap.set_thursday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.THURSDAY
  else
    self.value = self.THURSDAY
  end
end

DaysMaskMap.unset_thursday = function(self)
  self.value = self.value & (~self.THURSDAY & self.BASE_MASK)
end

DaysMaskMap.is_friday_set = function(self)
  return (self.value & self.FRIDAY) ~= 0
end

DaysMaskMap.set_friday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.FRIDAY
  else
    self.value = self.FRIDAY
  end
end

DaysMaskMap.unset_friday = function(self)
  self.value = self.value & (~self.FRIDAY & self.BASE_MASK)
end

DaysMaskMap.is_saturday_set = function(self)
  return (self.value & self.SATURDAY) ~= 0
end

DaysMaskMap.set_saturday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SATURDAY
  else
    self.value = self.SATURDAY
  end
end

DaysMaskMap.unset_saturday = function(self)
  self.value = self.value & (~self.SATURDAY & self.BASE_MASK)
end

DaysMaskMap.mask_methods = {
  is_sunday_set = DaysMaskMap.is_sunday_set,
  set_sunday = DaysMaskMap.set_sunday,
  unset_sunday = DaysMaskMap.unset_sunday,
  is_monday_set = DaysMaskMap.is_monday_set,
  set_monday = DaysMaskMap.set_monday,
  unset_monday = DaysMaskMap.unset_monday,
  is_tuesday_set = DaysMaskMap.is_tuesday_set,
  set_tuesday = DaysMaskMap.set_tuesday,
  unset_tuesday = DaysMaskMap.unset_tuesday,
  is_wednesday_set = DaysMaskMap.is_wednesday_set,
  set_wednesday = DaysMaskMap.set_wednesday,
  unset_wednesday = DaysMaskMap.unset_wednesday,
  is_thursday_set = DaysMaskMap.is_thursday_set,
  set_thursday = DaysMaskMap.set_thursday,
  unset_thursday = DaysMaskMap.unset_thursday,
  is_friday_set = DaysMaskMap.is_friday_set,
  set_friday = DaysMaskMap.set_friday,
  unset_friday = DaysMaskMap.unset_friday,
  is_saturday_set = DaysMaskMap.is_saturday_set,
  set_saturday = DaysMaskMap.set_saturday,
  unset_saturday = DaysMaskMap.unset_saturday,
}

DaysMaskMap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(DaysMaskMap, new_mt)

return DaysMaskMap