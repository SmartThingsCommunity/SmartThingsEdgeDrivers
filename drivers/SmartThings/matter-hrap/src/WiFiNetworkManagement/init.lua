local cluster_base = require "st.matter.cluster_base"
local WiFiNetworkManagementServerAttributes = require "WiFiNetworkManagement.server.attributes"

local WiFiNetworkManagement = {}

WiFiNetworkManagement.ID = 0x0451
WiFiNetworkManagement.NAME = "WiFiNetworkManagement"
WiFiNetworkManagement.server = {}
WiFiNetworkManagement.client = {}
WiFiNetworkManagement.server.attributes = WiFiNetworkManagementServerAttributes:set_parent_cluster(WiFiNetworkManagement)

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

setmetatable(WiFiNetworkManagement, {__index = cluster_base})

return WiFiNetworkManagement

