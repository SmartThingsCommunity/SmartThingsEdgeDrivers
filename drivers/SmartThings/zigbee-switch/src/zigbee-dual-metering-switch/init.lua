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
local st_device = require "st.device"
local clusters = require "st.zigbee.zcl.clusters"
local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local utils = require "st.utils"

local CHILD_ENDPOINT = 2

local ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT = {
  {mfr = "Aurora", model = "DoubleSocket50AU"}
}

local function can_handle_zigbee_dual_metering_switch(opts, driver, device, ...)
  for _, fingerprint in ipairs(ZIGBEE_DUAL_METERING_SWITCH_FINGERPRINT) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      local subdriver = require("zigbee-dual-metering-switch")
      return true, subdriver
    end
  end
  return false
end

local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
end

local function find_child(parent, ep_id)
  return parent:get_child_by_parent_assigned_key(string.format("%02X", ep_id))
end

local function device_added(driver, device, event)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE and
    not (device.child_ids and utils.table_size(device.child_ids) ~= 0) and
    find_child(device, CHILD_ENDPOINT) == nil then

    local name = "AURORA Outlet 2"
    local metadata = {
      type = "EDGE_CHILD",
      label = name,
      profile = "switch-power-smartplug",
      parent_device_id = device.id,
      parent_assigned_child_key = string.format("%02X", CHILD_ENDPOINT),
      vendor_provided_label = name,
    }
    driver:try_create_device(metadata)
  end
  do_refresh(driver, device)
end

local function device_init(driver, device)
  if device.network_type == st_device.NETWORK_TYPE_ZIGBEE then
    device:set_find_child(find_child)
  end
end

local zigbee_dual_metering_switch = {
  NAME = "zigbee dual metering switch",
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added
  },
  can_handle = can_handle_zigbee_dual_metering_switch
}

return zigbee_dual_metering_switch
