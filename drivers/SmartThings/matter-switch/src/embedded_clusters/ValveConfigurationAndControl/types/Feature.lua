local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"
local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.TIME_SYNC = 0x0001
Feature.LEVEL = 0x0002

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

setmetatable(Feature, new_mt)

return Feature
