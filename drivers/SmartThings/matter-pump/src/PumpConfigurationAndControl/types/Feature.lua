local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.CONSTANT_PRESSURE = 0x0001
Feature.COMPENSATED_PRESSURE = 0x0002
Feature.CONSTANT_FLOW = 0x0004
Feature.CONSTANT_SPEED = 0x0008
Feature.CONSTANT_TEMPERATURE = 0x0010
Feature.AUTOMATIC = 0x0020
Feature.LOCAL_OPERATION = 0x0040

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  CONSTANT_PRESSURE = 0x0001,
  COMPENSATED_PRESSURE = 0x0002,
  CONSTANT_FLOW = 0x0004,
  CONSTANT_SPEED = 0x0008,
  CONSTANT_TEMPERATURE = 0x0010,
  AUTOMATIC = 0x0020,
  LOCAL_OPERATION = 0x0040,
}

Feature.is_constant_pressure_set = function(self)
  return (self.value & self.CONSTANT_PRESSURE) ~= 0
end

Feature.set_constant_pressure = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CONSTANT_PRESSURE
  else
    self.value = self.CONSTANT_PRESSURE
  end
end

Feature.unset_constant_pressure = function(self)
  self.value = self.value & (~self.CONSTANT_PRESSURE & self.BASE_MASK)
end

Feature.is_compensated_pressure_set = function(self)
  return (self.value & self.COMPENSATED_PRESSURE) ~= 0
end

Feature.set_compensated_pressure = function(self)
  if self.value ~= nil then
    self.value = self.value | self.COMPENSATED_PRESSURE
  else
    self.value = self.COMPENSATED_PRESSURE
  end
end

Feature.unset_compensated_pressure = function(self)
  self.value = self.value & (~self.COMPENSATED_PRESSURE & self.BASE_MASK)
end

Feature.is_constant_flow_set = function(self)
  return (self.value & self.CONSTANT_FLOW) ~= 0
end

Feature.set_constant_flow = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CONSTANT_FLOW
  else
    self.value = self.CONSTANT_FLOW
  end
end

Feature.unset_constant_flow = function(self)
  self.value = self.value & (~self.CONSTANT_FLOW & self.BASE_MASK)
end

Feature.is_constant_speed_set = function(self)
  return (self.value & self.CONSTANT_SPEED) ~= 0
end

Feature.set_constant_speed = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CONSTANT_SPEED
  else
    self.value = self.CONSTANT_SPEED
  end
end

Feature.unset_constant_speed = function(self)
  self.value = self.value & (~self.CONSTANT_SPEED & self.BASE_MASK)
end

Feature.is_constant_temperature_set = function(self)
  return (self.value & self.CONSTANT_TEMPERATURE) ~= 0
end

Feature.set_constant_temperature = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CONSTANT_TEMPERATURE
  else
    self.value = self.CONSTANT_TEMPERATURE
  end
end

Feature.unset_constant_temperature = function(self)
  self.value = self.value & (~self.CONSTANT_TEMPERATURE & self.BASE_MASK)
end

Feature.is_automatic_set = function(self)
  return (self.value & self.AUTOMATIC) ~= 0
end

Feature.set_automatic = function(self)
  if self.value ~= nil then
    self.value = self.value | self.AUTOMATIC
  else
    self.value = self.AUTOMATIC
  end
end

Feature.unset_automatic = function(self)
  self.value = self.value & (~self.AUTOMATIC & self.BASE_MASK)
end

Feature.is_local_operation_set = function(self)
  return (self.value & self.LOCAL_OPERATION) ~= 0
end

Feature.set_local_operation = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LOCAL_OPERATION
  else
    self.value = self.LOCAL_OPERATION
  end
end

Feature.unset_local_operation = function(self)
  self.value = self.value & (~self.LOCAL_OPERATION & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.CONSTANT_PRESSURE |
    Feature.COMPENSATED_PRESSURE |
    Feature.CONSTANT_FLOW |
    Feature.CONSTANT_SPEED |
    Feature.CONSTANT_TEMPERATURE |
    Feature.AUTOMATIC |
    Feature.LOCAL_OPERATION
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_constant_pressure_set = Feature.is_constant_pressure_set,
  set_constant_pressure = Feature.set_constant_pressure,
  unset_constant_pressure = Feature.unset_constant_pressure,
  is_compensated_pressure_set = Feature.is_compensated_pressure_set,
  set_compensated_pressure = Feature.set_compensated_pressure,
  unset_compensated_pressure = Feature.unset_compensated_pressure,
  is_constant_flow_set = Feature.is_constant_flow_set,
  set_constant_flow = Feature.set_constant_flow,
  unset_constant_flow = Feature.unset_constant_flow,
  is_constant_speed_set = Feature.is_constant_speed_set,
  set_constant_speed = Feature.set_constant_speed,
  unset_constant_speed = Feature.unset_constant_speed,
  is_constant_temperature_set = Feature.is_constant_temperature_set,
  set_constant_temperature = Feature.set_constant_temperature,
  unset_constant_temperature = Feature.unset_constant_temperature,
  is_automatic_set = Feature.is_automatic_set,
  set_automatic = Feature.set_automatic,
  unset_automatic = Feature.unset_automatic,
  is_local_operation_set = Feature.is_local_operation_set,
  set_local_operation = Feature.set_local_operation,
  unset_local_operation = Feature.unset_local_operation,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
