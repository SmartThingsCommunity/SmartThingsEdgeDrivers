local cluster_base = require "st.matter.cluster_base"
local ClosureControlServerAttributes = require "embedded_clusters.ClosureControl.server.attributes"
local ClosureControlServerCommands = require "embedded_clusters.ClosureControl.server.commands"
local ClosureControlTypes = require "embedded_clusters.ClosureControl.types"

local ClosureControl = {}

ClosureControl.ID = 0x0104
ClosureControl.NAME = "ClosureControl"
ClosureControl.server = {}
ClosureControl.client = {}
ClosureControl.server.attributes = ClosureControlServerAttributes:set_parent_cluster(ClosureControl)
ClosureControl.server.commands = ClosureControlServerCommands:set_parent_cluster(ClosureControl)
ClosureControl.types = ClosureControlTypes

function ClosureControl:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "CountdownTime",
    [0x0001] = "MainState",
    [0x0002] = "CurrentErrorList",
    [0x0003] = "OverallCurrentState",
    [0x0004] = "OverallTargetState",
    [0x0005] = "LatchControlModes",
    [0xFFF9] = "AcceptedCommandList",
    [0xFFFB] = "AttributeList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

function ClosureControl:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "Stop",
    [0x0001] = "MoveTo",
    [0x0002] = "Calibrate",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end


ClosureControl.attribute_direction_map = {
  ["CountdownTime"] = "server",
  ["MainState"] = "server",
  ["CurrentErrorList"] = "server",
  ["OverallCurrentState"] = "server",
  ["OverallTargetState"] = "server",
  ["LatchControlModes"] = "server",
  ["AcceptedCommandList"] = "server",
  ["AttributeList"] = "server",
}

ClosureControl.command_direction_map = {
  ["Stop"] = "server",
  ["MoveTo"] = "server",
  ["Calibrate"] = "server",
}

ClosureControl.FeatureMap = ClosureControl.types.Feature

function ClosureControl.are_features_supported(feature, feature_map)
  if (ClosureControl.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ClosureControl.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ClosureControl.NAME))
  end
  return ClosureControl[direction].attributes[key]
end
ClosureControl.attributes = {}
setmetatable(ClosureControl.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ClosureControl.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ClosureControl.NAME))
  end
  return ClosureControl[direction].commands[key]
end
ClosureControl.commands = {}
setmetatable(ClosureControl.commands, command_helper_mt)

setmetatable(ClosureControl, {__index = cluster_base})

return ClosureControl
