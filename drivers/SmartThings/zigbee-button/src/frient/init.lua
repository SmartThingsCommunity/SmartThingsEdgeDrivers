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
local device_management = require "st.zigbee.device_management"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local BasicInput = zcl_clusters.BasicInput
local PowerConfiguration = zcl_clusters.PowerConfiguration

local battery_table = {
    [2.90] = 100,
    [2.80] = 80,
    [2.75] = 60,
    [2.70] = 50,
    [2.65] = 40,
    [2.60] = 30,
    [2.50] = 20,
    [2.40] = 15,
    [2.20] = 10,
    [2.00] = 1,
    [1.90] = 0,
    [0.00] = 0
}

local function present_value_attr_handler(driver, device, value, zb_rx)
  local event
  local additional_fields = {
    state_change = true
  }
  if value.value == true then
    event = capabilities.button.button.pushed(additional_fields)
    device:emit_event(event)
  end
end

local function init_handler(self, device, event, args)
  battery_defaults.enable_battery_voltage_table(device, battery_table)
end

local function added_handler(self, device)
  device:emit_event(capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }}))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}))
  -- device:emit_event(capabilities.button.button.pushed({state_change = false}))
end

local configure_handler = function(self, device)
  device:send(device_management.build_bind_request(device, BasicInput.ID, self.environment_info.hub_zigbee_eui))
  device:send(BasicInput.attributes.PresentValue:configure_reporting(device, 0, 600, 1))
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
end

local frient_button = {
  NAME = "Frient Button Handler",
  lifecycle_handlers = {
    added = added_handler,
    doConfigure = configure_handler,
    init = init_handler
  },
  zigbee_handlers = {
    attr = {
      [BasicInput.ID] = {
        [BasicInput.attributes.PresentValue.ID] = present_value_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "frient A/S" and device:get_model() == "MBTZB-110"
  end
}

return frient_button
