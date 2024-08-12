local cluster_base = require "st.matter.cluster_base"
local RvcOperationalStateServerAttributes = require "RvcOperationalState.server.attributes"
local RvcOperationalStateServerCommands = require "RvcOperationalState.server.commands"
local RvcOperationalStateEvents = require "RvcOperationalState.server.events"
local RvcOperationalStateTypes = require "RvcOperationalState.types"

local RvcOperationalState = {}

RvcOperationalState.ID = 0x0061
RvcOperationalState.NAME = "RvcOperationalState"
RvcOperationalState.server = {}
RvcOperationalState.server.attributes = RvcOperationalStateServerAttributes:set_parent_cluster(RvcOperationalState)
RvcOperationalState.server.commands = RvcOperationalStateServerCommands:set_parent_cluster(RvcOperationalState)
RvcOperationalState.server.events = RvcOperationalStateEvents:set_parent_cluster(RvcOperationalState)
RvcOperationalState.types = RvcOperationalStateTypes

function RvcOperationalState:get_attribute_by_id(attr_id)
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

function RvcOperationalState:get_server_command_by_id(command_id)
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

function RvcOperationalState:get_event_by_id(event_id)
  local event_id_map = {
    [0x0000] = "OperationalError",
    [0x0001] = "OperationCompletion",
  }
  if event_id_map[event_id] ~= nil then
    return self.server.events[event_id_map[event_id]]
  end
  return nil
end

RvcOperationalState.attribute_direction_map = {
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

RvcOperationalState.command_direction_map = {
  ["Pause"] = "server",
  ["Stop"] = "server",
  ["Start"] = "server",
  ["Resume"] = "server",
  ["OperationalCommandResponse"] = "client",
}

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = RvcOperationalState.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, RvcOperationalState.NAME))
  end
  return RvcOperationalState[direction].attributes[key]
end
RvcOperationalState.attributes = {}
setmetatable(RvcOperationalState.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = RvcOperationalState.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, RvcOperationalState.NAME))
  end
  return RvcOperationalState[direction].commands[key]
end
RvcOperationalState.commands = {}
setmetatable(RvcOperationalState.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return RvcOperationalState.server.events[key]
end
RvcOperationalState.events = {}
setmetatable(RvcOperationalState.events, event_helper_mt)

setmetatable(RvcOperationalState, {__index = cluster_base})

return RvcOperationalState

