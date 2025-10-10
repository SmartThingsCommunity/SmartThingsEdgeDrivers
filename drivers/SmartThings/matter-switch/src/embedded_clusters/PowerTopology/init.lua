local cluster_base = require "st.matter.cluster_base"
local PowerTopologyServerAttributes = require "embedded_clusters.PowerTopology.server.attributes"
local PowerTopologyTypes = require "embedded_clusters.PowerTopology.types"

local PowerTopology = {}

PowerTopology.ID = 0x009C
PowerTopology.NAME = "PowerTopology"
PowerTopology.server = {}
PowerTopology.client = {}
PowerTopology.server.attributes = PowerTopologyServerAttributes:set_parent_cluster(PowerTopology)
PowerTopology.types = PowerTopologyTypes

function PowerTopology:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "AvailableEndpoints",
    [0x0001] = "ActiveEndpoints",
    [0xFFF9] = "AcceptedCommandList",
    [0xFFFA] = "EventList",
    [0xFFFB] = "AttributeList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

function PowerTopology:get_server_command_by_id(command_id)
  local server_id_map = {
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end


PowerTopology.attribute_direction_map = {
  ["AvailableEndpoints"] = "server",
  ["ActiveEndpoints"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

PowerTopology.command_direction_map = {
}

PowerTopology.FeatureMap = PowerTopology.types.Feature

function PowerTopology.are_features_supported(feature, feature_map)
  if (PowerTopology.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = PowerTopology.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, PowerTopology.NAME))
  end
  return PowerTopology[direction].attributes[key]
end
PowerTopology.attributes = {}
setmetatable(PowerTopology.attributes, attribute_helper_mt)

setmetatable(PowerTopology, {__index = cluster_base})

return PowerTopology

