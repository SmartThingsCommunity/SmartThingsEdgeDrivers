local cluster_base = require "st.matter.cluster_base"
local ThreadBorderRouterManagementServerAttributes = require "ThreadBorderRouterManagement.server.attributes"
local ThreadBorderRouterManagementServerCommands = require "ThreadBorderRouterManagement.server.commands"
local ThreadBorderRouterManagementClientCommands = require "ThreadBorderRouterManagement.client.commands"
local ThreadBorderRouterManagementTypes = require "ThreadBorderRouterManagement.types"

local ThreadBorderRouterManagement = {}

ThreadBorderRouterManagement.ID = 0x0452
ThreadBorderRouterManagement.NAME = "ThreadBorderRouterManagement"
ThreadBorderRouterManagement.server = {}
ThreadBorderRouterManagement.client = {}
ThreadBorderRouterManagement.server.attributes = ThreadBorderRouterManagementServerAttributes:set_parent_cluster(ThreadBorderRouterManagement)
ThreadBorderRouterManagement.server.commands = ThreadBorderRouterManagementServerCommands:set_parent_cluster(ThreadBorderRouterManagement)
ThreadBorderRouterManagement.client.commands = ThreadBorderRouterManagementClientCommands:set_parent_cluster(ThreadBorderRouterManagement)
ThreadBorderRouterManagement.types = ThreadBorderRouterManagementTypes

function ThreadBorderRouterManagement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "BorderRouterName",
    [0x0001] = "BorderAgentID",
    [0x0002] = "ThreadVersion",
    [0x0003] = "InterfaceEnabled",
    [0x0004] = "ActiveDatasetTimestamp",
    [0x0005] = "PendingDatasetTimestamp",
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

function ThreadBorderRouterManagement:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "GetActiveDatasetRequest",
    [0x0001] = "GetPendingDatasetRequest",
    [0x0003] = "SetActiveDatasetRequest",
    [0x0004] = "SetPendingDatasetRequest",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function ThreadBorderRouterManagement:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x0002] = "DatasetResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

ThreadBorderRouterManagement.attribute_direction_map = {
  ["BorderRouterName"] = "server",
  ["BorderAgentID"] = "server",
  ["ThreadVersion"] = "server",
  ["InterfaceEnabled"] = "server",
  ["ActiveDatasetTimestamp"] = "server",
  ["PendingDatasetTimestamp"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

do
  local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.ThreadBorderRouterManagement.server.attributes")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      ThreadBorderRouterManagement.attribute_direction_map[alias] = "server"
    end
  end
end

ThreadBorderRouterManagement.command_direction_map = {
  ["GetActiveDatasetRequest"] = "server",
  ["GetPendingDatasetRequest"] = "server",
  ["SetActiveDatasetRequest"] = "server",
  ["SetPendingDatasetRequest"] = "server",
  ["DatasetResponse"] = "client",
}

do
  local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.ThreadBorderRouterManagement.server.commands")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      ThreadBorderRouterManagement.command_direction_map[alias] = "server"
    end
  end
end

do
  local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.ThreadBorderRouterManagement.client.commands")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      ThreadBorderRouterManagement.command_direction_map[alias] = "client"
    end
  end
end

ThreadBorderRouterManagement.FeatureMap = ThreadBorderRouterManagement.types.Feature

function ThreadBorderRouterManagement.are_features_supported(feature, feature_map)
  if (ThreadBorderRouterManagement.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ThreadBorderRouterManagement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ThreadBorderRouterManagement.NAME))
  end
  return ThreadBorderRouterManagement[direction].attributes[key]
end
ThreadBorderRouterManagement.attributes = {}
setmetatable(ThreadBorderRouterManagement.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ThreadBorderRouterManagement.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ThreadBorderRouterManagement.NAME))
  end
  return ThreadBorderRouterManagement[direction].commands[key]
end
ThreadBorderRouterManagement.commands = {}
setmetatable(ThreadBorderRouterManagement.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return ThreadBorderRouterManagement.server.events[key]
end
ThreadBorderRouterManagement.events = {}
setmetatable(ThreadBorderRouterManagement.events, event_helper_mt)

setmetatable(ThreadBorderRouterManagement, {__index = cluster_base})

return ThreadBorderRouterManagement

