local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.VISUAL = 0x0001
Feature.AUDIBLE = 0x0002
Feature.ALARM_SUPPRESS = 0x0004
Feature.SENSITIVITY_LEVEL = 0x0008

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  VISUAL = 0x0001,
  AUDIBLE = 0x0002,
  ALARM_SUPPRESS = 0x0004,
  SENSITIVITY_LEVEL = 0x0008,
}

Feature.is_visual_set = function(self)
  return (self.value & self.VISUAL) ~= 0
end

Feature.set_visual = function(self)
  if self.value ~= nil then
    self.value = self.value | self.VISUAL
  else
    self.value = self.VISUAL
  end
end

Feature.unset_visual = function(self)
  self.value = self.value & (~self.VISUAL & self.BASE_MASK)
end
Feature.is_audible_set = function(self)
  return (self.value & self.AUDIBLE) ~= 0
end

Feature.set_audible = function(self)
  if self.value ~= nil then
    self.value = self.value | self.AUDIBLE
  else
    self.value = self.AUDIBLE
  end
end

Feature.unset_audible = function(self)
  self.value = self.value & (~self.AUDIBLE & self.BASE_MASK)
end

Feature.is_alarm_suppress_set = function(self)
  return (self.value & self.ALARM_SUPPRESS) ~= 0
end

Feature.set_alarm_suppress = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ALARM_SUPPRESS
  else
    self.value = self.ALARM_SUPPRESS
  end
end

Feature.unset_alarm_suppress = function(self)
  self.value = self.value & (~self.ALARM_SUPPRESS & self.BASE_MASK)
end

Feature.is_sensitivity_level_set = function(self)
  return (self.value & self.SENSITIVITY_LEVEL) ~= 0
end

Feature.set_sensitivity_level = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SENSITIVITY_LEVEL
  else
    self.value = self.SENSITIVITY_LEVEL
  end
end

Feature.unset_sensitivity_level = function(self)
  self.value = self.value & (~self.SENSITIVITY_LEVEL & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.VISUAL |
    Feature.AUDIBLE |
    Feature.ALARM_SUPPRESS |
    Feature.SENSITIVITY_LEVEL
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_visual_set = Feature.is_visual_set,
  set_visual = Feature.set_visual,
  unset_visual = Feature.unset_visual,
  is_audible_set = Feature.is_audible_set,
  set_audible = Feature.set_audible,
  unset_audible = Feature.unset_audible,
  is_alarm_suppress_set = Feature.is_alarm_suppress_set,
  set_alarm_suppress = Feature.set_alarm_suppress,
  unset_alarm_suppress = Feature.unset_alarm_suppress,
  is_sensitivity_level_set = Feature.is_sensitivity_level_set,
  set_sensitivity_level = Feature.set_sensitivity_level,
  unset_sensitivity_level = Feature.unset_sensitivity_level,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

