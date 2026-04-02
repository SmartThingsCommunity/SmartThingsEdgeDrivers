-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local WaterHeaterModeServerAttributes = require "embedded_clusters.WaterHeaterMode.server.attributes"
local WaterHeaterModeServerCommands = require "embedded_clusters.WaterHeaterMode.server.commands"
local WaterHeaterModeTypes = require "embedded_clusters.WaterHeaterMode.types"

local WaterHeaterMode = {}

WaterHeaterMode.ID = 0x009E
WaterHeaterMode.NAME = "WaterHeaterMode"
WaterHeaterMode.server = {}
WaterHeaterMode.client = {}
WaterHeaterMode.server.attributes = WaterHeaterModeServerAttributes:set_parent_cluster(WaterHeaterMode)
WaterHeaterMode.server.commands = WaterHeaterModeServerCommands:set_parent_cluster(WaterHeaterMode)
WaterHeaterMode.types = WaterHeaterModeTypes

function WaterHeaterMode:get_attribute_by_id(attr_id)
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

function WaterHeaterMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

WaterHeaterMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["StartUpMode"] = "server",
  ["OnMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

WaterHeaterMode.command_direction_map = {
  ["ChangeToMode"] = "server",
  ["ChangeToModeResponse"] = "client",
}

WaterHeaterMode.FeatureMap = WaterHeaterMode.types.Feature

function WaterHeaterMode.are_features_supported(feature, feature_map)
  if (WaterHeaterMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = WaterHeaterMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, WaterHeaterMode.NAME))
  end
  return WaterHeaterMode[direction].attributes[key]
end
WaterHeaterMode.attributes = {}
setmetatable(WaterHeaterMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = WaterHeaterMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, WaterHeaterMode.NAME))
  end
  return WaterHeaterMode[direction].commands[key]
end
WaterHeaterMode.commands = {}
setmetatable(WaterHeaterMode.commands, command_helper_mt)

setmetatable(WaterHeaterMode, {__index = cluster_base})

return WaterHeaterMode

