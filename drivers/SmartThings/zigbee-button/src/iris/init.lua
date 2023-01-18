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

local zcl_clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local OnOff = zcl_clusters.OnOff
local PowerConfiguration = zcl_clusters.PowerConfiguration
local IASZone = zcl_clusters.IASZone
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local button_utils = require "button_utils"

local IRIS_BUTTON_FINGERPRINTS = {
  { mfr = "CentraLite", model = "3455-L" },
  { mfr = "CentraLite", model = "3460-L" }
}

local function can_handle_iris_button(opts, driver, device, ...)
  for _, fingerprint in ipairs(IRIS_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function button_pressed_handler(self, device, value, zb_rx)
  button_utils.init_button_press(device)
end

local function button_released_handler(self, device, value, zb_rx)
  button_utils.send_pushed_or_held_button_event_if_applicable(device)
end

local function generate_event_from_zone_status(device, zone_status)
  if zone_status:is_alarm2_set() then
    button_utils.init_button_press(device)
  else
    button_utils.send_pushed_or_held_button_event_if_applicable(device)
  end
end

local function ias_zone_status_attr_handler(self, device, zone_status, zb_rx)
  generate_event_from_zone_status(device, zone_status)
end

local function ias_zone_status_change_handler(self, device, zb_rx)
  generate_event_from_zone_status(device, zb_rx.body.zcl_body.zone_status)
end

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
  -- device:emit_event(capabilities.button.button.pushed({state_change = false}))
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
end

local function do_configure(self, device)
  device:configure()
  device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui))
end

local iris_button = {
  NAME = "Iris Button",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    added = added_handler,
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.On.ID] = button_pressed_handler,
        [OnOff.server.commands.Off.ID] = button_released_handler
      },
      [IASZone.ID] = {
        [IASZone.client.commands.ZoneStatusChangeNotification.ID] = ias_zone_status_change_handler
      }
    },
    attr = {
      [IASZone.ID] = {
        [IASZone.attributes.ZoneStatus.ID] = ias_zone_status_attr_handler
      }
    }
  },
  can_handle = can_handle_iris_button
}

return iris_button
