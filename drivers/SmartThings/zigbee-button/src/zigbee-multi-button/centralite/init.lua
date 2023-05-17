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

local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local button_utils = require "button_utils"

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration

local CENTRALITE_NUM_ENDPOINT = 0x04

local EP_BUTTON_COMPONENT_MAP = {
  [0x01] = 4,
  [0x02] = 3,
  [0x03] = 1,
  [0x04] = 2
}

local CENTRALITE_BUTTON_FINGERPRINTS = {
  { mfr = "CentraLite", model = "3450-L" },
  { mfr = "CentraLite", model = "3450-L2" }
}

local is_centralite_button = function(opts, driver, device)
  for _, fingerprint in ipairs(CENTRALITE_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local do_configuration = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  for endpoint = 1,CENTRALITE_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui, endpoint))
  end
  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))
end

local function attr_on_handler(driver, device, zb_rx)
  button_utils.init_button_press(device, EP_BUTTON_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value])
end

local function attr_off_handler(driver, device, zb_rx)
  button_utils.send_pushed_or_held_button_event_if_applicable(device, EP_BUTTON_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value])
end

local centralite_device_handler = {
  NAME = "Centralite 3450-L and L2 handler",
  lifecycle_handlers = {
    doConfigure = do_configuration,
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0)
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = attr_off_handler,
        [OnOff.server.commands.On.ID] = attr_on_handler
      }
    }
  },
  can_handle = is_centralite_button
}

return centralite_device_handler
