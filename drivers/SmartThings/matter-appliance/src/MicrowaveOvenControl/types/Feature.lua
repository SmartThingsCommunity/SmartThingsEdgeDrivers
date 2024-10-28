local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.POWER_AS_NUMBER = 0x0001
Feature.POWER_IN_WATTS = 0x0002
Feature.POWER_NUMBER_LIMITS = 0x0004

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  POWER_AS_NUMBER = 0x0001,
  POWER_IN_WATTS = 0x0002,
  POWER_NUMBER_LIMITS = 0x0004,
}

Feature.is_power_as_number_set = function(self)
  return (self.value & self.POWER_AS_NUMBER) ~= 0
end

Feature.set_power_as_number = function(self)
  if self.value ~= nil then
    self.value = self.value | self.POWER_AS_NUMBER
  else
    self.value = self.POWER_AS_NUMBER
  end
end

Feature.unset_power_as_number = function(self)
  self.value = self.value & (~self.POWER_AS_NUMBER & self.BASE_MASK)
end

Feature.is_power_in_watts_set = function(self)
  return (self.value & self.POWER_IN_WATTS) ~= 0
end

Feature.set_power_in_watts = function(self)
  if self.value ~= nil then
    self.value = self.value | self.POWER_IN_WATTS
  else
    self.value = self.POWER_IN_WATTS
  end
end

Feature.unset_power_in_watts = function(self)
  self.value = self.value & (~self.POWER_IN_WATTS & self.BASE_MASK)
end

Feature.is_power_number_limits_set = function(self)
  return (self.value & self.POWER_NUMBER_LIMITS) ~= 0
end

Feature.set_power_number_limits = function(self)
  if self.value ~= nil then
    self.value = self.value | self.POWER_NUMBER_LIMITS
  else
    self.value = self.POWER_NUMBER_LIMITS
  end
end

Feature.unset_power_number_limits = function(self)
  self.value = self.value & (~self.POWER_NUMBER_LIMITS & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.POWER_AS_NUMBER |
    Feature.POWER_IN_WATTS |
    Feature.POWER_NUMBER_LIMITS
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_power_as_number_set = Feature.is_power_as_number_set,
  set_power_as_number = Feature.set_power_as_number,
  unset_power_as_number = Feature.unset_power_as_number,
  is_power_in_watts_set = Feature.is_power_in_watts_set,
  set_power_in_watts = Feature.set_power_in_watts,
  unset_power_in_watts = Feature.unset_power_in_watts,
  is_power_number_limits_set = Feature.is_power_number_limits_set,
  set_power_number_limits = Feature.set_power_number_limits,
  unset_power_number_limits = Feature.unset_power_number_limits,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature