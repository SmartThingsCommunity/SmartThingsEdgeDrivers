local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.SPIN = 0x0001
Feature.RINSE = 0x0002

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  SPIN = 0x0001,
  RINSE = 0x0002,
}

Feature.is_spin_set = function(self)
  return (self.value & self.SPIN) ~= 0
end

Feature.set_spin = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SPIN
  else
    self.value = self.SPIN
  end
end

Feature.unset_spin = function(self)
  self.value = self.value & (~self.SPIN & self.BASE_MASK)
end

Feature.is_rinse_set = function(self)
  return (self.value & self.RINSE) ~= 0
end

Feature.set_rinse = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RINSE
  else
    self.value = self.RINSE
  end
end

Feature.unset_rinse = function(self)
  self.value = self.value & (~self.RINSE & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.SPIN |
    Feature.RINSE
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_spin_set = Feature.is_spin_set,
  set_spin = Feature.set_spin,
  unset_spin = Feature.unset_spin,
  is_rinse_set = Feature.is_rinse_set,
  set_rinse = Feature.set_rinse,
  unset_rinse = Feature.unset_rinse,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
