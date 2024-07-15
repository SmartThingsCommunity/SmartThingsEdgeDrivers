local cluster_base = require "st.matter.cluster_base"
local RefrigeratorAndTemperatureControlledCabinetModeServerAttributes = require "RefrigeratorAndTemperatureControlledCabinetMode.server.attributes"
local RefrigeratorAndTemperatureControlledCabinetModeServerCommands = require "RefrigeratorAndTemperatureControlledCabinetMode.server.commands"
local RefrigeratorAndTemperatureControlledCabinetModeTypes = require "RefrigeratorAndTemperatureControlledCabinetMode.types"

local RefrigeratorAndTemperatureControlledCabinetMode = {}

RefrigeratorAndTemperatureControlledCabinetMode.ID = 0x0052
RefrigeratorAndTemperatureControlledCabinetMode.NAME = "RefrigeratorAndTemperatureControlledCabinetMode"
RefrigeratorAndTemperatureControlledCabinetMode.server = {}
RefrigeratorAndTemperatureControlledCabinetMode.client = {}
RefrigeratorAndTemperatureControlledCabinetMode.server.attributes = RefrigeratorAndTemperatureControlledCabinetModeServerAttributes:set_parent_cluster(RefrigeratorAndTemperatureControlledCabinetMode)
RefrigeratorAndTemperatureControlledCabinetMode.server.commands = RefrigeratorAndTemperatureControlledCabinetModeServerCommands:set_parent_cluster(RefrigeratorAndTemperatureControlledCabinetMode)
RefrigeratorAndTemperatureControlledCabinetMode.types = RefrigeratorAndTemperatureControlledCabinetModeTypes

function RefrigeratorAndTemperatureControlledCabinetMode:get_attribute_by_id(attr_id)
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

function RefrigeratorAndTemperatureControlledCabinetMode:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "ChangeToMode",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function RefrigeratorAndTemperatureControlledCabinetMode:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x0001] = "ChangeToModeResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

RefrigeratorAndTemperatureControlledCabinetMode.attribute_direction_map = {
  ["SupportedModes"] = "server",
  ["CurrentMode"] = "server",
  ["StartUpMode"] = "server",
  ["OnMode"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

RefrigeratorAndTemperatureControlledCabinetMode.command_direction_map = {
  ["ChangeToMode"] = "server",
  ["ChangeToModeResponse"] = "client",
}

RefrigeratorAndTemperatureControlledCabinetMode.FeatureMap = RefrigeratorAndTemperatureControlledCabinetMode.types.Feature

function RefrigeratorAndTemperatureControlledCabinetMode.are_features_supported(feature, feature_map)
  if (RefrigeratorAndTemperatureControlledCabinetMode.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = RefrigeratorAndTemperatureControlledCabinetMode.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, RefrigeratorAndTemperatureControlledCabinetMode.NAME))
  end
  return RefrigeratorAndTemperatureControlledCabinetMode[direction].attributes[key]
end
RefrigeratorAndTemperatureControlledCabinetMode.attributes = {}
setmetatable(RefrigeratorAndTemperatureControlledCabinetMode.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = RefrigeratorAndTemperatureControlledCabinetMode.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, RefrigeratorAndTemperatureControlledCabinetMode.NAME))
  end
  return RefrigeratorAndTemperatureControlledCabinetMode[direction].commands[key]
end
RefrigeratorAndTemperatureControlledCabinetMode.commands = {}
setmetatable(RefrigeratorAndTemperatureControlledCabinetMode.commands, command_helper_mt)

setmetatable(RefrigeratorAndTemperatureControlledCabinetMode, {__index = cluster_base})

return RefrigeratorAndTemperatureControlledCabinetMode
