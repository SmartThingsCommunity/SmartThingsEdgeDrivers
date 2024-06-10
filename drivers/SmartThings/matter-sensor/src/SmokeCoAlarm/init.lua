local cluster_base = require "st.matter.cluster_base"
local SmokeCoAlarmServerAttributes = require "SmokeCoAlarm.server.attributes"
local SmokeCoAlarmServerCommands = require "SmokeCoAlarm.server.commands"
local SmokeCoAlarmTypes = require "SmokeCoAlarm.types"

local SmokeCoAlarm = {}

SmokeCoAlarm.ID = 0x005C
SmokeCoAlarm.NAME = "SmokeCoAlarm"
SmokeCoAlarm.server = {}
SmokeCoAlarm.client = {}
SmokeCoAlarm.server.attributes = SmokeCoAlarmServerAttributes:set_parent_cluster(SmokeCoAlarm)
SmokeCoAlarm.server.commands = SmokeCoAlarmServerCommands:set_parent_cluster(SmokeCoAlarm)
SmokeCoAlarm.types = SmokeCoAlarmTypes

function SmokeCoAlarm:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "ExpressedState",
    [0x0001] = "SmokeState",
    [0x0002] = "COState",
    [0x0003] = "BatteryAlert",
    [0x0004] = "DeviceMuted",
    [0x0005] = "TestInProgress",
    [0x0006] = "HardwareFaultAlert",
    [0x0007] = "EndOfServiceAlert",
    [0x0008] = "InterconnectSmokeAlarm",
    [0x0009] = "InterconnectCOAlarm",
    [0x000A] = "ContaminationState",
    [0x000B] = "SmokeSensitivityLevel",
    [0x000C] = "ExpiryDate",
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

function SmokeCoAlarm:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "SelfTestRequest",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

SmokeCoAlarm.attribute_direction_map = {
  ["ExpressedState"] = "server",
  ["SmokeState"] = "server",
  ["COState"] = "server",
  ["BatteryAlert"] = "server",
  ["DeviceMuted"] = "server",
  ["TestInProgress"] = "server",
  ["HardwareFaultAlert"] = "server",
  ["EndOfServiceAlert"] = "server",
  ["InterconnectSmokeAlarm"] = "server",
  ["InterconnectCOAlarm"] = "server",
  ["ContaminationState"] = "server",
  ["SmokeSensitivityLevel"] = "server",
  ["ExpiryDate"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

SmokeCoAlarm.command_direction_map = {
  ["SelfTestRequest"] = "server",
}

SmokeCoAlarm.FeatureMap = SmokeCoAlarm.types.Feature

function SmokeCoAlarm.are_features_supported(feature, feature_map)
  if (SmokeCoAlarm.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = SmokeCoAlarm.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, SmokeCoAlarm.NAME))
  end
  return SmokeCoAlarm[direction].attributes[key]
end
SmokeCoAlarm.attributes = {}
setmetatable(SmokeCoAlarm.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = SmokeCoAlarm.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, SmokeCoAlarm.NAME))
  end
  return SmokeCoAlarm[direction].commands[key]
end
SmokeCoAlarm.commands = {}
setmetatable(SmokeCoAlarm.commands, command_helper_mt)

setmetatable(SmokeCoAlarm, {__index = cluster_base})

return SmokeCoAlarm

