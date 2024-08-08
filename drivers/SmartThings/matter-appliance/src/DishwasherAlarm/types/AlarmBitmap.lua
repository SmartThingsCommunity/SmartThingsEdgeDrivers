local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local AlarmBitmap = {}
local new_mt = UintABC.new_mt({NAME = "AlarmBitmap", ID = data_types.name_to_id_map["Uint32"]}, 4)

AlarmBitmap.BASE_MASK = 0xFFFF
AlarmBitmap.INFLOW_ERROR = 0x0001
AlarmBitmap.DRAIN_ERROR = 0x0002
AlarmBitmap.DOOR_ERROR = 0x0004
AlarmBitmap.TEMP_TOO_LOW = 0x0008
AlarmBitmap.TEMP_TOO_HIGH = 0x0010
AlarmBitmap.WATER_LEVEL_ERROR = 0x0020

AlarmBitmap.mask_fields = {
  BASE_MASK = 0xFFFF,
  INFLOW_ERROR = 0x0001,
  DRAIN_ERROR = 0x0002,
  DOOR_ERROR = 0x0004,
  TEMP_TOO_LOW = 0x0008,
  TEMP_TOO_HIGH = 0x0010,
  WATER_LEVEL_ERROR = 0x0020,
}

AlarmBitmap.is_inflow_error_set = function(self)
  return (self.value & self.INFLOW_ERROR) ~= 0
end

AlarmBitmap.set_inflow_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.INFLOW_ERROR
  else
    self.value = self.INFLOW_ERROR
  end
end

AlarmBitmap.unset_inflow_error = function(self)
  self.value = self.value & (~self.INFLOW_ERROR & self.BASE_MASK)
end

AlarmBitmap.is_drain_error_set = function(self)
  return (self.value & self.DRAIN_ERROR) ~= 0
end

AlarmBitmap.set_drain_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DRAIN_ERROR
  else
    self.value = self.DRAIN_ERROR
  end
end

AlarmBitmap.unset_drain_error = function(self)
  self.value = self.value & (~self.DRAIN_ERROR & self.BASE_MASK)
end

AlarmBitmap.is_door_error_set = function(self)
  return (self.value & self.DOOR_ERROR) ~= 0
end

AlarmBitmap.set_door_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DOOR_ERROR
  else
    self.value = self.DOOR_ERROR
  end
end

AlarmBitmap.unset_door_error = function(self)
  self.value = self.value & (~self.DOOR_ERROR & self.BASE_MASK)
end

AlarmBitmap.is_temp_too_low_set = function(self)
  return (self.value & self.TEMP_TOO_LOW) ~= 0
end

AlarmBitmap.set_temp_too_low = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TEMP_TOO_LOW
  else
    self.value = self.TEMP_TOO_LOW
  end
end

AlarmBitmap.unset_temp_too_low = function(self)
  self.value = self.value & (~self.TEMP_TOO_LOW & self.BASE_MASK)
end

AlarmBitmap.is_temp_too_high_set = function(self)
  return (self.value & self.TEMP_TOO_HIGH) ~= 0
end

AlarmBitmap.set_temp_too_high = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TEMP_TOO_HIGH
  else
    self.value = self.TEMP_TOO_HIGH
  end
end

AlarmBitmap.unset_temp_too_high = function(self)
  self.value = self.value & (~self.TEMP_TOO_HIGH & self.BASE_MASK)
end

AlarmBitmap.is_water_level_error_set = function(self)
  return (self.value & self.WATER_LEVEL_ERROR) ~= 0
end

AlarmBitmap.set_water_level_error = function(self)
  if self.value ~= nil then
    self.value = self.value | self.WATER_LEVEL_ERROR
  else
    self.value = self.WATER_LEVEL_ERROR
  end
end

AlarmBitmap.unset_water_level_error = function(self)
  self.value = self.value & (~self.WATER_LEVEL_ERROR & self.BASE_MASK)
end


AlarmBitmap.mask_methods = {
  is_inflow_error_set = AlarmBitmap.is_inflow_error_set,
  set_inflow_error = AlarmBitmap.set_inflow_error,
  unset_inflow_error = AlarmBitmap.unset_inflow_error,
  is_drain_error_set = AlarmBitmap.is_drain_error_set,
  set_drain_error = AlarmBitmap.set_drain_error,
  unset_drain_error = AlarmBitmap.unset_drain_error,
  is_door_error_set = AlarmBitmap.is_door_error_set,
  set_door_error = AlarmBitmap.set_door_error,
  unset_door_error = AlarmBitmap.unset_door_error,
  is_temp_too_low_set = AlarmBitmap.is_temp_too_low_set,
  set_temp_too_low = AlarmBitmap.set_temp_too_low,
  unset_temp_too_low = AlarmBitmap.unset_temp_too_low,
  is_temp_too_high_set = AlarmBitmap.is_temp_too_high_set,
  set_temp_too_high = AlarmBitmap.set_temp_too_high,
  unset_temp_too_high = AlarmBitmap.unset_temp_too_high,
  is_water_level_error_set = AlarmBitmap.is_water_level_error_set,
  set_water_level_error = AlarmBitmap.set_water_level_error,
  unset_water_level_error = AlarmBitmap.unset_water_level_error,
}

AlarmBitmap.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(AlarmBitmap, new_mt)

local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.DishwasherAlarm.types.AlarmBitmap")
if has_aliases then
  aliases:add_to_class(AlarmBitmap)
end

return AlarmBitmap

