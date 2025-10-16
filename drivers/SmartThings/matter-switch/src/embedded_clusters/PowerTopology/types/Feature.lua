local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.NODE_TOPOLOGY = 0x0001
Feature.TREE_TOPOLOGY = 0x0002
Feature.SET_TOPOLOGY = 0x0004
Feature.DYNAMIC_POWER_FLOW = 0x0008

function Feature.bits_are_valid(feature)
  local max =
    Feature.NODE_TOPOLOGY |
    Feature.TREE_TOPOLOGY |
    Feature.SET_TOPOLOGY |
    Feature.DYNAMIC_POWER_FLOW
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

setmetatable(Feature, new_mt)

return Feature

