local cluster_base = require "st.matter.cluster_base"
local OperationalStateServerAttributes = require "OperationalState.server.attributes"
local OperationalStateServerCommands = require "OperationalState.server.commands"
local OperationalStateEvents = require "OperationalState.server.events"
local OperationalStateTypes = require "OperationalState.types"

local OperationalState = {}

OperationalState.ID = 0x0060
OperationalState.NAME = "OperationalState"
OperationalState.server = {}
OperationalState.client = {}
OperationalState.server.attributes = OperationalStateServerAttributes:set_parent_cluster(OperationalState)
OperationalState.server.commands = OperationalStateServerCommands:set_parent_cluster(OperationalState)
OperationalState.server.events = OperationalStateEvents:set_parent_cluster(OperationalState)
OperationalState.types = OperationalStateTypes

function OperationalState:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "PhaseList",
    [0x0001] = "CurrentPhase",
    [0x0002] = "CountdownTime",
    [0x0003] = "OperationalStateList",
    [0x0004] = "OperationalState",
    [0x0005] = "OperationalError",
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

function OperationalState:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "Pause",
    [0x0001] = "Stop",
    [0x0002] = "Start",
    [0x0003] = "Resume",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function OperationalState:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x0004] = "OperationalCommandResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

function OperationalState:get_event_by_id(event_id)
  local event_id_map = {
    [0x0000] = "OperationalError",
    [0x0001] = "OperationCompletion",
  }
  if event_id_map[event_id] ~= nil then
    return self.server.events[event_id_map[event_id]]
  end
  return nil
end

OperationalState.attribute_direction_map = {
  ["PhaseList"] = "server",
  ["CurrentPhase"] = "server",
  ["CountdownTime"] = "server",
  ["OperationalStateList"] = "server",
  ["OperationalState"] = "server",
  ["OperationalError"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

OperationalState.command_direction_map = {
  ["Pause"] = "server",
  ["Stop"] = "server",
  ["Start"] = "server",
  ["Resume"] = "server",
  ["OperationalCommandResponse"] = "client",
}

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = OperationalState.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, OperationalState.NAME))
  end
  return OperationalState[direction].attributes[key]
end
OperationalState.attributes = {}
setmetatable(OperationalState.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = OperationalState.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, OperationalState.NAME))
  end
  return OperationalState[direction].commands[key]
end
OperationalState.commands = {}
setmetatable(OperationalState.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return OperationalState.server.events[key]
end
OperationalState.events = {}
setmetatable(OperationalState.events, event_helper_mt)

setmetatable(OperationalState, {__index = cluster_base})

return OperationalState
