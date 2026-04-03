local cluster_base = require "st.matter.cluster_base"
local ClosureDimensionServerAttributes = require "embedded_clusters.ClosureDimension.server.attributes"
local ClosureDimensionServerCommands = require "embedded_clusters.ClosureDimension.server.commands"
local ClosureDimensionTypes = require "embedded_clusters.ClosureDimension.types"

local ClosureDimension = {}

ClosureDimension.ID = 0x0105
ClosureDimension.NAME = "ClosureDimension"
ClosureDimension.server = {}
ClosureDimension.client = {}
ClosureDimension.server.attributes = ClosureDimensionServerAttributes:set_parent_cluster(ClosureDimension)
ClosureDimension.server.commands = ClosureDimensionServerCommands:set_parent_cluster(ClosureDimension)
ClosureDimension.types = ClosureDimensionTypes

function ClosureDimension:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "CurrentState",
    [0x0001] = "TargetState",
    [0x0002] = "Resolution",
    [0x0003] = "StepValue",
    [0x0004] = "Unit",
    [0x0005] = "UnitRange",
    [0x0006] = "LimitRange",
    [0x0007] = "TranslationDirection",
    [0x0008] = "RotationAxis",
    [0x0009] = "Overflow",
    [0x000A] = "ModulationType",
    [0x000B] = "LatchControlModes",
    [0xFFF9] = "AcceptedCommandList",
    [0xFFFB] = "AttributeList",
  }
  local attr_name = attr_id_map[attr_id]
  if attr_name ~= nil then
    return self.attributes[attr_name]
  end
  return nil
end

function ClosureDimension:get_server_command_by_id(command_id)
  local server_id_map = {
    [0x0000] = "SetTarget",
    [0x0001] = "Step",
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

ClosureDimension.attribute_direction_map = {
  ["CurrentState"] = "server",
  ["TargetState"] = "server",
  ["Resolution"] = "server",
  ["StepValue"] = "server",
  ["Unit"] = "server",
  ["UnitRange"] = "server",
  ["LimitRange"] = "server",
  ["TranslationDirection"] = "server",
  ["RotationAxis"] = "server",
  ["Overflow"] = "server",
  ["ModulationType"] = "server",
  ["LatchControlModes"] = "server",
  ["AcceptedCommandList"] = "server",
  ["AttributeList"] = "server",
}

ClosureDimension.command_direction_map = {
  ["SetTarget"] = "server",
  ["Step"] = "server",
}

ClosureDimension.FeatureMap = ClosureDimension.types.Feature

function ClosureDimension.are_features_supported(feature, feature_map)
  if (ClosureDimension.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = ClosureDimension.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, ClosureDimension.NAME))
  end
  return ClosureDimension[direction].attributes[key]
end
ClosureDimension.attributes = {}
setmetatable(ClosureDimension.attributes, attribute_helper_mt)

local command_helper_mt = {}
command_helper_mt.__index = function(self, key)
  local direction = ClosureDimension.command_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown command %s on cluster %s", key, ClosureDimension.NAME))
  end
  return ClosureDimension[direction].commands[key]
end
ClosureDimension.commands = {}
setmetatable(ClosureDimension.commands, command_helper_mt)

setmetatable(ClosureDimension, {__index = cluster_base})

return ClosureDimension
