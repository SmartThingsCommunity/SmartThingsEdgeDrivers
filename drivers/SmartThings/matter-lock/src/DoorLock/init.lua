local cluster_base = require "st.matter.cluster_base"
local DoorLockServerAttributes = require "DoorLock.server.attributes"
local DoorLockServerCommands = require "DoorLock.server.commands"
local DoorLockClientCommands = require "DoorLock.client.commands"
local DoorLockEvents = require "DoorLock.server.events"
local DoorLockTypes = require "DoorLock.types"

local DoorLock = {}

DoorLock.ID = 0x0101
DoorLock.NAME = "DoorLock"
DoorLock.server = {}
DoorLock.client = {}
DoorLock.server.attributes = DoorLockServerAttributes:set_parent_cluster(DoorLock)
DoorLock.server.commands = DoorLockServerCommands:set_parent_cluster(DoorLock)
DoorLock.client.commands = DoorLockClientCommands:set_parent_cluster(DoorLock)
DoorLock.server.events = DoorLockEvents:set_parent_cluster(DoorLock)
DoorLock.types = DoorLockTypes

function DoorLock:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "LockState",
    [0x0001] = "LockType",
    [0x0002] = "ActuatorEnabled",
    [0x0003] = "DoorState",
    [0x0004] = "DoorOpenEvents",
    [0x0005] = "DoorClosedEvents",
    [0x0006] = "OpenPeriod",
    [0x0011] = "NumberOfTotalUsersSupported",
    [0x0012] = "NumberOfPINUsersSupported",
    [0x0013] = "NumberOfRFIDUsersSupported",
    [0x0014] = "NumberOfWeekDaySchedulesSupportedPerUser",
    [0x0015] = "NumberOfYearDaySchedulesSupportedPerUser",
    [0x0016] = "NumberOfHolidaySchedulesSupported",
    [0x0017] = "MaxPINCodeLength",
    [0x0018] = "MinPINCodeLength",
    [0x0019] = "MaxRFIDCodeLength",
    [0x001A] = "MinRFIDCodeLength",
    [0x001B] = "CredentialRulesSupport",
    [0x001C] = "NumberOfCredentialsSupportedPerUser",
    [0x0021] = "Language",
    [0x0022] = "LEDSettings",
    [0x0023] = "AutoRelockTime",
    [0x0024] = "SoundVolume",
    [0x0025] = "OperatingMode",
    [0x0026] = "SupportedOperatingModes",
    [0x0027] = "DefaultConfigurationRegister",
    [0x0028] = "EnableLocalProgramming",
    [0x0029] = "EnableOneTouchLocking",
    [0x002A] = "EnableInsideStatusLED",
    [0x002B] = "EnablePrivacyModeButton",
    [0x002C] = "LocalProgrammingFeatures",
    [0x0030] = "WrongCodeEntryLimit",
    [0x0031] = "UserCodeTemporaryDisableTime",
    [0x0032] = "SendPINOverTheAir",
    [0x0033] = "RequirePINforRemoteOperation",
    [0x0035] = "ExpiringUserTimeout",
    [0x0080] = "AliroReaderVerificationKey",
    [0x0081] = "AliroReaderGroupIdentifier",
    [0x0082] = "AliroReaderGroupSubIdentifier",
    [0x0083] = "AliroExpeditedTransactionSupportedProtocolVersions",
    [0x0084] = "AliroGroupResolvingKey",
    [0x0085] = "AliroSupportedBLEUWBProtocolVersions",
    [0x0086] = "AliroBLEAdvertisingVersion",
    [0x0087] = "NumberOfAliroCredentialIssuerKeysSupported",
    [0x0088] = "NumberOfAliroEndpointKeysSupported",
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

function DoorLock:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "LockDoor",
    [0x0001] = "UnlockDoor",
    [0x0003] = "UnlockWithTimeout",
    [0x000B] = "SetWeekDaySchedule",
    [0x000C] = "GetWeekDaySchedule",
    [0x000D] = "ClearWeekDaySchedule",
    [0x000E] = "SetYearDaySchedule",
    [0x000F] = "GetYearDaySchedule",
    [0x0010] = "ClearYearDaySchedule",
    [0x0011] = "SetHolidaySchedule",
    [0x0012] = "GetHolidaySchedule",
    [0x0013] = "ClearHolidaySchedule",
    [0x001A] = "SetUser",
    [0x001B] = "GetUser",
    [0x001D] = "ClearUser",
    [0x0022] = "SetCredential",
    [0x0024] = "GetCredentialStatus",
    [0x0026] = "ClearCredential",
    [0x0027] = "UnboltDoor",
    [0x0028] = "SetAliroReaderConfig",
    [0x0029] = "ClearAliroReaderConfig",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function DoorLock:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x000C] = "GetWeekDayScheduleResponse",
    [0x000F] = "GetYearDayScheduleResponse",
    [0x0012] = "GetHolidayScheduleResponse",
    [0x001C] = "GetUserResponse",
    [0x0023] = "SetCredentialResponse",
    [0x0025] = "GetCredentialStatusResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

