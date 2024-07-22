local cluster_base = require "st.matter.cluster_base"
local HepaFilterMonitoringServerAttributes = require "HepaFilterMonitoring.server.attributes"
local HepaFilterMonitoringTypes = require "HepaFilterMonitoring.types"

local HepaFilterMonitoring = {}

HepaFilterMonitoring.ID = 0x0071
HepaFilterMonitoring.NAME = "HepaFilterMonitoring"
HepaFilterMonitoring.server = {}
HepaFilterMonitoring.client = {}
HepaFilterMonitoring.server.attributes = HepaFilterMonitoringServerAttributes:set_parent_cluster(HepaFilterMonitoring)
HepaFilterMonitoring.types = HepaFilterMonitoringTypes

function HepaFilterMonitoring:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "Condition",
    [0x0001] = "DegradationDirection",
    [0x0002] = "ChangeIndication",
    [0x0003] = "InPlaceIndicator",
    [0x0004] = "LastChangedTime",
    [0x0005] = "ReplacementProductList",
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

function HepaFilterMonitoring:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ResetCondition",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

HepaFilterMonitoring.attribute_direction_map = {
  ["Condition"] = "server",
  ["DegradationDirection"] = "server",
  ["ChangeIndication"] = "server",
  ["InPlaceIndicator"] = "server",
  ["LastChangedTime"] = "server",
  ["ReplacementProductList"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}


HepaFilterMonitoring.FeatureMap = HepaFilterMonitoring.types.Feature

function HepaFilterMonitoring.are_features_supported(feature, feature_map)
  if (HepaFilterMonitoring.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = HepaFilterMonitoring.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, HepaFilterMonitoring.NAME))
  end
  return HepaFilterMonitoring[direction].attributes[key]
end
HepaFilterMonitoring.attributes = {}
setmetatable(HepaFilterMonitoring.attributes, attribute_helper_mt)

setmetatable(HepaFilterMonitoring, {__index = cluster_base})

return HepaFilterMonitoring

