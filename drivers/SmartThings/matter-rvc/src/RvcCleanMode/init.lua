local cluster_base = require "st.matter.cluster_base"
local RvcCleanModeServerAttributes = require "RvcCleanMode.server.attributes"
local RvcCleanModeServerCommands = require "RvcCleanMode.server.commands"
local RvcCleanModeClientCommands = require "RvcCleanMode.client.commands"
local RvcCleanModeTypes = require "RvcCleanMode.types"

local RvcCleanMode = {}

RvcCleanMode.ID = 0x0055
RvcCleanMode.NAME = "RvcCleanMode"
RvcCleanMode.server = {}
RvcCleanMode.client = {}
RvcCleanMode.server.attributes = RvcCleanModeServerAttributes:set_parent_cluster(RvcCleanMode)
RvcCleanMode.server.commands = RvcCleanModeServerCommands:set_parent_cluster(RvcCleanMode)
RvcCleanMode.client.commands = RvcCleanModeClientCommands:set_parent_cluster(RvcCleanMode)
RvcCleanMode.types = RvcCleanModeTypes

function RvcCleanMode:get_attribute_by_id(attr_id)
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

function RvcCleanMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function RvcCleanMode:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x0001] = "ChangeToModeResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

RvcCleanMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["StartUpMode"] = "server",
  ["OnMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

RvcCleanMode.command_direction_map = {
  ["ChangeToMode"] = "server",
  ["ChangeToModeResponse"] = "client",
}

RvcCleanMode.FeatureMap = RvcCleanMode.types.Feature

function RvcCleanMode.are_features_supported(feature, feature_map)
  if (RvcCleanMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = RvcCleanMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, RvcCleanMode.NAME))
  end
  return RvcCleanMode[direction].attributes[key]
end
RvcCleanMode.attributes = {}
setmetatable(RvcCleanMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = RvcCleanMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, RvcCleanMode.NAME))
  end
  return RvcCleanMode[direction].commands[key]
end
RvcCleanMode.commands = {}
setmetatable(RvcCleanMode.commands, command_helper_mt)

setmetatable(RvcCleanMode, {__index = cluster_base})

return RvcCleanMode

