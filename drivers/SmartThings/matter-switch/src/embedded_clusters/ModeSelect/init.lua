-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local cluster_base = require "st.matter.cluster_base"
local ModeSelectServerAttributes = require "embedded_clusters.ModeSelect.server.attributes"
local ModeSelectServerCommands = require "embedded_clusters.ModeSelect.server.commands"
local ModeSelectTypes = require "embedded_clusters.ModeSelect.types"

local ModeSelect = {}

ModeSelect.ID = 0x0050
ModeSelect.NAME = "ModeSelect"
ModeSelect.server = {}
ModeSelect.client = {}
ModeSelect.server.attributes = ModeSelectServerAttributes:set_parent_cluster(ModeSelect)
ModeSelect.server.commands = ModeSelectServerCommands:set_parent_cluster(ModeSelect)
ModeSelect.types = ModeSelectTypes

function ModeSelect:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "Description",
    [0x0001] = "StandardNamespace",
    [0x0002] = "SupportedModes",
    [0x0003] = "CurrentMode",
    [0x0004] = "StartUpMode",
    [0x0005] = "OnMode",
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

function ModeSelect:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

ModeSelect.attribute_direction_map = {
  ["Description"] = "server",
  ["StandardNamespace"] = "server",
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["StartUpMode"] = "server",
  ["OnMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

ModeSelect.command_direction_map = {
  ["ChangeToMode"] = "server",
}

ModeSelect.FeatureMap = ModeSelect.types.Feature

function ModeSelect.are_features_supported(feature, feature_map)
  if (ModeSelect.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ModeSelect.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ModeSelect.NAME))
  end
  return ModeSelect[direction].attributes[key]
end
ModeSelect.attributes = {}
setmetatable(ModeSelect.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ModeSelect.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ModeSelect.NAME))
  end
  return ModeSelect[direction].commands[key]
end
ModeSelect.commands = {}
setmetatable(ModeSelect.commands, command_helper_mt)

setmetatable(ModeSelect, {__index = cluster_base})

return ModeSelect
