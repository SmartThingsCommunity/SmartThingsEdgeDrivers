local cluster_base = require "st.matter.cluster_base"
local EnergyEvseServerAttributes = require "EnergyEvse.server.attributes"
local EnergyEvseServerCommands = require "EnergyEvse.server.commands"
local EnergyEvseEvents = require "EnergyEvse.server.events"
local EnergyEvseTypes = require "EnergyEvse.types"

local EnergyEvse = {}

EnergyEvse.ID = 0x0099
EnergyEvse.NAME = "EnergyEvse"
EnergyEvse.server = {}
EnergyEvse.client = {}
EnergyEvse.server.attributes = EnergyEvseServerAttributes:set_parent_cluster(EnergyEvse)
EnergyEvse.server.commands = EnergyEvseServerCommands:set_parent_cluster(EnergyEvse)
EnergyEvse.server.events = EnergyEvseEvents:set_parent_cluster(EnergyEvse)
EnergyEvse.types = EnergyEvseTypes
EnergyEvse.FeatureMap = EnergyEvse.types.Feature

function EnergyEvse.are_features_supported(feature, feature_map)
  if (EnergyEvse.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

function EnergyEvse:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "State",
    [0x0001] = "SupplyState",
    [0x0002] = "FaultState",
    [0x0003] = "ChargingEnabledUntil",
    [0x0004] = "DischargingEnabledUntil",
    [0x0005] = "CircuitCapacity",
    [0x0006] = "MinimumChargeCurrent",
    [0x0007] = "MaximumChargeCurrent",
    [0x0008] = "MaximumDischargeCurrent",
    [0x0009] = "UserMaximumChargeCurrent",
    [0x000A] = "RandomizationDelayWindow",
    [0x0023] = "NextChargeStartTime",
    [0x0024] = "NextChargeTargetTime",
    [0x0025] = "NextChargeRequiredEnergy",
    [0x0026] = "NextChargeTargetSoC",
    [0x0027] = "ApproximateEVEfficiency",
    [0x0030] = "StateOfCharge",
    [0x0031] = "BatteryCapacity",
    [0x0032] = "VehicleID",
    [0x0040] = "SessionID",
    [0x0041] = "SessionDuration",
    [0x0042] = "SessionEnergyCharged",
    [0x0043] = "SessionEnergyDischarged",
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

function EnergyEvse:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0001] = "Disable",
    [0x0002] = "EnableCharging",
    [0x0003] = "EnableDischarging",
    [0x0004] = "StartDiagnostics",
    [0x0005] = "SetTargets",
    [0x0006] = "GetTargets",
    [0x0007] = "ClearTargets",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function EnergyEvse:get_event_by_id(event_id)
  local event_id_map = {
    [0x0000] = "EVConnected",
    [0x0001] = "EVNotDetected",
    [0x0002] = "EnergyTransferStarted",
    [0x0003] = "EnergyTransferStopped",
    [0x0004] = "Fault",
    [0x0005] = "Rfid",
  }
  if event_id_map[event_id] ~= nil then
    return self.server.events[event_id_map[event_id]]
  end
  return nil
end
EnergyEvse.attribute_direction_map = {
  ["State"] = "server",
  ["SupplyState"] = "server",
  ["FaultState"] = "server",
  ["ChargingEnabledUntil"] = "server",
  ["DischargingEnabledUntil"] = "server",
  ["CircuitCapacity"] = "server",
  ["MinimumChargeCurrent"] = "server",
  ["MaximumChargeCurrent"] = "server",
  ["MaximumDischargeCurrent"] = "server",
  ["UserMaximumChargeCurrent"] = "server",
  ["RandomizationDelayWindow"] = "server",
  ["NextChargeStartTime"] = "server",
  ["NextChargeTargetTime"] = "server",
  ["NextChargeRequiredEnergy"] = "server",
  ["NextChargeTargetSoC"] = "server",
  ["ApproximateEVEfficiency"] = "server",
  ["StateOfCharge"] = "server",
  ["BatteryCapacity"] = "server",
  ["VehicleID"] = "server",
  ["SessionID"] = "server",
  ["SessionDuration"] = "server",
  ["SessionEnergyCharged"] = "server",
  ["SessionEnergyDischarged"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

EnergyEvse.command_direction_map = {
  ["Disable"] = "server",
  ["EnableCharging"] = "server",
  ["EnableDischarging"] = "server",
  ["StartDiagnostics"] = "server",
  ["SetTargets"] = "server",
  ["GetTargets"] = "server",
  ["ClearTargets"] = "server",
}

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = EnergyEvse.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, EnergyEvse.NAME))
  end
  return EnergyEvse[direction].attributes[key]
end
EnergyEvse.attributes = {}
setmetatable(EnergyEvse.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = EnergyEvse.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, EnergyEvse.NAME))
  end
  return EnergyEvse[direction].commands[key]
end
EnergyEvse.commands = {}
setmetatable(EnergyEvse.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return EnergyEvse.server.events[key]
end
EnergyEvse.events = {}
setmetatable(EnergyEvse.events, event_helper_mt)

setmetatable(EnergyEvse, {__index = cluster_base})

return EnergyEvse