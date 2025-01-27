local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.PAN_CHANGE = 0x0001

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  PAN_CHANGE = 0x0001,
}

Feature.is_pan_change_set = function(self)
  return (self.value & self.PAN_CHANGE) ~= 0
end

Feature.set_pan_change = function(self)
  if self.value ~= nil then
    self.value = self.value | self.PAN_CHANGE
  else
    self.value = self.PAN_CHANGE
  end
end

Feature.unset_pan_change = function(self)
  self.value = self.value & (~self.PAN_CHANGE & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.PAN_CHANGE
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_pan_change_set = Feature.is_pan_change_set,
  set_pan_change = Feature.set_pan_change,
  unset_pan_change = Feature.unset_pan_change,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

