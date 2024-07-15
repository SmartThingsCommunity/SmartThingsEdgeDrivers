local cluster_base = require "st.matter.cluster_base"
local ActivatedCarbonFilterMonitoringServerAttributes = require "ActivatedCarbonFilterMonitoring.server.attributes"
local ActivatedCarbonFilterMonitoringTypes = require "ActivatedCarbonFilterMonitoring.types"

local ActivatedCarbonFilterMonitoring = {}

ActivatedCarbonFilterMonitoring.ID = 0x0072
ActivatedCarbonFilterMonitoring.NAME = "ActivatedCarbonFilterMonitoring"
ActivatedCarbonFilterMonitoring.server = {}
ActivatedCarbonFilterMonitoring.client = {}
ActivatedCarbonFilterMonitoring.server.attributes = ActivatedCarbonFilterMonitoringServerAttributes:set_parent_cluster(ActivatedCarbonFilterMonitoring)
ActivatedCarbonFilterMonitoring.types = ActivatedCarbonFilterMonitoringTypes

function ActivatedCarbonFilterMonitoring:get_attribute_by_id(attr_id)
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

function ActivatedCarbonFilterMonitoring:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ResetCondition",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

ActivatedCarbonFilterMonitoring.attribute_direction_map = {
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


ActivatedCarbonFilterMonitoring.FeatureMap = ActivatedCarbonFilterMonitoring.types.Feature

function ActivatedCarbonFilterMonitoring.are_features_supported(feature, feature_map)
  if (ActivatedCarbonFilterMonitoring.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ActivatedCarbonFilterMonitoring.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ActivatedCarbonFilterMonitoring.NAME))
  end
  return ActivatedCarbonFilterMonitoring[direction].attributes[key]
end
ActivatedCarbonFilterMonitoring.attributes = {}
setmetatable(ActivatedCarbonFilterMonitoring.attributes, attribute_helper_mt)

setmetatable(ActivatedCarbonFilterMonitoring, {__index = cluster_base})

return ActivatedCarbonFilterMonitoring

