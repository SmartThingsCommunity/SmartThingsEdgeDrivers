local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.CONDITION = 0x0001
Feature.WARNING = 0x0002
Feature.REPLACEMENT_PRODUCT_LIST = 0x0004

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  CONDITION = 0x0001,
  WARNING = 0x0002,
  REPLACEMENT_PRODUCT_LIST = 0x0004,
}

Feature.is_condition_set = function(self)
  return (self.value & self.CONDITION) ~= 0
end

Feature.set_condition = function(self)
  if self.value ~= nil then
    self.value = self.value | self.CONDITION
  else
    self.value = self.CONDITION
  end
end

Feature.unset_condition = function(self)
  self.value = self.value & (~self.CONDITION & self.BASE_MASK)
end

Feature.is_warning_set = function(self)
  return (self.value & self.WARNING) ~= 0
end

Feature.set_warning = function(self)
  if self.value ~= nil then
    self.value = self.value | self.WARNING
  else
    self.value = self.WARNING
  end
end

Feature.unset_warning = function(self)
  self.value = self.value & (~self.WARNING & self.BASE_MASK)
end

Feature.is_replacement_product_list_set = function(self)
  return (self.value & self.REPLACEMENT_PRODUCT_LIST) ~= 0
end

Feature.set_replacement_product_list = function(self)
  if self.value ~= nil then
    self.value = self.value | self.REPLACEMENT_PRODUCT_LIST
  else
    self.value = self.REPLACEMENT_PRODUCT_LIST
  end
end

Feature.unset_replacement_product_list = function(self)
  self.value = self.value & (~self.REPLACEMENT_PRODUCT_LIST & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.CONDITION |
    Feature.WARNING |
    Feature.REPLACEMENT_PRODUCT_LIST
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_condition_set = Feature.is_condition_set,
  set_condition = Feature.set_condition,
  unset_condition = Feature.unset_condition,
  is_warning_set = Feature.is_warning_set,
  set_warning = Feature.set_warning,
  unset_warning = Feature.unset_warning,
  is_replacement_product_list_set = Feature.is_replacement_product_list_set,
  set_replacement_product_list = Feature.set_replacement_product_list,
  unset_replacement_product_list = Feature.unset_replacement_product_list,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

