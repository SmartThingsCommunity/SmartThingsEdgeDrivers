-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"
local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.IMPORTED_ENERGY = 0x0001
Feature.EXPORTED_ENERGY = 0x0002
Feature.CUMULATIVE_ENERGY = 0x0004
Feature.PERIODIC_ENERGY = 0x0008

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

setmetatable(Feature, new_mt)

return Feature

