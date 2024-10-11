local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local TargetDayOfWeekBitmap = {}
local new_mt = UintABC.new_mt({NAME = "TargetDayOfWeekBitmap", ID = data_types.name_to_id_map["Uint8"]}, 1)

TargetDayOfWeekBitmap.BASE_MASK = 0xFFFF
TargetDayOfWeekBitmap.SUNDAY = 0x0001
TargetDayOfWeekBitmap.MONDAY = 0x0002
TargetDayOfWeekBitmap.TUESDAY = 0x0004
TargetDayOfWeekBitmap.WEDNESDAY = 0x0008
TargetDayOfWeekBitmap.THURSDAY = 0x0010
TargetDayOfWeekBitmap.FRIDAY = 0x0020
TargetDayOfWeekBitmap.SATURDAY = 0x0040

TargetDayOfWeekBitmap.mask_fields = {
  BASE_MASK = 0xFFFF,
  SUNDAY = 0x0001,
  MONDAY = 0x0002,
  TUESDAY = 0x0004,
  WEDNESDAY = 0x0008,
  THURSDAY = 0x0010,
  FRIDAY = 0x0020,
  SATURDAY = 0x0040,
}

TargetDayOfWeekBitmap.is_sunday_set = function(self)
  return (self.value & self.SUNDAY) ~= 0
end

TargetDayOfWeekBitmap.set_sunday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SUNDAY
  else
    self.value = self.SUNDAY
  end
end

TargetDayOfWeekBitmap.unset_sunday = function(self)
  self.value = self.value & (~self.SUNDAY & self.BASE_MASK)
end

TargetDayOfWeekBitmap.is_monday_set = function(self)
  return (self.value & self.MONDAY) ~= 0
end

TargetDayOfWeekBitmap.set_monday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MONDAY
  else
    self.value = self.MONDAY
  end
end

TargetDayOfWeekBitmap.unset_monday = function(self)
  self.value = self.value & (~self.MONDAY & self.BASE_MASK)
end

TargetDayOfWeekBitmap.is_tuesday_set = function(self)
  return (self.value & self.TUESDAY) ~= 0
end

TargetDayOfWeekBitmap.set_tuesday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TUESDAY
  else
    self.value = self.TUESDAY
  end
end

TargetDayOfWeekBitmap.unset_tuesday = function(self)
  self.value = self.value & (~self.TUESDAY & self.BASE_MASK)
end

TargetDayOfWeekBitmap.is_wednesday_set = function(self)
  return (self.value & self.WEDNESDAY) ~= 0
end

TargetDayOfWeekBitmap.set_wednesday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.WEDNESDAY
  else
    self.value = self.WEDNESDAY
  end
end

TargetDayOfWeekBitmap.unset_wednesday = function(self)
  self.value = self.value & (~self.WEDNESDAY & self.BASE_MASK)
end

TargetDayOfWeekBitmap.is_thursday_set = function(self)
  return (self.value & self.THURSDAY) ~= 0
end

TargetDayOfWeekBitmap.set_thursday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.THURSDAY
  else
    self.value = self.THURSDAY
  end
end

TargetDayOfWeekBitmap.unset_thursday = function(self)
  self.value = self.value & (~self.THURSDAY & self.BASE_MASK)
end

TargetDayOfWeekBitmap.is_friday_set = function(self)
  return (self.value & self.FRIDAY) ~= 0
end

TargetDayOfWeekBitmap.set_friday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.FRIDAY
  else
    self.value = self.FRIDAY
  end
end

TargetDayOfWeekBitmap.unset_friday = function(self)
  self.value = self.value & (~self.FRIDAY & self.BASE_MASK)
end

TargetDayOfWeekBitmap.is_saturday_set = function(self)
  return (self.value & self.SATURDAY) ~= 0
end

TargetDayOfWeekBitmap.set_saturday = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SATURDAY
  else
    self.value = self.SATURDAY
  end
end

TargetDayOfWeekBitmap.unset_saturday = function(self)
  self.value = self.value & (~self.SATURDAY & self.BASE_MASK)
end


TargetDayOfWeekBitmap.mask_methods = {
  is_sunday_set = TargetDayOfWeekBitmap.is_sunday_set,
  set_sunday = TargetDayOfWeekBitmap.set_sunday,
  unset_sunday = TargetDayOfWeekBitmap.unset_sunday,
  is_monday_set = TargetDayOfWeekBitmap.is_monday_set,
  set_monday = TargetDayOfWeekBitmap.set_monday,
  unset_monday = TargetDayOfWeekBitmap.unset_monday,
  is_tuesday_set = TargetDayOfWeekBitmap.is_tuesday_set,
  set_tuesday = TargetDayOfWeekBitmap.set_tuesday,
  unset_tuesday = TargetDayOfWeekBitmap.unset_tuesday,
  is_wednesday_set = TargetDayOfWeekBitmap.is_wednesday_set,
  set_wednesday = TargetDayOfWeekBitmap.set_wednesday,
  unset_wednesday = TargetDayOfWeekBitmap.unset_wednesday,
  is_thursday_set = TargetDayOfWeekBitmap.is_thursday_set,
  set_thursday = TargetDayOfWeekBitmap.set_thursday,
  unset_thursday = TargetDayOfWeekBitmap.unset_thursday,
  is_friday_set = TargetDayOfWeekBitmap.is_friday_set,
  set_friday = TargetDayOfWeekBitmap.set_friday,
  unset_friday = TargetDayOfWeekBitmap.unset_friday,
  is_saturday_set = TargetDayOfWeekBitmap.is_saturday_set,
  set_saturday = TargetDayOfWeekBitmap.set_saturday,
  unset_saturday = TargetDayOfWeekBitmap.unset_saturday,
}

TargetDayOfWeekBitmap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(TargetDayOfWeekBitmap, new_mt)

return TargetDayOfWeekBitmap

