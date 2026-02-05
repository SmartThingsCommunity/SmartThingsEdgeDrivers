local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.POSITIONING = 0x0001
Feature.MOTION_LATCHING = 0x0002
Feature.INSTANTANEOUS = 0x0004
Feature.SPEED = 0x0008
Feature.VENTILATION = 0x0010
Feature.PEDESTRIAN = 0x0020
Feature.CALIBRATION = 0x0040
Feature.PROTECTION = 0x0080
Feature.MANUALLY_OPERABLE = 0x0100

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  POSITIONING = 0x0001,
  MOTION_LATCHING = 0x0002,
  INSTANTANEOUS = 0x0004,
  SPEED = 0x0008,
  VENTILATION = 0x0010,
  PEDESTRIAN = 0x0020,
  CALIBRATION = 0x0040,
  PROTECTION = 0x0080,
  MANUALLY_OPERABLE = 0x0100,
}

Feature.is_positioning_set = function(self)
  return (self.value & self.POSITIONING) ~= 0
end

Feature.set_positioning = function(self)
  if self.value ~= nil then
    self.value = self.value | self.POSITIONING
  else
    self.value = self.POSITIONING
  end
end

Feature.unset_positioning = function(self)
  self.value = self.value & (~self.POSITIONING & self.BASE_MASK)
end
Feature.is_motion_latching_set = function(self)
  return (self.value & self.MOTION_LATCHING) ~= 0
end

Feature.set_motion_latching = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MOTION_LATCHING
  else
    self.value = self.MOTION_LATCHING
  end
end

Feature.unset_motion_latching = function(self)
  self.value = self.value & (~self.MOTION_LATCHING & self.BASE_MASK)
end

Feature.is_instantaneous_set = function(self)
  return (self.value & self.INSTANTANEOUS) ~= 0
end

Feature.set_instantaneous = function(self)
  if self.value ~= nil then
    self.value = self.value | self.INSTANTANEOUS
  else
    self.value = self.INSTANTANEOUS
  end
end

Feature.unset_instantaneous = function(self)
  self.value = self.value & (~self.INSTANTANEOUS & self.BASE_MASK)
end

Feature.is_speed_set = function(self)
  return (self.value & self.SPEED) ~= 0
end

Feature.set_speed = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SPEED
  else
    self.value = self.SPEED
  end
end

Feature.unset_speed = function(self)
  self.value = self.value & (~self.SPEED & self.BASE_MASK)
end

Feature.is_ventilation_set = function(self)
  return (self.value & self.VENTILATION) ~= 0
end

Feature.set_ventilation = function(self)
  if self.value ~= nil then
    self.value = self.value | self.VENTILATION
  else
    self.value = self.VENTILATION
  end
end

Feature.unset_ventilation = function(self)
  self.value = self.value & (~self.VENTILATION & self.BASE_MASK)
end

Feature.is_pedestrian_set = function(self)
  return (self.value & self.PEDESTRIAN) ~= 0
end

Feature.set_pedestrian = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PEDESTRIAN
  else
    self.value = self.PEDESTRIAN
  end
end

Feature.unset_pedestrian = function(self)
  self.value = self.value & (~self.PEDESTRIAN & self.BASE_MASK)
end

Feature.is_calibration_set = function(self)
  return (self.value & self.CALIBRATION) ~= 0
end

Feature.set_calibration = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CALIBRATION
  else
    self.value = self.CALIBRATION
  end
end

Feature.unset_calibration = function(self)
  self.value = self.value & (~self.CALIBRATION & self.BASE_MASK)
end

Feature.is_protection_set = function(self)
  return (self.value & self.PROTECTION) ~= 0
end

Feature.set_protection = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PROTECTION
  else
    self.value = self.PROTECTION
  end
end

Feature.unset_protection = function(self)
  self.value = self.value & (~self.PROTECTION & self.BASE_MASK)
end

Feature.is_manually_operable_set = function(self)
  return (self.value & self.MANUALLY_OPERABLE) ~= 0
end

Feature.set_manually_operable = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MANUALLY_OPERABLE
  else
    self.value = self.MANUALLY_OPERABLE
  end
end

Feature.unset_manually_operable = function(self)
  self.value = self.value & (~self.MANUALLY_OPERABLE & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.POSITIONING |
    Feature.MOTION_LATCHING |
    Feature.INSTANTANEOUS |
    Feature.SPEED |
    Feature.VENTILATION |
    Feature.PEDESTRIAN |
    Feature.CALIBRATION |
    Feature.PROTECTION |
    Feature.MANUALLY_OPERABLE
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_positioning_set = Feature.is_positioning_set,
  set_positioning = Feature.set_positioning,
  unset_positioning = Feature.unset_positioning,
  is_motion_latching_set = Feature.is_motion_latching_set,
  set_motion_latching = Feature.set_motion_latching,
  unset_motion_latching = Feature.unset_motion_latching,
  is_instantaneous_set = Feature.is_instantaneous_set,
  set_instantaneous = Feature.set_instantaneous,
  unset_instantaneous = Feature.unset_instantaneous,
  is_speed_set = Feature.is_speed_set,
  set_speed = Feature.set_speed,
  unset_speed = Feature.unset_speed,
  is_ventilation_set = Feature.is_ventilation_set,
  set_ventilation = Feature.set_ventilation,
  unset_ventilation = Feature.unset_ventilation,
  is_pedestrian_set = Feature.is_pedestrian_set,
  set_pedestrian = Feature.set_pedestrian,
  unset_pedestrian = Feature.unset_pedestrian,
  is_calibration_set = Feature.is_calibration_set,
  set_calibration = Feature.set_calibration,
  unset_calibration = Feature.unset_calibration,
  is_protection_set = Feature.is_protection_set,
  set_protection = Feature.set_protection,
  unset_protection = Feature.unset_protection,
  is_manually_operable_set = Feature.is_manually_operable_set,
  set_manually_operable = Feature.set_manually_operable,
  unset_manually_operable = Feature.unset_manually_operable,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
