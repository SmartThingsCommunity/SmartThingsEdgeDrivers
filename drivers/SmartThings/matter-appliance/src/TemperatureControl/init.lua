local cluster_base = require "st.matter.cluster_base"
local TemperatureControlServerAttributes = require "TemperatureControl.server.attributes"
local TemperatureControlServerCommands = require "TemperatureControl.server.commands"
local TemperatureControlTypes = require "TemperatureControl.types"

local TemperatureControl = {}

TemperatureControl.ID = 0x0056
TemperatureControl.NAME = "TemperatureControl"
TemperatureControl.server = {}
TemperatureControl.client = {}
TemperatureControl.server.attributes = TemperatureControlServerAttributes:set_parent_cluster(TemperatureControl)
TemperatureControl.server.commands = TemperatureControlServerCommands:set_parent_cluster(TemperatureControl)
TemperatureControl.types = TemperatureControlTypes

function TemperatureControl:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "TemperatureSetpoint",
    [0x0001] = "MinTemperature",
    [0x0002] = "MaxTemperature",
    [0x0003] = "Step",
    [0x0004] = "SelectedTemperatureLevel",
    [0x0005] = "SupportedTemperatureLevels",
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

function TemperatureControl:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "SetTemperature",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

TemperatureControl.attribute_direction_map = {
  ["TemperatureSetpoint"] = "server",
  ["MinTemperature"] = "server",
  ["MaxTemperature"] = "server",
  ["Step"] = "server",
  ["SelectedTemperatureLevel"] = "server",
  ["SupportedTemperatureLevels"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

TemperatureControl.command_direction_map = {
  ["SetTemperature"] = "server",
}

TemperatureControl.FeatureMap = TemperatureControl.types.Feature

function TemperatureControl.are_features_supported(feature, feature_map)
  if (TemperatureControl.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end


local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = TemperatureControl.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, TemperatureControl.NAME))
  end
  return TemperatureControl[direction].attributes[key]
end
TemperatureControl.attributes = {}
setmetatable(TemperatureControl.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = TemperatureControl.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, TemperatureControl.NAME))
  end
  return TemperatureControl[direction].commands[key]
end
TemperatureControl.commands = {}
setmetatable(TemperatureControl.commands, command_helper_mt)

setmetatable(TemperatureControl, {__index = cluster_base})

return TemperatureControl
