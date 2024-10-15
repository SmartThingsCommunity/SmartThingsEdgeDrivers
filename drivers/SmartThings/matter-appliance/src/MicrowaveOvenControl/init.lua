local cluster_base = require "st.matter.cluster_base"
local MicrowaveOvenControlServerAttributes = require "MicrowaveOvenControl.server.attributes"
local MicrowaveOvenControlServerCommands = require "MicrowaveOvenControl.server.commands"
local MicrowaveOvenControlTypes = require "MicrowaveOvenControl.types"

local MicrowaveOvenControl = {}

MicrowaveOvenControl.ID = 0x005F
MicrowaveOvenControl.NAME = "MicrowaveOvenControl"
MicrowaveOvenControl.server = {}
MicrowaveOvenControl.client = {}
MicrowaveOvenControl.server.attributes = MicrowaveOvenControlServerAttributes:set_parent_cluster(MicrowaveOvenControl)
MicrowaveOvenControl.server.commands = MicrowaveOvenControlServerCommands:set_parent_cluster(MicrowaveOvenControl)
MicrowaveOvenControl.types = MicrowaveOvenControlTypes

function MicrowaveOvenControl:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "CookTime",
    [0x0001] = "MaxCookTime",
    [0xFFF9] = "AcceptedCommandList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

function MicrowaveOvenControl:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "SetCookingParameters",
    [0x0001] = "AddMoreTime",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

MicrowaveOvenControl.attribute_direction_map = {
  ["CookTime"] = "server",
  ["MaxCookTime"] = "server",
  ["AcceptedCommandList"] = "server",
}

MicrowaveOvenControl.command_direction_map = {
  ["SetCookingParameters"] = "server",
  ["AddMoreTime"] = "server",
}

MicrowaveOvenControl.FeatureMap = MicrowaveOvenControl.types.Feature

function MicrowaveOvenControl.are_features_supported(feature, feature_map)
  if (MicrowaveOvenControl.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = MicrowaveOvenControl.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, MicrowaveOvenControl.NAME))
  end
  return MicrowaveOvenControl[direction].attributes[key]
end
MicrowaveOvenControl.attributes = {}
setmetatable(MicrowaveOvenControl.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = MicrowaveOvenControl.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, MicrowaveOvenControl.NAME))
  end
  return MicrowaveOvenControl[direction].commands[key]
end
MicrowaveOvenControl.commands = {}
setmetatable(MicrowaveOvenControl.commands, command_helper_mt)

setmetatable(MicrowaveOvenControl, {__index = cluster_base})

return MicrowaveOvenControl