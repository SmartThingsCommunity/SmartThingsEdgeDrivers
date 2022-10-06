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
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local device_lib = require "st.device"

local ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT = {
  {mfr = "Aurora", model = "DoubleSocket50AU"}
}

local function can_handle_zigbee_dual_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function added(driver, device, event)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    for i = 1,2 do
      local name = string.format("%s outlet %d", device.label, i)
      local metadata = {
        type = "EDGE_CHILD",
        label = name,
        profile = "switch-power-2",
        parent_device_id = device.id,
        parent_assigned_child_key = string.format("%02X", i),
        vendor_provided_label = name,
      }
      driver:try_create_device(metadata)
    end
  end
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function init(driver, device, event)
  if device.network_type == device_lib.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local zigbee_dual_metering_switch = {
  NAME = "zigbee dual metering switch",
  supported_capabilities = {
    capabilities.switch,
    capabilities.powerMeter
  },
  lifecycle_handlers = {
    added = added,
    init =  init
  },
  can_handle = can_handle_zigbee_dual_metering_switch
}

return zigbee_dual_metering_switch