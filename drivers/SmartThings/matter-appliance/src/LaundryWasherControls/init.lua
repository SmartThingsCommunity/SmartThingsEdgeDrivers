local LaundryWasherControlsServerAttributes = require "LaundryWasherControls.server.attributes"
local LaundryWasherControlsTypes = require "LaundryWasherControls.types"

local LaundryWasherControls = {}

LaundryWasherControls.ID = 0x0053
LaundryWasherControls.NAME = "LaundryWasherControls"
LaundryWasherControls.server = {}
LaundryWasherControls.client = {}
LaundryWasherControls.server.attributes = LaundryWasherControlsServerAttributes:set_parent_cluster(LaundryWasherControls)
LaundryWasherControls.types = LaundryWasherControlsTypes

function LaundryWasherControls:get_attribute_by_id(attr_id)
  local attr_id_map = {
    [0x0000] = "SpinSpeeds",
    [0x0001] = "SpinSpeedCurrent",
    [0x0002] = "NumberOfRinses",
    [0x0003] = "SupportedRinses",
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

function LaundryWasherControls:get_server_command_by_id(command_id)
  local server_id_map = {
  }
  if server_id_map[command_id] ~= nil then
    return self.server.commands[server_id_map[command_id]]
  end
  return nil
end

LaundryWasherControls.attribute_direction_map = {
  ["SpinSpeeds"] = "server",
  ["SpinSpeedCurrent"] = "server",
  ["NumberOfRinses"] = "server",
  ["SupportedRinses"] = "server",
  ["AcceptedCommandList"] = "server",
  ["EventList"] = "server",
  ["AttributeList"] = "server",
}

LaundryWasherControls.command_direction_map = {
}

LaundryWasherControls.FeatureMap = LaundryWasherControls.types.Feature

function LaundryWasherControls.are_features_supported(feature, feature_map)
  if (LaundryWasherControls.FeatureMap.bits_are_valid(feature)) then
    return (feature & feature_map) == feature
  end
  return false
end

local attribute_helper_mt = {}
attribute_helper_mt.__index = function(self, key)
  local direction = LaundryWasherControls.attribute_direction_map[key]
  if direction == nil then
    error(string.format("Referenced unknown attribute %s on cluster %s", key, LaundryWasherControls.NAME))
  end
  return LaundryWasherControls[direction].attributes[key]
end
LaundryWasherControls.attributes = {}
setmetatable(LaundryWasherControls.attributes, attribute_helper_mt)

return LaundryWasherControls
