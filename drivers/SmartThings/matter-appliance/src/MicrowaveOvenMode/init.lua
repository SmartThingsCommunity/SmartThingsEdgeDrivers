local cluster_base = require "st.matter.cluster_base"
local MicrowaveOvenModeServerAttributes = require "MicrowaveOvenMode.server.attributes"
local MicrowaveOvenModeTypes = require "MicrowaveOvenMode.types"

local MicrowaveOvenMode = {}

MicrowaveOvenMode.ID = 0x005E
MicrowaveOvenMode.NAME = "MicrowaveOvenMode"
MicrowaveOvenMode.server = {}
MicrowaveOvenMode.client = {}
MicrowaveOvenMode.server.attributes = MicrowaveOvenModeServerAttributes:set_parent_cluster(MicrowaveOvenMode)
MicrowaveOvenMode.types = MicrowaveOvenModeTypes

function MicrowaveOvenMode:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "SupportedModes",
    [0x0001] = "CurrentMode",
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

function MicrowaveOvenMode:get_server_command_by_id(command_id)
  local server_id_map = {
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

MicrowaveOvenMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

MicrowaveOvenMode.FeatureMap = MicrowaveOvenMode.types.Feature

function MicrowaveOvenMode.are_features_supported(feature, feature_map)
  if (MicrowaveOvenMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = MicrowaveOvenMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, MicrowaveOvenMode.NAME))
  end
  return MicrowaveOvenMode[direction].attributes[key]
end
MicrowaveOvenMode.attributes = {}
setmetatable(MicrowaveOvenMode.attributes, attribute_helper_mt)

setmetatable(MicrowaveOvenMode, {__index = cluster_base})

return MicrowaveOvenMode
