local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.NUMERIC_MEASUREMENT = 0x0001
Feature.LEVEL_INDICATION = 0x0002
Feature.MEDIUM_LEVEL = 0x0004
Feature.CRITICAL_LEVEL = 0x0008
Feature.PEAK_MEASUREMENT = 0x0010
Feature.AVERAGE_MEASUREMENT = 0x0020

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  NUMERIC_MEASUREMENT = 0x0001,
  LEVEL_INDICATION = 0x0002,
  MEDIUM_LEVEL = 0x0004,
  CRITICAL_LEVEL = 0x0008,
  PEAK_MEASUREMENT = 0x0010,
  AVERAGE_MEASUREMENT = 0x0020,
}

Feature.is_numeric_measurement_set = function(self)
  return (self.value & self.NUMERIC_MEASUREMENT) ~= 0
end

Feature.set_numeric_measurement = function(self)
  if self.value ~= nil then
    self.value = self.value | self.NUMERIC_MEASUREMENT
  else
    self.value = self.NUMERIC_MEASUREMENT
  end
end

Feature.unset_numeric_measurement = function(self)
  self.value = self.value & (~self.NUMERIC_MEASUREMENT & self.BASE_MASK)
end

Feature.is_level_indication_set = function(self)
  return (self.value & self.LEVEL_INDICATION) ~= 0
end

Feature.set_level_indication = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LEVEL_INDICATION
  else
    self.value = self.LEVEL_INDICATION
  end
end

Feature.unset_level_indication = function(self)
  self.value = self.value & (~self.LEVEL_INDICATION & self.BASE_MASK)
end

Feature.is_medium_level_set = function(self)
  return (self.value & self.MEDIUM_LEVEL) ~= 0
end

Feature.set_medium_level = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MEDIUM_LEVEL
  else
    self.value = self.MEDIUM_LEVEL
  end
end

Feature.unset_medium_level = function(self)
  self.value = self.value & (~self.MEDIUM_LEVEL & self.BASE_MASK)
end

Feature.is_critical_level_set = function(self)
  return (self.value & self.CRITICAL_LEVEL) ~= 0
end

Feature.set_critical_level = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CRITICAL_LEVEL
  else
    self.value = self.CRITICAL_LEVEL
  end
end

Feature.unset_critical_level = function(self)
  self.value = self.value & (~self.CRITICAL_LEVEL & self.BASE_MASK)
end

Feature.is_peak_measurement_set = function(self)
  return (self.value & self.PEAK_MEASUREMENT) ~= 0
end

Feature.set_peak_measurement = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PEAK_MEASUREMENT
  else
    self.value = self.PEAK_MEASUREMENT
  end
end

Feature.unset_peak_measurement = function(self)
  self.value = self.value & (~self.PEAK_MEASUREMENT & self.BASE_MASK)
end

Feature.is_average_measurement_set = function(self)
  return (self.value & self.AVERAGE_MEASUREMENT) ~= 0
end

Feature.set_average_measurement = function(self)
  if self.value ~= nil then
    self.value = self.value | self.AVERAGE_MEASUREMENT
  else
    self.value = self.AVERAGE_MEASUREMENT
  end
end

Feature.unset_average_measurement = function(self)
  self.value = self.value & (~self.AVERAGE_MEASUREMENT & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.NUMERIC_MEASUREMENT |
    Feature.LEVEL_INDICATION |
    Feature.MEDIUM_LEVEL |
    Feature.CRITICAL_LEVEL |
    Feature.PEAK_MEASUREMENT |
    Feature.AVERAGE_MEASUREMENT
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_numeric_measurement_set = Feature.is_numeric_measurement_set,
  set_numeric_measurement = Feature.set_numeric_measurement,
  unset_numeric_measurement = Feature.unset_numeric_measurement,
  is_level_indication_set = Feature.is_level_indication_set,
  set_level_indication = Feature.set_level_indication,
  unset_level_indication = Feature.unset_level_indication,
  is_medium_level_set = Feature.is_medium_level_set,
  set_medium_level = Feature.set_medium_level,
  unset_medium_level = Feature.unset_medium_level,
  is_critical_level_set = Feature.is_critical_level_set,
  set_critical_level = Feature.set_critical_level,
  unset_critical_level = Feature.unset_critical_level,
  is_peak_measurement_set = Feature.is_peak_measurement_set,
  set_peak_measurement = Feature.set_peak_measurement,
  unset_peak_measurement = Feature.unset_peak_measurement,
  is_average_measurement_set = Feature.is_average_measurement_set,
  set_average_measurement = Feature.set_average_measurement,
  unset_average_measurement = Feature.unset_average_measurement,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

