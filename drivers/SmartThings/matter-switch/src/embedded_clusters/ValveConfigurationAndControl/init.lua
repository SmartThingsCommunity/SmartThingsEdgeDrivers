local cluster_base = require "st.matter.cluster_base"
local ValveConfigurationAndControlServerAttributes = require "ValveConfigurationAndControl.server.attributes"
local ValveConfigurationAndControlServerCommands = require "ValveConfigurationAndControl.server.commands"
local ValveConfigurationAndControlTypes = require "ValveConfigurationAndControl.types"
local ValveConfigurationAndControl = {}

ValveConfigurationAndControl.ID = 0x0081
ValveConfigurationAndControl.NAME = "ValveConfigurationAndControl"
ValveConfigurationAndControl.server = {}
ValveConfigurationAndControl.client = {}
ValveConfigurationAndControl.server.attributes = ValveConfigurationAndControlServerAttributes:set_parent_cluster(ValveConfigurationAndControl)
ValveConfigurationAndControl.server.commands = ValveConfigurationAndControlServerCommands:set_parent_cluster(ValveConfigurationAndControl)
ValveConfigurationAndControl.types = ValveConfigurationAndControlTypes

function ValveConfigurationAndControl:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "OpenDuration",
    [0x0001] = "DefaultOpenDuration",
    [0x0002] = "AutoCloseTime",
    [0x0003] = "RemainingDuration",
    [0x0004] = "CurrentState",
    [0x0005] = "TargetState",
    [0x0006] = "CurrentLevel",
    [0x0007] = "TargetLevel",
    [0x0008] = "DefaultOpenLevel",
    [0x0009] = "ValveFault",
    [0x000A] = "LevelStep",
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

function ValveConfigurationAndControl:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "Open",
    [0x0001] = "Close",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function ValveConfigurationAndControl:get_event_by_id(event_id)
  local event_id_map = {
    [0x0000] = "ValveStateChanged",
    [0x0001] = "ValveFault",
  }
  if event_id_map[event_id] ~= nil then
    return self.server.events[event_id_map[event_id]]
  end
  return nil
end

ValveConfigurationAndControl.attribute_direction_map = {
  ["OpenDuration"] = "server",
  ["DefaultOpenDuration"] = "server",
  ["AutoCloseTime"] = "server",
  ["RemainingDuration"] = "server",
  ["CurrentState"] = "server",
  ["TargetState"] = "server",
  ["CurrentLevel"] = "server",
  ["TargetLevel"] = "server",
  ["DefaultOpenLevel"] = "server",
  ["ValveFault"] = "server",
  ["LevelStep"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

ValveConfigurationAndControl.command_direction_map = {
  ["Open"] = "server",
  ["Close"] = "server",
}

ValveConfigurationAndControl.FeatureMap = ValveConfigurationAndControl.types.Feature

function ValveConfigurationAndControl.are_features_supported(feature, feature_map)
  if (ValveConfigurationAndControl.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ValveConfigurationAndControl.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ValveConfigurationAndControl.NAME))
  end
  return ValveConfigurationAndControl[direction].attributes[key]
end
ValveConfigurationAndControl.attributes = {}
setmetatable(ValveConfigurationAndControl.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ValveConfigurationAndControl.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ValveConfigurationAndControl.NAME))
  end
  return ValveConfigurationAndControl[direction].commands[key]
end
ValveConfigurationAndControl.commands = {}
setmetatable(ValveConfigurationAndControl.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return ValveConfigurationAndControl.server.events[key]
end
ValveConfigurationAndControl.events = {}
setmetatable(ValveConfigurationAndControl.events, event_helper_mt)

setmetatable(ValveConfigurationAndControl, {__index = cluster_base})

return ValveConfigurationAndControl
