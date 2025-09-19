local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.DIRECT_CURRENT = 0x0001
Feature.ALTERNATING_CURRENT = 0x0002
Feature.POLYPHASE_POWER = 0x0004
Feature.HARMONICS = 0x0008
Feature.POWER_QUALITY = 0x0010

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  DIRECT_CURRENT = 0x0001,
  ALTERNATING_CURRENT = 0x0002,
  POLYPHASE_POWER = 0x0004,
  HARMONICS = 0x0008,
  POWER_QUALITY = 0x0010,
}

Feature.is_direct_current_set = function(self)
  return (self.value & self.DIRECT_CURRENT) ~= 0
end

Feature.set_direct_current = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DIRECT_CURRENT
  else
    self.value = self.DIRECT_CURRENT
  end
end

Feature.unset_direct_current = function(self)
  self.value = self.value & (~self.DIRECT_CURRENT & self.BASE_MASK)
end
Feature.is_alternating_current_set = function(self)
  return (self.value & self.ALTERNATING_CURRENT) ~= 0
end

Feature.set_alternating_current = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ALTERNATING_CURRENT
  else
    self.value = self.ALTERNATING_CURRENT
  end
end

Feature.unset_alternating_current = function(self)
  self.value = self.value & (~self.ALTERNATING_CURRENT & self.BASE_MASK)
end
Feature.is_polyphase_power_set = function(self)
  return (self.value & self.POLYPHASE_POWER) ~= 0
end

Feature.set_polyphase_power = function(self)
  if self.value ~= nil then
    self.value = self.value | self.POLYPHASE_POWER
  else
    self.value = self.POLYPHASE_POWER
  end
end

Feature.unset_polyphase_power = function(self)
  self.value = self.value & (~self.POLYPHASE_POWER & self.BASE_MASK)
end
Feature.is_harmonics_set = function(self)
  return (self.value & self.HARMONICS) ~= 0
end

Feature.set_harmonics = function(self)
  if self.value ~= nil then
    self.value = self.value | self.HARMONICS
  else
    self.value = self.HARMONICS
  end
end

Feature.unset_harmonics = function(self)
  self.value = self.value & (~self.HARMONICS & self.BASE_MASK)
end
Feature.is_power_quality_set = function(self)
  return (self.value & self.POWER_QUALITY) ~= 0
end

Feature.set_power_quality = function(self)
  if self.value ~= nil then
    self.value = self.value | self.POWER_QUALITY
  else
    self.value = self.POWER_QUALITY
  end
end

Feature.unset_power_quality = function(self)
  self.value = self.value & (~self.POWER_QUALITY & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.DIRECT_CURRENT |
    Feature.ALTERNATING_CURRENT |
    Feature.POLYPHASE_POWER |
    Feature.HARMONICS |
    Feature.POWER_QUALITY
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_direct_current_set = Feature.is_direct_current_set,
  set_direct_current = Feature.set_direct_current,
  unset_direct_current = Feature.unset_direct_current,
  is_alternating_current_set = Feature.is_alternating_current_set,
  set_alternating_current = Feature.set_alternating_current,
  unset_alternating_current = Feature.unset_alternating_current,
  is_polyphase_power_set = Feature.is_polyphase_power_set,
  set_polyphase_power = Feature.set_polyphase_power,
  unset_polyphase_power = Feature.unset_polyphase_power,
  is_harmonics_set = Feature.is_harmonics_set,
  set_harmonics = Feature.set_harmonics,
  unset_harmonics = Feature.unset_harmonics,
  is_power_quality_set = Feature.is_power_quality_set,
  set_power_quality = Feature.set_power_quality,
  unset_power_quality = Feature.unset_power_quality,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

