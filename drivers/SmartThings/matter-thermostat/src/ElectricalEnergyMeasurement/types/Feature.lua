local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"
local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.IMPORTED_ENERGY = 0x0001
Feature.EXPORTED_ENERGY = 0x0002
Feature.CUMULATIVE_ENERGY = 0x0004
Feature.PERIODIC_ENERGY = 0x0008

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  IMPORTED_ENERGY = 0x0001,
  EXPORTED_ENERGY = 0x0002,
  CUMULATIVE_ENERGY = 0x0004,
  PERIODIC_ENERGY = 0x0008,
}

Feature.is_imported_energy_set = function(self)
  return (self.value & self.IMPORTED_ENERGY) ~= 0
end

Feature.set_imported_energy = function(self)
  if self.value ~= nil then
    self.value = self.value | self.IMPORTED_ENERGY
  else
    self.value = self.IMPORTED_ENERGY
  end
end

Feature.unset_imported_energy = function(self)
  self.value = self.value & (~self.IMPORTED_ENERGY & self.BASE_MASK)
end
Feature.is_exported_energy_set = function(self)
  return (self.value & self.EXPORTED_ENERGY) ~= 0
end

Feature.set_exported_energy = function(self)
  if self.value ~= nil then
    self.value = self.value | self.EXPORTED_ENERGY
  else
    self.value = self.EXPORTED_ENERGY
  end
end

Feature.unset_exported_energy = function(self)
  self.value = self.value & (~self.EXPORTED_ENERGY & self.BASE_MASK)
end
Feature.is_cumulative_energy_set = function(self)
  return (self.value & self.CUMULATIVE_ENERGY) ~= 0
end

Feature.set_cumulative_energy = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CUMULATIVE_ENERGY
  else
    self.value = self.CUMULATIVE_ENERGY
  end
end

Feature.unset_cumulative_energy = function(self)
  self.value = self.value & (~self.CUMULATIVE_ENERGY & self.BASE_MASK)
end
Feature.is_periodic_energy_set = function(self)
  return (self.value & self.PERIODIC_ENERGY) ~= 0
end

Feature.set_periodic_energy = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PERIODIC_ENERGY
  else
    self.value = self.PERIODIC_ENERGY
  end
end

Feature.unset_periodic_energy = function(self)
  self.value = self.value & (~self.PERIODIC_ENERGY & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.IMPORTED_ENERGY |
    Feature.EXPORTED_ENERGY |
    Feature.CUMULATIVE_ENERGY |
    Feature.PERIODIC_ENERGY
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_imported_energy_set = Feature.is_imported_energy_set,
  set_imported_energy = Feature.set_imported_energy,
  unset_imported_energy = Feature.unset_imported_energy,
  is_exported_energy_set = Feature.is_exported_energy_set,
  set_exported_energy = Feature.set_exported_energy,
  unset_exported_energy = Feature.unset_exported_energy,
  is_cumulative_energy_set = Feature.is_cumulative_energy_set,
  set_cumulative_energy = Feature.set_cumulative_energy,
  unset_cumulative_energy = Feature.unset_cumulative_energy,
  is_periodic_energy_set = Feature.is_periodic_energy_set,
  set_periodic_energy = Feature.set_periodic_energy,
  unset_periodic_energy = Feature.unset_periodic_energy,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

