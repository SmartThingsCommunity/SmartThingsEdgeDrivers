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
local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local PowerConfiguration = clusters.PowerConfiguration
local OnOff = clusters.OnOff
local device_management = require "st.zigbee.device_management"
local Groups = clusters.Groups

local SHINASYSTEM_BUTTON_FINGERPRINTS = {
  { mfr = "ShinaSystem", model = "MSM-300Z", endpoint_num = 0x04 },
  { mfr = "ShinaSystem", model = "BSM-300Z", endpoint_num = 0x01 },
  { mfr = "ShinaSystem", model = "SBM300ZB1", endpoint_num = 0x01 },
  { mfr = "ShinaSystem", model = "SBM300ZB2", endpoint_num = 0x02 },
  { mfr = "ShinaSystem", model = "SBM300ZB3", endpoint_num = 0x03 },
}

local is_shinasystem_button = function(opts, driver, device)
  for _, fingerprint in ipairs(SHINASYSTEM_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local function get_ep_num_shinasystem_button(device)
  for _, fingerprint in ipairs(SHINASYSTEM_BUTTON_FINGERPRINTS) do
    if device:get_model() == fingerprint.model then
      return fingerprint.endpoint_num
    end
  end
end

local function build_button_handler(pressed_type)
  return function(driver, device, zb_rx)
    local additional_fields = {
      state_change = true
    }
    local event = pressed_type(additional_fields)
    local button_comp = string.format("button%d", zb_rx.address_header.src_endpoint.value)
    if device.profile.components[button_comp] == nil then
        button_comp = "main"
    end
    device:emit_component_event(device.profile.components[button_comp], event)
    if button_comp ~= "main" then
      device:emit_event(event)
    end
  end
end

local do_configure = function(self, device)
  device:configure()
  device:send(PowerConfiguration.attributes.BatteryVoltage:read(device))
  for endpoint = 1, get_ep_num_shinasystem_button(device) do
      device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui, endpoint))
  end
  self:add_hub_to_zigbee_group(0x0000)
  device:send(Groups.commands.AddGroup(device, 0x0000))
end

local shinasystem_device_handler = {
  NAME = "ShinaSystem Device Handler",
  lifecycle_handlers = {
    init = battery_defaults.build_linear_voltage_init(2.1, 3.0),
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = build_button_handler(capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = build_button_handler(capabilities.button.button.double),
        [OnOff.server.commands.Toggle.ID] = build_button_handler(capabilities.button.button.held)
      }
    }
  },
  can_handle = is_shinasystem_button
}

return shinasystem_device_handler
