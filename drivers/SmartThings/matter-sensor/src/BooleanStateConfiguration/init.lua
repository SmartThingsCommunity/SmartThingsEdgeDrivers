local cluster_base = require "st.matter.cluster_base"
local BooleanStateConfigurationServerAttributes = require "BooleanStateConfiguration.server.attributes"
local BooleanStateConfigurationTypes = require "BooleanStateConfiguration.types"

local BooleanStateConfiguration = {}

BooleanStateConfiguration.ID = 0x0080
BooleanStateConfiguration.NAME = "BooleanStateConfiguration"
BooleanStateConfiguration.server = {}
BooleanStateConfiguration.client = {}
BooleanStateConfiguration.server.attributes = BooleanStateConfigurationServerAttributes:set_parent_cluster(BooleanStateConfiguration)
BooleanStateConfiguration.types = BooleanStateConfigurationTypes

function BooleanStateConfiguration:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "CurrentSensitivityLevel",
    [0x0001] = "SupportedSensitivityLevels",
    [0x0002] = "DefaultSensitivityLevel",
    [0x0003] = "AlarmsActive",
    [0x0004] = "AlarmsSuppressed",
    [0x0005] = "AlarmsEnabled",
    [0x0006] = "AlarmsSupported",
    [0x0007] = "SensorFault",
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

BooleanStateConfiguration.attribute_direction_map = {
  ["CurrentSensitivityLevel"] = "server",
  ["SupportedSensitivityLevels"] = "server",
  ["DefaultSensitivityLevel"] = "server",
  ["AlarmsActive"] = "server",
  ["AlarmsSuppressed"] = "server",
  ["AlarmsEnabled"] = "server",
  ["AlarmsSupported"] = "server",
  ["SensorFault"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

do
  local has_aliases, aliases = pcall(require, "BooleanStateConfiguration.server.attributes")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      BooleanStateConfiguration.attribute_direction_map[alias] = "server"
    end
  end
end

BooleanStateConfiguration.FeatureMap = BooleanStateConfiguration.types.Feature

function BooleanStateConfiguration.are_features_supported(feature, feature_map)
  if (BooleanStateConfiguration.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

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

