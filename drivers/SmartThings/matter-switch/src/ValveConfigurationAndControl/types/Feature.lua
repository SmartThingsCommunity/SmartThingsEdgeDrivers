local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"
local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.TIME_SYNC = 0x0001
Feature.LEVEL = 0x0002

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  TIME_SYNC = 0x0001,
  LEVEL = 0x0002,
}

Feature.is_time_sync_set = function(self)
  return (self.value & self.TIME_SYNC) ~= 0
end

Feature.set_time_sync = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TIME_SYNC
  else
    self.value = self.TIME_SYNC
  end
end

Feature.unset_time_sync = function(self)
  self.value = self.value & (~self.TIME_SYNC & self.BASE_MASK)
end

Feature.is_level_set = function(self)
  return (self.value & self.LEVEL) ~= 0
end

Feature.set_level = function(self)
  if self.value ~= nil then
    self.value = self.value | self.LEVEL
  else
    self.value = self.LEVEL
  end
end

Feature.unset_level = function(self)
  self.value = self.value & (~self.LEVEL & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.TIME_SYNC |
    Feature.LEVEL
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_time_sync_set = Feature.is_time_sync_set,
  set_time_sync = Feature.set_time_sync,
  unset_time_sync = Feature.unset_time_sync,
  is_level_set = Feature.is_level_set,
  set_level = Feature.set_level,
  unset_level = Feature.unset_level,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
