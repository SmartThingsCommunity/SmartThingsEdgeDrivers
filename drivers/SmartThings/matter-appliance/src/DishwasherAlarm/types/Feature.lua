local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.RESET = 0x0001

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  RESET = 0x0001,
}

Feature.is_reset_set = function(self)
  return (self.value & self.RESET) ~= 0
end

Feature.set_reset = function(self)
  if self.value ~= nil then
    self.value = self.value | self.RESET
  else
    self.value = self.RESET
  end
end

Feature.unset_reset = function(self)
  self.value = self.value & (~self.RESET & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.RESET
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_reset_set = Feature.is_reset_set,
  set_reset = Feature.set_reset,
  unset_reset = Feature.unset_reset,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

