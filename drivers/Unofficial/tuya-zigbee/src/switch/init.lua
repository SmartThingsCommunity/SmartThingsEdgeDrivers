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

local capabilities = require "st.capabilities"
local device_lib = require "st.device"
local tuya_utils = require "tuya_utils"
local ep_array = {1,2,3,4,5,6}
local packet_id = 0

local FINGERPRINTS = {
  { mfr = "_TZE204_h2rctifa", model = "TS0601"}
}

local function is_tuya_switch(opts, driver, device)
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function find_child(parent, endpoint)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", endpoint))
end

local function create_child_devices(driver, device)
  for ep in ipairs(ep_array) do
    if ep ~= device.fingerprinted_endpoint_id then
      if find_child(device, ep) == nil then
        local metadata = {
          type = "EDGE_CHILD",
          parent_assigned_child_key = string.format("%02X", ep),
          label = device.label..' '..ep,
          profile = "basic-switch",
          parent_device_id = device.id
        }
        driver:try_create_device(metadata)
      end
    end
  end
end

local function tuya_cluster_handler(driver, device, zb_rx)
  local raw = zb_rx.body.zcl_body.body_bytes
  local dp = string.byte(raw:sub(3,3))
  local dp_data_len = string.unpack(">I2", raw:sub(5,6))
  local dp_data = string.unpack(">I"..dp_data_len, raw:sub(7))
  if dp == device.fingerprinted_endpoint_id or find_child(device, dp) ~= nil then
    device:emit_event_for_endpoint(dp, capabilities.switch.switch(dp_data == 0 and "off" or "on"))
  end
end

local function switch_on_handler(driver, device)
  local dp = (device.network_type == device_lib.NETWORK_TYPE_CHILD) and string.char(device:get_endpoint()) or "\x01"
  tuya_utils.send_tuya_command(device, dp, tuya_utils.DP_TYPE_BOOL, "\x01", packet_id)
  packet_id = (packet_id + 1) % 65536
end

local function switch_off_handler(driver, device)
  local dp = (device.network_type == device_lib.NETWORK_TYPE_CHILD) and string.char(device:get_endpoint()) or "\x01"
  tuya_utils.send_tuya_command(device, dp, tuya_utils.DP_TYPE_BOOL, "\x00", packet_id)
  packet_id = (packet_id + 1) % 65536
end

local function device_added(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    create_child_devices(driver, device)
  end
end

local function device_init(driver, device)
  if device.network_type == device_lib.NETWORK_TYPE_CHILD then return end
  device:set_find_child(find_child)
end

local tuya_multi_switch_driver = {
  NAME = "tuya multi switch",
  supported_capabilities = {
    capabilities.switch
  },
  zigbee_handlers = {
    cluster = {
      [tuya_utils.TUYA_PRIVATE_CLUSTER] = {
        [tuya_utils.TUYA_PRIVATE_CMD_RESPONSE] = tuya_cluster_handler,
        [tuya_utils.TUYA_PRIVATE_CMD_REPORT] = tuya_cluster_handler,
      }
    },
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = switch_on_handler,
      [capabilities.switch.commands.off.NAME] = switch_off_handler,
    },
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
  },
  can_handle = is_tuya_switch
}

return tuya_multi_switch_driver