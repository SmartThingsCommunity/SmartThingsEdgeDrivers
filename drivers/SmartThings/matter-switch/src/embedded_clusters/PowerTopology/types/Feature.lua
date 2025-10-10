local data_types = require "st.matter.data_types"
local UintABC = require "st.matter.data_types.base_defs.UintABC"

local Feature = {}
local new_mt = UintABC.new_mt({NAME = "Feature", ID = data_types.name_to_id_map["Uint32"]}, 4)

Feature.BASE_MASK = 0xFFFF
Feature.NODE_TOPOLOGY = 0x0001
Feature.TREE_TOPOLOGY = 0x0002
Feature.SET_TOPOLOGY = 0x0004
Feature.DYNAMIC_POWER_FLOW = 0x0008

Feature.mask_fields = {
  BASE_MASK = 0xFFFF,
  NODE_TOPOLOGY = 0x0001,
  TREE_TOPOLOGY = 0x0002,
  SET_TOPOLOGY = 0x0004,
  DYNAMIC_POWER_FLOW = 0x0008,
}

Feature.is_node_topology_set = function(self)
  return (self.value & self.NODE_TOPOLOGY) ~= 0
end

Feature.set_node_topology = function(self)
  if self.value ~= nil then
    self.value = self.value | self.NODE_TOPOLOGY
  else
    self.value = self.NODE_TOPOLOGY
  end
end

Feature.unset_node_topology = function(self)
  self.value = self.value & (~self.NODE_TOPOLOGY & self.BASE_MASK)
end
Feature.is_tree_topology_set = function(self)
  return (self.value & self.TREE_TOPOLOGY) ~= 0
end

Feature.set_tree_topology = function(self)
  if self.value ~= nil then
    self.value = self.value | self.TREE_TOPOLOGY
  else
    self.value = self.TREE_TOPOLOGY
  end
end

Feature.unset_tree_topology = function(self)
  self.value = self.value & (~self.TREE_TOPOLOGY & self.BASE_MASK)
end
Feature.is_set_topology_set = function(self)
  return (self.value & self.SET_TOPOLOGY) ~= 0
end

Feature.set_set_topology = function(self)
  if self.value ~= nil then
    self.value = self.value | self.SET_TOPOLOGY
  else
    self.value = self.SET_TOPOLOGY
  end
end

Feature.unset_set_topology = function(self)
  self.value = self.value & (~self.SET_TOPOLOGY & self.BASE_MASK)
end
Feature.is_dynamic_power_flow_set = function(self)
  return (self.value & self.DYNAMIC_POWER_FLOW) ~= 0
end

Feature.set_dynamic_power_flow = function(self)
  if self.value ~= nil then
    self.value = self.value | self.DYNAMIC_POWER_FLOW
  else
    self.value = self.DYNAMIC_POWER_FLOW
  end
end

Feature.unset_dynamic_power_flow = function(self)
  self.value = self.value & (~self.DYNAMIC_POWER_FLOW & self.BASE_MASK)
end

function Feature.bits_are_valid(feature)
  local max =
    Feature.NODE_TOPOLOGY |
    Feature.TREE_TOPOLOGY |
    Feature.SET_TOPOLOGY |
    Feature.DYNAMIC_POWER_FLOW
  if (feature <= max) and (feature >= 1) then
    return true
  else
    return false
  end
end

Feature.mask_methods = {
  is_node_topology_set = Feature.is_node_topology_set,
  set_node_topology = Feature.set_node_topology,
  unset_node_topology = Feature.unset_node_topology,
  is_tree_topology_set = Feature.is_tree_topology_set,
  set_tree_topology = Feature.set_tree_topology,
  unset_tree_topology = Feature.unset_tree_topology,
  is_set_topology_set = Feature.is_set_topology_set,
  set_set_topology = Feature.set_set_topology,
  unset_set_topology = Feature.unset_set_topology,
  is_dynamic_power_flow_set = Feature.is_dynamic_power_flow_set,
  set_dynamic_power_flow = Feature.set_dynamic_power_flow,
  unset_dynamic_power_flow = Feature.unset_dynamic_power_flow,
}

Feature.augment_type = function(cls, val)
  setmetatable(val, new_mt)
end

setmetatable(Feature, new_mt)

return Feature

