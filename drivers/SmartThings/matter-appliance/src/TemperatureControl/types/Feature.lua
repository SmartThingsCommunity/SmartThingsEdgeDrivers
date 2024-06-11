local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.TEMPERATURE_NUMBER = 0x0001
Feature.TEMPERATURE_LEVEL = 0x0002
Feature.TEMPERATURE_STEP = 0x0004

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  TEMPERATURE_NUMBER = 0x0001,
  TEMPERATURE_LEVEL = 0x0002,
  TEMPERATURE_STEP = 0x0004,
}

Feature.is_temperature_number_set = function(self)
  return (self.value & self.TEMPERATURE_NUMBER) ~= 0
end

Feature.set_temperature_number = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TEMPERATURE_NUMBER
  else
    self.value = self.TEMPERATURE_NUMBER
  end
end

Feature.unset_temperature_number = function(self)
  self.value = self.value & (~self.TEMPERATURE_NUMBER & self.BASE_MASK)
end

Feature.is_temperature_level_set = function(self)
  return (self.value & self.TEMPERATURE_LEVEL) ~= 0
end

Feature.set_temperature_level = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TEMPERATURE_LEVEL
  else
    self.value = self.TEMPERATURE_LEVEL
  end
end

Feature.unset_temperature_level = function(self)
  self.value = self.value & (~self.TEMPERATURE_LEVEL & self.BASE_MASK)
end

Feature.is_temperature_step_set = function(self)
  return (self.value & self.TEMPERATURE_STEP) ~= 0
end

Feature.set_temperature_step = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TEMPERATURE_STEP
  else
    self.value = self.TEMPERATURE_STEP
  end
end

Feature.unset_temperature_step = function(self)
  self.value = self.value & (~self.TEMPERATURE_STEP & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.TEMPERATURE_NUMBER |
    Feature.TEMPERATURE_LEVEL |
    Feature.TEMPERATURE_STEP
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_temperature_number_set = Feature.is_temperature_number_set,
  set_temperature_number = Feature.set_temperature_number,
  unset_temperature_number = Feature.unset_temperature_number,
  is_temperature_level_set = Feature.is_temperature_level_set,
  set_temperature_level = Feature.set_temperature_level,
  unset_temperature_level = Feature.unset_temperature_level,
  is_temperature_step_set = Feature.is_temperature_step_set,
  set_temperature_step = Feature.set_temperature_step,
  unset_temperature_step = Feature.unset_temperature_step,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
