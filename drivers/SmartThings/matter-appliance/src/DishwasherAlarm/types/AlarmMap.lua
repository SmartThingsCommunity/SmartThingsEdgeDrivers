local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AlarmMap = {}
local new_mt = UintABC.new_mt({NAME = "AlarmMap", ID = data_types.name_to_id_map["Uint32"]}, 4)

AlarmMap.BASE_MASK = 0xFFFF
AlarmMap.INFLOW_ERROR = 0x0001
AlarmMap.DRAIN_ERROR = 0x0002
AlarmMap.DOOR_ERROR = 0x0004
AlarmMap.TEMP_TOO_LOW = 0x0008
AlarmMap.TEMP_TOO_HIGH = 0x0010
AlarmMap.WATER_LEVEL_ERROR = 0x0020

AlarmMap.mask_fields = {
  BASE_MASK = 0xFFFF,
  INFLOW_ERROR = 0x0001,
  DRAIN_ERROR = 0x0002,
  DOOR_ERROR = 0x0004,
  TEMP_TOO_LOW = 0x0008,
  TEMP_TOO_HIGH = 0x0010,
  WATER_LEVEL_ERROR = 0x0020,
}

AlarmMap.is_inflow_error_set = function(self)
  return (self.value & self.INFLOW_ERROR) ~= 0
end

AlarmMap.set_inflow_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.INFLOW_ERROR
  else
    self.value = self.INFLOW_ERROR
  end
end

AlarmMap.unset_inflow_error = function(self)
  self.value = self.value & (~self.INFLOW_ERROR & self.BASE_MASK)
end

AlarmMap.is_drain_error_set = function(self)
  return (self.value & self.DRAIN_ERROR) ~= 0
end

AlarmMap.set_drain_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DRAIN_ERROR
  else
    self.value = self.DRAIN_ERROR
  end
end

AlarmMap.unset_drain_error = function(self)
  self.value = self.value & (~self.DRAIN_ERROR & self.BASE_MASK)
end

AlarmMap.is_door_error_set = function(self)
  return (self.value & self.DOOR_ERROR) ~= 0
end

AlarmMap.set_door_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DOOR_ERROR
  else
    self.value = self.DOOR_ERROR
  end
end

AlarmMap.unset_door_error = function(self)
  self.value = self.value & (~self.DOOR_ERROR & self.BASE_MASK)
end
AlarmMap.is_temp_too_low_set = function(self)
  return (self.value & self.TEMP_TOO_LOW) ~= 0
end

AlarmMap.set_temp_too_low = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TEMP_TOO_LOW
  else
    self.value = self.TEMP_TOO_LOW
  end
end

AlarmMap.unset_temp_too_low = function(self)
  self.value = self.value & (~self.TEMP_TOO_LOW & self.BASE_MASK)
end

AlarmMap.is_temp_too_high_set = function(self)
  return (self.value & self.TEMP_TOO_HIGH) ~= 0
end

AlarmMap.set_temp_too_high = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TEMP_TOO_HIGH
  else
    self.value = self.TEMP_TOO_HIGH
  end
end

AlarmMap.unset_temp_too_high = function(self)
  self.value = self.value & (~self.TEMP_TOO_HIGH & self.BASE_MASK)
end

AlarmMap.is_water_level_error_set = function(self)
  return (self.value & self.WATER_LEVEL_ERROR) ~= 0
end

AlarmMap.set_water_level_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.WATER_LEVEL_ERROR
  else
    self.value = self.WATER_LEVEL_ERROR
  end
end

AlarmMap.unset_water_level_error = function(self)
  self.value = self.value & (~self.WATER_LEVEL_ERROR & self.BASE_MASK)
end


AlarmMap.mask_methods = {
  is_inflow_error_set = AlarmMap.is_inflow_error_set,
  set_inflow_error = AlarmMap.set_inflow_error,
  unset_inflow_error = AlarmMap.unset_inflow_error,
  is_drain_error_set = AlarmMap.is_drain_error_set,
  set_drain_error = AlarmMap.set_drain_error,
  unset_drain_error = AlarmMap.unset_drain_error,
  is_door_error_set = AlarmMap.is_door_error_set,
  set_door_error = AlarmMap.set_door_error,
  unset_door_error = AlarmMap.unset_door_error,
  is_temp_too_low_set = AlarmMap.is_temp_too_low_set,
  set_temp_too_low = AlarmMap.set_temp_too_low,
  unset_temp_too_low = AlarmMap.unset_temp_too_low,
  is_temp_too_high_set = AlarmMap.is_temp_too_high_set,
  set_temp_too_high = AlarmMap.set_temp_too_high,
  unset_temp_too_high = AlarmMap.unset_temp_too_high,
  is_water_level_error_set = AlarmMap.is_water_level_error_set,
  set_water_level_error = AlarmMap.set_water_level_error,
  unset_water_level_error = AlarmMap.unset_water_level_error,
}

AlarmMap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(AlarmMap, new_mt)

return AlarmMap

