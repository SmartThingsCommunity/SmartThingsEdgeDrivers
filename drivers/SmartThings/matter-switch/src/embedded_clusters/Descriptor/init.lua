local cluster_base = require "st.matter.cluster_base"
local DescriptorServerAttributes = require "embedded_clusters.Descriptor.server.attributes"

local Descriptor = {}

Descriptor.ID = 0x001D
Descriptor.NAME = "Descriptor"
Descriptor.server = {}
Descriptor.client = {}
Descriptor.server.attributes = DescriptorServerAttributes:set_parent_cluster(Descriptor)

function Descriptor:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0003] = "PartsList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

function Descriptor:get_server_command_by_id(command_id)
  local server_id_map = {
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

Descriptor.attribute_direction_map = {
  ["PartsList"] = "server",
}

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = Descriptor.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, Descriptor.NAME))
  end
  return Descriptor[direction].attributes[key]
end
Descriptor.attributes = {}
setmetatable(Descriptor.attributes, attribute_helper_mt)

setmetatable(Descriptor, {__index = cluster_base})

return Descriptor

