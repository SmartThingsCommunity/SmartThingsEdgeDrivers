local cluster_base = require "st.matter.cluster_base"
local AirQualityServerAttributes = require "AirQuality.server.attributes"
local AirQualityServerCommands = require "AirQuality.server.commands"
local AirQualityTypes = require "AirQuality.types"

local AirQuality = {}

AirQuality.ID = 0x005B
AirQuality.NAME = "AirQuality"
AirQuality.server = {}
AirQuality.client = {}
AirQuality.server.attributes = AirQualityServerAttributes:set_parent_cluster(AirQuality)
AirQuality.server.commands = AirQualityServerCommands:set_parent_cluster(AirQuality)
AirQuality.types = AirQualityTypes

function AirQuality:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "AirQuality",
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

function AirQuality:get_server_command_by_id(command_id)
  local server_id_map = {
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end


-- Attribute Mapping
AirQuality.attribute_direction_map = {
  ["AirQuality"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

AirQuality.FeatureMap = AirQuality.types.Feature

function AirQuality.are_features_supported(feature, feature_map)
  if (AirQuality.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = AirQuality.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, AirQuality.NAME))
  end
  return AirQuality[direction].attributes[key]
end
AirQuality.attributes = {}
setmetatable(AirQuality.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = AirQuality.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, AirQuality.NAME))
  end
  return AirQuality[direction].commands[key]
end
AirQuality.commands = {}
setmetatable(AirQuality.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return AirQuality.server.events[key]
end
AirQuality.events = {}
setmetatable(AirQuality.events, event_helper_mt)

setmetatable(AirQuality, {__index = cluster_base})

return AirQuality

