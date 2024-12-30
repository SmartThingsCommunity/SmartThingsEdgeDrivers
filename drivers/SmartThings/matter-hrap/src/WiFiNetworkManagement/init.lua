local cluster_base = require "st.matter.cluster_base"
local WiFiNetworkManagementServerAttributes = require "WiFiNetworkManagement.server.attributes"
local WiFiNetworkManagementServerCommands = require "WiFiNetworkManagement.server.commands"
local WiFiNetworkManagementClientCommands = require "WiFiNetworkManagement.client.commands"
local WiFiNetworkManagementTypes = require "WiFiNetworkManagement.types"

local WiFiNetworkManagement = {}

WiFiNetworkManagement.ID = 0x0451
WiFiNetworkManagement.NAME = "WiFiNetworkManagement"
WiFiNetworkManagement.server = {}
WiFiNetworkManagement.client = {}
WiFiNetworkManagement.server.attributes = WiFiNetworkManagementServerAttributes:set_parent_cluster(WiFiNetworkManagement)
WiFiNetworkManagement.server.commands = WiFiNetworkManagementServerCommands:set_parent_cluster(WiFiNetworkManagement)
WiFiNetworkManagement.client.commands = WiFiNetworkManagementClientCommands:set_parent_cluster(WiFiNetworkManagement)
WiFiNetworkManagement.types = WiFiNetworkManagementTypes

function WiFiNetworkManagement:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "Ssid",
    [0x0001] = "PassphraseSurrogate",
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

function WiFiNetworkManagement:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "NetworkPassphraseRequest",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

function WiFiNetworkManagement:get_client_command_by_id(command_id)
  local client_id_map = {
    [0x0001] = "NetworkPassphraseResponse",
  }
  if client_id_map[command_id] ~= nil then
    return self.client.commands[client_id_map[command_id]]
  end
  return nil
end

WiFiNetworkManagement.attribute_direction_map = {
  ["Ssid"] = "server",
  ["PassphraseSurrogate"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

do
  local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.WiFiNetworkManagement.server.attributes")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      WiFiNetworkManagement.attribute_direction_map[alias] = "server"
    end
  end
end

WiFiNetworkManagement.command_direction_map = {
  ["NetworkPassphraseRequest"] = "server",
  ["NetworkPassphraseResponse"] = "client",
}

do
  local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.WiFiNetworkManagement.server.commands")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      WiFiNetworkManagement.command_direction_map[alias] = "server"
    end
  end
end

do
  local has_aliases, aliases = pcall(require, "st.matter.clusters.aliases.WiFiNetworkManagement.client.commands")
  if has_aliases then
    for alias, _ in pairs(aliases) do
      WiFiNetworkManagement.command_direction_map[alias] = "client"
    end
  end
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = WiFiNetworkManagement.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, WiFiNetworkManagement.NAME))
  end
  return WiFiNetworkManagement[direction].attributes[key]
end
WiFiNetworkManagement.attributes = {}
setmetatable(WiFiNetworkManagement.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = WiFiNetworkManagement.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, WiFiNetworkManagement.NAME))
  end
  return WiFiNetworkManagement[direction].commands[key]
end
WiFiNetworkManagement.commands = {}
setmetatable(WiFiNetworkManagement.commands, command_helper_mt)

local event_helper_mt = {}
event_helper_mt.__index = function(self, key)
  return WiFiNetworkManagement.server.events[key]
end
WiFiNetworkManagement.events = {}
setmetatable(WiFiNetworkManagement.events, event_helper_mt)

setmetatable(WiFiNetworkManagement, {__index = cluster_base})

return WiFiNetworkManagement

