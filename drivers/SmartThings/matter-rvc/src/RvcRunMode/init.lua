local cluster_base = require "st.matter.cluster_base"
local RvcRunModeServerAttributes = require "RvcRunMode.server.attributes"
local RvcRunModeServerCommands = require "RvcRunMode.server.commands"
local RvcRunModeClientCommands = require "RvcRunMode.client.commands"
local RvcRunModeTypes = require "RvcRunMode.types"

local RvcRunMode = {}

RvcRunMode.ID = 0x0054
RvcRunMode.NAME = "RvcRunMode"
RvcRunMode.server = {}
RvcRunMode.client = {}
RvcRunMode.server.attributes = RvcRunModeServerAttributes:set_parent_cluster(RvcRunMode)
RvcRunMode.server.commands = RvcRunModeServerCommands:set_parent_cluster(RvcRunMode)
RvcRunMode.client.commands = RvcRunModeClientCommands:set_parent_cluster(RvcRunMode)
RvcRunMode.types = RvcRunModeTypes

function RvcRunMode:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "SupportedModes",
    [0x0001] = "CurrentMode",
    [0x0002] = "StartUpMode",
    [0x0003] = "OnMode",
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

function RvcRunMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function RvcRunMode:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x0001] = "ChangeToModeResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

RvcRunMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["StartUpMode"] = "server",
  ["OnMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

RvcRunMode.command_direction_map = {
  ["ChangeToMode"] = "server",
  ["ChangeToModeResponse"] = "client",
}

RvcRunMode.FeatureMap = RvcRunMode.types.Feature

function RvcRunMode.are_features_supported(feature, feature_map)
  if (RvcRunMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = RvcRunMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, RvcRunMode.NAME))
  end
  return RvcRunMode[direction].attributes[key]
end
RvcRunMode.attributes = {}
setmetatable(RvcRunMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = RvcRunMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, RvcRunMode.NAME))
  end
  return RvcRunMode[direction].commands[key]
end
RvcRunMode.commands = {}
setmetatable(RvcRunMode.commands, command_helper_mt)

setmetatable(RvcRunMode, {__index = cluster_base})

return RvcRunMode

