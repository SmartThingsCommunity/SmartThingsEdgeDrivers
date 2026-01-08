local cluster_base = require "st.matter.cluster_base"
local BooleanStateConfigurationServerAttributes = require "embedded_clusters.BooleanStateConfiguration.server.attributes"

local BooleanStateConfiguration = {}

BooleanStateConfiguration.ID = 0x0080
BooleanStateConfiguration.NAME = "BooleanStateConfiguration"
BooleanStateConfiguration.server = {}
BooleanStateConfiguration.client = {}
BooleanStateConfiguration.server.attributes = BooleanStateConfigurationServerAttributes:set_parent_cluster(BooleanStateConfiguration)

function BooleanStateConfiguration:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0001] = "SupportedSensitivityLevels",
    [0x0007] = "SensorFault",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

BooleanStateConfiguration.attribute_direction_map = {
  ["SupportedSensitivityLevels"] = "server",
  ["SensorFault"] = "server",
}

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = BooleanStateConfiguration.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, BooleanStateConfiguration.NAME))
  end
  return BooleanStateConfiguration[direction].attributes[key]
end
BooleanStateConfiguration.attributes = {}
setmetatable(BooleanStateConfiguration.attributes, attribute_helper_mt)

setmetatable(BooleanStateConfiguration, {__index = cluster_base})

return BooleanStateConfiguration

