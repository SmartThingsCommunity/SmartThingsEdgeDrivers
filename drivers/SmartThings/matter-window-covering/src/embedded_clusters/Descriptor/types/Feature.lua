-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.TAG_LIST = 0x0001

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  TAG_LIST = 0x0001,
}

Feature.is_tag_list_set = function(self)
  return (self.value & self.TAG_LIST) ~= 0
end

Feature.set_tag_list = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TAG_LIST
  else
    self.value = self.TAG_LIST
  end
end

Feature.unset_tag_list = function(self)
  self.value = self.value & (~self.TAG_LIST & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.TAG_LIST
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_tag_list_set = Feature.is_tag_list_set,
  set_tag_list = Feature.set_tag_list,
  unset_tag_list = Feature.unset_tag_list,
}

Feature.augment_type = function(_cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature
