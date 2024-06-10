local cluster_base = require "st.matter.cluster_base"
local LaundryWasherModeServerAttributes = require "LaundryWasherMode.server.attributes"
local LaundryWasherModeServerCommands = require "LaundryWasherMode.server.commands"
local LaundryWasherModeTypes = require "LaundryWasherMode.types"

local LaundryWasherMode = {}

LaundryWasherMode.ID = 0x0051
LaundryWasherMode.NAME = "LaundryWasherMode"
LaundryWasherMode.server = {}
LaundryWasherMode.client = {}
LaundryWasherMode.server.attributes = LaundryWasherModeServerAttributes:set_parent_cluster(LaundryWasherMode)
LaundryWasherMode.server.commands = LaundryWasherModeServerCommands:set_parent_cluster(LaundryWasherMode)
LaundryWasherMode.types = LaundryWasherModeTypes

function LaundryWasherMode:get_attribute_by_id(attr_id)
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

function LaundryWasherMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

LaundryWasherMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["StartUpMode"] = "server",
  ["OnMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

LaundryWasherMode.command_direction_map = {
  ["ChangeToMode"] = "server",
  ["ChangeToModeResponse"] = "client",
}

LaundryWasherMode.FeatureMap = LaundryWasherMode.types.Feature

function LaundryWasherMode.are_features_supported(feature, feature_map)
  if (LaundryWasherMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end


local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = LaundryWasherMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, LaundryWasherMode.NAME))
  end
  return LaundryWasherMode[direction].attributes[key]
end
LaundryWasherMode.attributes = {}
setmetatable(LaundryWasherMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = LaundryWasherMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, LaundryWasherMode.NAME))
  end
  return LaundryWasherMode[direction].commands[key]
end
LaundryWasherMode.commands = {}
setmetatable(LaundryWasherMode.commands, command_helper_mt)

setmetatable(LaundryWasherMode, {__index = cluster_base})

return LaundryWasherMode
