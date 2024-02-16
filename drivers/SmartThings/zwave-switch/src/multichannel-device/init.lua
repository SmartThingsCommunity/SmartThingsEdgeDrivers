-- Copyright 2022 SmartThings
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
local cc = require "st.zwave.CommandClass"
local capabilities = require "st.capabilities"
local st_device = require "st.device"
local MultiChannel = (require "st.zwave.CommandClass.MultiChannel")({ version = 3 })
local utils = require "st.utils"

local map_device_class_to_profile = {
  [0x10] = "metering-switch",
  [0x31] = "metering-switch",
  [0x11] = "metering-dimmer",
  [0x08] = "generic-multi-sensor",
  [0x21] = "generic-multi-sensor",
  [0x20] = "generic-sensor",
  [0xA1] = "generic-sensor"
}

local function can_handle_multichannel_device(opts, driver, device, ...)
  if device:supports_capability(capabilities.zwMultichannel) then
    local subdriver = require("multichannel-device")
    return true, subdriver
  end
  return false
end

local function find_child(device, src_channel)
  if src_channel == 0 then
    return device
  else
    return device:get_child_by_parent_assigned_key(string.format("%02X", src_channel))
  end
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZWAVE then
    device:set_find_child(find_child)
  end
end

local function prepare_metadata(device, endpoint, profile)
  local name = string.format("%s %d", device.label, endpoint)
  return {
    type = "EDGE_CHILD",
    label = name,
    profile = profile,
    parent_device_id = device.id,
    parent_assigned_child_key = string.format("%02X", endpoint),
    vendor_provided_label = name
  }
end

local function device_added(driver, device)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD then
    for index, endpoint in pairs(device.zwave_endpoints) do
      device:send(MultiChannel:CapabilityGet({ end_point = index }))
    end
  end
  device:refresh()
end

local function capability_get_report_handler(driver, device, cmd)
  if device.network_type ~= st_device.NETWORK_TYPE_CHILD and
    not (device.child_ids and utils.table_size(device.child_ids) ~= 0) then
    local profile = map_device_class_to_profile[cmd.args.generic_device_class]
    if find_child(device, cmd.args.end_point) == nil and profile ~= nil then
      driver:try_create_device(prepare_metadata(device, cmd.args.end_point, profile))
    end
  end
end

local multichannel_device = {
  NAME = "Z-Wave Device Multichannel",
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  zwave_handlers = {
    [cc.MULTI_CHANNEL] = {
      [MultiChannel.CAPABILITY_REPORT] = capability_get_report_handler
    }
  },
  can_handle = can_handle_multichannel_device
}

return multichannel_device