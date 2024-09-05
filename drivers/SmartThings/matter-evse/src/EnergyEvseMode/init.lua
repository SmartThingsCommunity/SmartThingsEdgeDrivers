local cluster_base = require "st.matter.cluster_base"
local EnergyEvseModeServerAttributes = require "EnergyEvseMode.server.attributes"
local EnergyEvseModeServerCommands = require "EnergyEvseMode.server.commands"
local EnergyEvseModeTypes = require "EnergyEvseMode.types"

local EnergyEvseMode = {}

EnergyEvseMode.ID = 0x009D
EnergyEvseMode.NAME = "EnergyEvseMode"
EnergyEvseMode.server = {}
EnergyEvseMode.server.attributes = EnergyEvseModeServerAttributes:set_parent_cluster(EnergyEvseMode)
EnergyEvseMode.server.commands = EnergyEvseModeServerCommands:set_parent_cluster(EnergyEvseMode)
EnergyEvseMode.types = EnergyEvseModeTypes
EnergyEvseMode.FeatureMap = EnergyEvseMode.types.Feature

function EnergyEvseMode.are_features_supported(feature, feature_map)
  if (EnergyEvseMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

function EnergyEvseMode:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "SupportedModes",
    [0x0001] = "CurrentMode",
    [0xFFF9] = "AcceptedCommandList",
    [0xFFFB] = "AttributeList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

function EnergyEvseMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function EnergyEvseMode:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x0001] = "ChangeToModeResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

-- Attribute Mapping
EnergyEvseMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["AttributeList"] = "server",
}

-- Command Mapping
EnergyEvseMode.command_direction_map = {
  ["ChangeToMode"] = "server",
  ["ChangeToModeResponse"] = "client",
}

-- Cluster Completion
local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = EnergyEvseMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, EnergyEvseMode.NAME))
  end
  return EnergyEvseMode[direction].attributes[key]
end
EnergyEvseMode.attributes = {}
setmetatable(EnergyEvseMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = EnergyEvseMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, EnergyEvseMode.NAME))
  end
  return EnergyEvseMode[direction].commands[key]
end
EnergyEvseMode.commands = {}
setmetatable(EnergyEvseMode.commands, command_helper_mt)

setmetatable(EnergyEvseMode, {__index = cluster_base})

return EnergyEvseMode