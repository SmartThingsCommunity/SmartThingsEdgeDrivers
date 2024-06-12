local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.FAIR = 0x0001
Feature.MODERATE = 0x0002
Feature.VERY_POOR = 0x0004
Feature.EXTREMELY_POOR = 0x0008

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  FAIR = 0x0001,
  MODERATE = 0x0002,
  VERY_POOR = 0x0004,
  EXTREMELY_POOR = 0x0008,
}

Feature.is_fair_set = function(self)
  return (self.value & self.FAIR) ~= 0
end

Feature.set_fair = function(self)
  if self.value ~= nil then
    self.value = self.value | self.FAIR
  else
    self.value = self.FAIR
  end
end

Feature.unset_fair = function(self)
  self.value = self.value & (~self.FAIR & self.BASE_MASK)
end

Feature.is_moderate_set = function(self)
  return (self.value & self.MODERATE) ~= 0
end

Feature.set_moderate = function(self)
  if self.value ~= nil then
    self.value = self.value | self.MODERATE
  else
    self.value = self.MODERATE
  end
end

Feature.unset_moderate = function(self)
  self.value = self.value & (~self.MODERATE & self.BASE_MASK)
end

Feature.is_very_poor_set = function(self)
  return (self.value & self.VERY_POOR) ~= 0
end

Feature.set_very_poor = function(self)
  if self.value ~= nil then
    self.value = self.value | self.VERY_POOR
  else
    self.value = self.VERY_POOR
  end
end

Feature.unset_very_poor = function(self)
  self.value = self.value & (~self.VERY_POOR & self.BASE_MASK)
end

Feature.is_extremely_poor_set = function(self)
  return (self.value & self.EXTREMELY_POOR) ~= 0
end

Feature.set_extremely_poor = function(self)
  if self.value ~= nil then
    self.value = self.value | self.EXTREMELY_POOR
  else
    self.value = self.EXTREMELY_POOR
  end
end

Feature.unset_extremely_poor = function(self)
  self.value = self.value & (~self.EXTREMELY_POOR & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.FAIR |
    Feature.MODERATE |
    Feature.VERY_POOR |
    Feature.EXTREMELY_POOR
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_fair_set = Feature.is_fair_set,
  set_fair = Feature.set_fair,
  unset_fair = Feature.unset_fair,
  is_moderate_set = Feature.is_moderate_set,
  set_moderate = Feature.set_moderate,
  unset_moderate = Feature.unset_moderate,
  is_very_poor_set = Feature.is_very_poor_set,
  set_very_poor = Feature.set_very_poor,
  unset_very_poor = Feature.unset_very_poor,
  is_extremely_poor_set = Feature.is_extremely_poor_set,
  set_extremely_poor = Feature.set_extremely_poor,
  unset_extremely_poor = Feature.unset_extremely_poor,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

