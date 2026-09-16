local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.POSITIONING = 0x0001
Feature.MOTION_LATCHING = 0x0002
Feature.UNIT = 0x0004
Feature.LIMITATION = 0x0008
Feature.SPEED = 0x0010
Feature.TRANSLATION = 0x0020
Feature.ROTATION = 0x0040
Feature.MODULATION = 0x0080

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  POSITIONING = 0x0001,
  MOTION_LATCHING = 0x0002,
  UNIT = 0x0004,
  LIMITATION = 0x0008,
  SPEED = 0x0010,
  TRANSLATION = 0x0020,
  ROTATION = 0x0040,
  MODULATION = 0x0080,
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

Feature.is_unit_set = function(self)
  return (self.value & self.UNIT) ~= 0
end

Feature.set_unit = function(self)
  if self.value ~= nil then
    self.value = self.value | self.UNIT
  else
    self.value = self.UNIT
  end
end

Feature.unset_unit = function(self)
  self.value = self.value & (~self.UNIT & self.BASE_MASK)
end

Feature.is_limitation_set = function(self)
  return (self.value & self.LIMITATION) ~= 0
end

Feature.set_limitation = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LIMITATION
  else
    self.value = self.LIMITATION
  end
end

Feature.unset_limitation = function(self)
  self.value = self.value & (~self.LIMITATION & self.BASE_MASK)
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

Feature.is_translation_set = function(self)
  return (self.value & self.TRANSLATION) ~= 0
end

Feature.set_translation = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TRANSLATION
  else
    self.value = self.TRANSLATION
  end
end

Feature.unset_translation = function(self)
  self.value = self.value & (~self.TRANSLATION & self.BASE_MASK)
end

Feature.is_rotation_set = function(self)
  return (self.value & self.ROTATION) ~= 0
end

Feature.set_rotation = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ROTATION
  else
    self.value = self.ROTATION
  end
end

Feature.unset_rotation = function(self)
  self.value = self.value & (~self.ROTATION & self.BASE_MASK)
end

Feature.is_modulation_set = function(self)
  return (self.value & self.MODULATION) ~= 0
end

Feature.set_modulation = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MODULATION
  else
    self.value = self.MODULATION
  end
end

Feature.unset_modulation = function(self)
  self.value = self.value & (~self.MODULATION & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.POSITIONING |
    Feature.MOTION_LATCHING |
    Feature.UNIT |
    Feature.LIMITATION |
    Feature.SPEED |
    Feature.TRANSLATION |
    Feature.ROTATION |
    Feature.MODULATION
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
  is_unit_set = Feature.is_unit_set,
  set_unit = Feature.set_unit,
  unset_unit = Feature.unset_unit,
  is_limitation_set = Feature.is_limitation_set,
  set_limitation = Feature.set_limitation,
  unset_limitation = Feature.unset_limitation,
  is_speed_set = Feature.is_speed_set,
  set_speed = Feature.set_speed,
  unset_speed = Feature.unset_speed,
  is_translation_set = Feature.is_translation_set,
  set_translation = Feature.set_translation,
  unset_translation = Feature.unset_translation,
  is_rotation_set = Feature.is_rotation_set,
  set_rotation = Feature.set_rotation,
  unset_rotation = Feature.unset_rotation,
  is_modulation_set = Feature.is_modulation_set,
  set_modulation = Feature.set_modulation,
  unset_modulation = Feature.unset_modulation,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
