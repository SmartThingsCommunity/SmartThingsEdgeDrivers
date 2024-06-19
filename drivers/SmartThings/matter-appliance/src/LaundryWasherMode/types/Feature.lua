local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.ON_OFF = 0x0001

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  ON_OFF = 0x0001,
}

Feature.is_on_off_set = function(self)
  return (self.value & self.ON_OFF) ~= 0
end

Feature.set_on_off = function(self)
  if self.value ~= nil then
    self.value = self.value | self.ON_OFF
  else
    self.value = self.ON_OFF
  end
end

Feature.unset_on_off = function(self)
  self.value = self.value & (~self.ON_OFF & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.ON_OFF
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_on_off_set = Feature.is_on_off_set,
  set_on_off = Feature.set_on_off,
  unset_on_off = Feature.unset_on_off,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
