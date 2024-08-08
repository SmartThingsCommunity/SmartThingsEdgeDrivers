local cluster_base = require "st.matter.cluster_base"
local DishwasherModeServerAttributes = require "DishwasherMode.server.attributes"
local DishwasherModeServerCommands = require "DishwasherMode.server.commands"
local DishwasherModeTypes = require "DishwasherMode.types"

local DishwasherMode = {}

DishwasherMode.ID = 0x0059
DishwasherMode.NAME = "DishwasherMode"
DishwasherMode.server = {}
DishwasherMode.client = {}
DishwasherMode.server.attributes = DishwasherModeServerAttributes:set_parent_cluster(DishwasherMode)
DishwasherMode.server.commands = DishwasherModeServerCommands:set_parent_cluster(DishwasherMode)
DishwasherMode.types = DishwasherModeTypes

function DishwasherMode:get_attribute_by_id(attr_id)
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

function DishwasherMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

DishwasherMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["StartUpMode"] = "server",
  ["OnMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

DishwasherMode.command_direction_map = {
  ["ChangeToMode"] = "server",
  ["ChangeToModeResponse"] = "client",
}

DishwasherMode.FeatureMap = DishwasherMode.types.Feature

function DishwasherMode.are_features_supported(feature, feature_map)
  if (DishwasherMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = DishwasherMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, DishwasherMode.NAME))
  end
  return DishwasherMode[direction].attributes[key]
end
DishwasherMode.attributes = {}
setmetatable(DishwasherMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = DishwasherMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, DishwasherMode.NAME))
  end
  return DishwasherMode[direction].commands[key]
end
DishwasherMode.commands = {}
setmetatable(DishwasherMode.commands, command_helper_mt)

setmetatable(DishwasherMode, {__index = cluster_base})

return DishwasherMode

