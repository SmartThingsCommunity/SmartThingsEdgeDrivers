-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local device_lib = require "st.device"
local zcl_clusters = require "st.zigbee.zcl.clusters"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local data_types = require "st.zigbee.data_types"
local zb_const = require "st.zigbee.constants"
local generic_body = require "st.zigbee.generic_body"
local read_attribute = require "st.zigbee.zcl.global_commands.read_attribute"

local TUYA_PRIVATE_CLUSTER = 0xEF00
local TUYA_PRIVATE_CMD_RESPONSE = 0x01
local TUYA_PRIVATE_CMD_REPORT = 0x02
local DP_TYPE_BOOL = "\x01"
local DP_TYPE_VALUE = "\x02"
local DP_TYPE_ENUM = "\x04"

local tuya_utils = {}

local function read_attribute_function(device, cluster_id, attr_id)
  local read_body = read_attribute.ReadAttribute( attr_id )
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)
  })
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(zcl_clusters.Basic.ID),
    zb_const.HA_PROFILE_ID,
    zcl_clusters.Basic.ID
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = read_body
  })
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
end

tuya_utils.send_magic_spell = function(device)
  local magic_spell = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xfffe}
  device:send(read_attribute_function(device, zcl_clusters.Basic.ID, magic_spell))
end

tuya_utils.send_tuya_command = function(device, dp, dp_type, dp_data, packet_id)
  local parent = (device.network_type == device_lib.NETWORK_TYPE_CHILD) and device:get_parent_device() or device
  local zclh = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(0x00)})
  zclh.frame_ctrl:set_cluster_specific()
  zclh.frame_ctrl:set_disable_default_response()
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    parent:get_short_address(),
    parent:get_endpoint(TUYA_PRIVATE_CLUSTER),
    zb_const.HA_PROFILE_ID,
    TUYA_PRIVATE_CLUSTER
  )
  local dp_data_len = string.len(dp_data)
  local payload_body = generic_body.GenericBody(string.pack(">I2", packet_id) .. dp .. dp_type .. string.pack(">I2", dp_data_len) .. dp_data)
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = payload_body
  })
  local send_message = messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
  parent:send(send_message)
end

tuya_utils.build_test_attr_report = function(device, dp, dp_type, dp_data, cmd_id)
  local zclh = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(cmd_id)})
  zclh.frame_ctrl:set_cluster_specific()
  zclh.frame_ctrl:set_disable_default_response()
  local addrh = messages.AddressHeader(
    device:get_short_address(),
    device:get_endpoint(TUYA_PRIVATE_CLUSTER),
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    zb_const.HA_PROFILE_ID,
    TUYA_PRIVATE_CLUSTER
  )
  local dp_data_len = string.len(dp_data)
  local payload_body = generic_body.GenericBody(string.pack(">I2", 1) .. dp .. dp_type .. string.pack(">I2", dp_data_len) .. dp_data)
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = payload_body
  })
  return messages.ZigbeeMessageRx({
    address_header = addrh,
    body = message_body
  })
end

tuya_utils.build_send_tuya_command = function(device, dp, dp_type, dp_data, packet_id)
  local parent = (device.network_type == device_lib.NETWORK_TYPE_CHILD) and device:get_parent_device() or device
  local zclh = zcl_messages.ZclHeader({cmd = data_types.ZCLCommandId(0x00)})
  zclh.frame_ctrl:set_cluster_specific()
  zclh.frame_ctrl:set_disable_default_response()
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    parent:get_short_address(),
    parent:get_endpoint(TUYA_PRIVATE_CLUSTER),
    zb_const.HA_PROFILE_ID,
    TUYA_PRIVATE_CLUSTER
  )
  local dp_data_len = string.len(dp_data)
  local payload_body = generic_body.GenericBody(string.pack(">I2", packet_id) .. dp .. dp_type .. string.pack(">I2", dp_data_len) .. dp_data)
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = payload_body
  })
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
end

tuya_utils.build_tuya_magic_spell_message = function(device)
  local magic_spell = {0x0004, 0x0000, 0x0001, 0x0005, 0x0007, 0xfffe}
  local read_body = read_attribute.ReadAttribute( magic_spell )
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(read_attribute.ReadAttribute.ID)
  })
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    device:get_short_address(),
    device:get_endpoint(zcl_clusters.Basic.ID),
    zb_const.HA_PROFILE_ID,
    zcl_clusters.Basic.ID
  )
  local message_body = zcl_messages.ZclMessageBody({
    zcl_header = zclh,
    zcl_body = read_body
  })
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = message_body
  })
end

tuya_utils.emit_event_if_latest_state_missing = function(device, component, capability, attribute_name, value)
  if device:get_latest_state(component, capability.ID, attribute_name) == nil then
    device:emit_event(value)
  end
end

tuya_utils.TUYA_PRIVATE_CLUSTER = TUYA_PRIVATE_CLUSTER
tuya_utils.DP_TYPE_BOOL = DP_TYPE_BOOL
tuya_utils.DP_TYPE_ENUM = DP_TYPE_ENUM
tuya_utils.DP_TYPE_VALUE = DP_TYPE_VALUE
tuya_utils.TUYA_PRIVATE_CMD_RESPONSE = TUYA_PRIVATE_CMD_RESPONSE
tuya_utils.TUYA_PRIVATE_CMD_REPORT = TUYA_PRIVATE_CMD_REPORT

return tuya_utils