function DoorLock:get_event_by_id(event_id)
  local event_id_map = {
    [0x0000] = "DoorLockAlarm",
    [0x0001] = "DoorStateChange",
    [0x0002] = "LockOperation",
    [0x0003] = "LockOperationError",
    [0x0004] = "LockUserChange",
  }
  if event_id_map[event_id] ~= nil then
    return self.server.events[event_id_map[event_id]]
  end
  return nil
end

DoorLock.attribute_direction_map = {
  ["LockState"] = "server",
  ["LockType"] = "server",
  ["ActuatorEnabled"] = "server",
  ["DoorState"] = "server",
  ["DoorOpenEvents"] = "server",
  ["DoorClosedEvents"] = "server",
  ["OpenPeriod"] = "server",
  ["NumberOfTotalUsersSupported"] = "server",
  ["NumberOfPINUsersSupported"] = "server",
  ["NumberOfRFIDUsersSupported"] = "server",
  ["NumberOfWeekDaySchedulesSupportedPerUser"] = "server",
  ["NumberOfYearDaySchedulesSupportedPerUser"] = "server",
  ["NumberOfHolidaySchedulesSupported"] = "server",
  ["MaxPINCodeLength"] = "server",
  ["MinPINCodeLength"] = "server",
  ["MaxRFIDCodeLength"] = "server",
  ["MinRFIDCodeLength"] = "server",
  ["CredentialRulesSupport"] = "server",
  ["NumberOfCredentialsSupportedPerUser"] = "server",
  ["Language"] = "server",
  ["LEDSettings"] = "server",
  ["AutoRelockTime"] = "server",
  ["SoundVolume"] = "server",
  ["OperatingMode"] = "server",
  ["SupportedOperatingModes"] = "server",
  ["DefaultConfigurationRegister"] = "server",
  ["EnableLocalProgramming"] = "server",
  ["EnableOneTouchLocking"] = "server",
  ["EnableInsideStatusLED"] = "server",
  ["EnablePrivacyModeButton"] = "server",
  ["LocalProgrammingFeatures"] = "server",
  ["WrongCodeEntryLimit"] = "server",
  ["UserCodeTemporaryDisableTime"] = "server",
  ["SendPINOverTheAir"] = "server",
  ["RequirePINforRemoteOperation"] = "server",
  ["ExpiringUserTimeout"] = "server",
  ["AliroReaderVerificationKey"] = "server",
  ["AliroReaderGroupIdentifier"] = "server",
  ["AliroReaderGroupSubIdentifier"] = "server",
  ["AliroExpeditedTransactionSupportedProtocolVersions"] = "server",
  ["AliroGroupResolvingKey"] = "server",
  ["AliroSupportedBLEUWBProtocolVersions"] = "server",
  ["AliroBLEAdvertisingVersion"] = "server",
  ["NumberOfAliroCredentialIssuerKeysSupported"] = "server",
  ["NumberOfAliroEndpointKeysSupported"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

DoorLock.command_direction_map = {
  ["LockDoor"] = "server",
  ["UnlockDoor"] = "server",
  ["UnlockWithTimeout"] = "server",
  ["SetWeekDaySchedule"] = "server",
  ["GetWeekDaySchedule"] = "server",
  ["ClearWeekDaySchedule"] = "server",
  ["SetYearDaySchedule"] = "server",
  ["GetYearDaySchedule"] = "server",
  ["ClearYearDaySchedule"] = "server",
  ["SetHolidaySchedule"] = "server",
  ["GetHolidaySchedule"] = "server",
  ["ClearHolidaySchedule"] = "server",
  ["SetUser"] = "server",
  ["GetUser"] = "server",
  ["ClearUser"] = "server",
  ["SetCredential"] = "server",
  ["GetCredentialStatus"] = "server",
  ["ClearCredential"] = "server",
  ["UnboltDoor"] = "server",
  ["SetAliroReaderConfig"] = "server",
  ["ClearAliroReaderConfig"] = "server",
  ["GetWeekDayScheduleResponse"] = "client",
  ["GetYearDayScheduleResponse"] = "client",
  ["GetHolidayScheduleResponse"] = "client",
  ["GetUserResponse"] = "client",
  ["SetCredentialResponse"] = "client",
  ["GetCredentialStatusResponse"] = "client",
}

DoorLock.FeatureMap = DoorLock.types.Feature

function DoorLock.are_features_supported(feature, feature_map)
  if (DoorLock.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = DoorLock.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, DoorLock.NAME))
  end
  return DoorLock[direction].attributes[key]
end
DoorLock.attributes = {}
setmetatable(DoorLock.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = DoorLock.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, DoorLock.NAME))
  end
  return DoorLock[direction].commands[key]
end
DoorLock.commands = {}
setmetatable(DoorLock.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return DoorLock.server.events[key]
end
DoorLock.events = {}
setmetatable(DoorLock.events, event_helper_mt)

setmetatable(DoorLock, {__index = cluster_base})

return DoorLock