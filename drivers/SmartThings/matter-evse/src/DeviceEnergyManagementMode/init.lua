local cluster_base = require "st.matter.cluster_base"
local DeviceEnergyManagementModeServerAttributes = require "DeviceEnergyManagementMode.server.attributes"
local DeviceEnergyManagementModeServerCommands = require "DeviceEnergyManagementMode.server.commands"
local DeviceEnergyManagementModeTypes = require "DeviceEnergyManagementMode.types"


local DeviceEnergyManagementMode = {}

DeviceEnergyManagementMode.ID = 0x009F
DeviceEnergyManagementMode.NAME = "DeviceEnergyManagementMode"
DeviceEnergyManagementMode.server = {}
DeviceEnergyManagementMode.server.attributes = DeviceEnergyManagementModeServerAttributes:set_parent_cluster(DeviceEnergyManagementMode)
DeviceEnergyManagementMode.server.commands = DeviceEnergyManagementModeServerCommands:set_parent_cluster(DeviceEnergyManagementMode)
DeviceEnergyManagementMode.types = DeviceEnergyManagementModeTypes
DeviceEnergyManagementMode.FeatureMap = DeviceEnergyManagementMode.types.Feature

function DeviceEnergyManagementMode.are_features_supported(feature, feature_map)
  if (DeviceEnergyManagementMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

function DeviceEnergyManagementMode:get_attribute_by_id(attr_id)
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

function DeviceEnergyManagementMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

-- Attribute Mapping
DeviceEnergyManagementMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["AttributeList"] = "server",
}

-- Command Mapping
DeviceEnergyManagementMode.command_direction_map = {
  ["ChangeToMode"] = "server",
}

-- Cluster Completion
local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = DeviceEnergyManagementMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, DeviceEnergyManagementMode.NAME))
  end
  return DeviceEnergyManagementMode[direction].attributes[key]
end
DeviceEnergyManagementMode.attributes = {}
setmetatable(DeviceEnergyManagementMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = DeviceEnergyManagementMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, DeviceEnergyManagementMode.NAME))
  end
  return DeviceEnergyManagementMode[direction].commands[key]
end
DeviceEnergyManagementMode.commands = {}
setmetatable(DeviceEnergyManagementMode.commands, command_helper_mt)

setmetatable(DeviceEnergyManagementMode, {__index = cluster_base})

return DeviceEnergyManagementMode