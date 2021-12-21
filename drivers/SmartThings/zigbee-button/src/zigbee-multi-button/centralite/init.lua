-- Copyright 2021 SmartThings
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
local clusters = require "st.zigbee.zcl.clusters"
local device_management = require "st.zigbee.device_management"
local log = require "log"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"

local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration

local CENTRALITE_NUM_ENDPOINT = 0x04
local HELD_THRESHOLD_TIMEOUT = 10000
local HOLD_TIME = 1000
local PRESS_TIME_EVENT = "press_time_event"

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
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui):to_endpoint(endpoint))
  end
  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))
end

local function attr_on_handler(driver, device, zb_rx)
  device:set_field(PRESS_TIME_EVENT, os.time())
end

local function attr_off_handler(driver, device, zb_rx)
  local additional_fields = {
    state_change = true
  }
  local button_num = EP_BUTTON_COMPONENT_MAP[zb_rx.address_header.src_endpoint.value]
  local press_time = device:get_field(PRESS_TIME_EVENT) or 0
  local time_diff = (os.time() - press_time) * 1000
  local button_name = "button" .. button_num
  if time_diff < HELD_THRESHOLD_TIMEOUT then
    local event = time_diff < HOLD_TIME and
      capabilities.button.button.pushed(additional_fields) or
      capabilities.button.button.held(additional_fields)
    local comp = device.profile.components[button_name]
    if comp ~= nil then
      device:emit_component_event(comp, event)
    else
      log.warn("Attempted to emit button event for unknown button: " .. button_name)
    end
  end
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
