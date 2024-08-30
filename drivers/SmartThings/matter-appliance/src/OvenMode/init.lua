local cluster_base = require "st.matter.cluster_base"
local OvenModeServerAttributes = require "OvenMode.server.attributes"
local OvenModeServerCommands = require "OvenMode.server.commands"
local OvenModeTypes = require "OvenMode.types"

local OvenMode = {}

OvenMode.ID = 0x0049
OvenMode.NAME = "OvenMode"
OvenMode.server = {}
OvenMode.client = {}
OvenMode.server.attributes = OvenModeServerAttributes:set_parent_cluster(OvenMode)
OvenMode.server.commands = OvenModeServerCommands:set_parent_cluster(OvenMode)
OvenMode.types = OvenModeTypes

function OvenMode:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "SupportedModes",
    [0x0001] = "CurrentMode",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

function OvenMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

OvenMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
}

OvenMode.command_direction_map = {
  ["ChangeToMode"] = "server",
}

OvenMode.FeatureMap = OvenMode.types.Feature

function OvenMode.are_features_supported(feature, feature_map)
  if (OvenMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = OvenMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, OvenMode.NAME))
  end
  return OvenMode[direction].attributes[key]
end
OvenMode.attributes = {}
setmetatable(OvenMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = OvenMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, OvenMode.NAME))
  end
  return OvenMode[direction].commands[key]
end
OvenMode.commands = {}
setmetatable(OvenMode.commands, command_helper_mt)

setmetatable(OvenMode, {__index = cluster_base})

return OvenMode
