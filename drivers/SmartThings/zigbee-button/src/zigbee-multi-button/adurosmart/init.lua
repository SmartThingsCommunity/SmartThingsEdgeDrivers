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
local device_management = require "st.zigbee.device_management"
local log = require "log"
local button_utils = require "button_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level

local ADURO_NUM_ENDPOINT = 0x04
local ADURO_MANUFACTURER_SPECIFIC_CLUSTER = 0xFCCC
local ADURO_MANUFACTURER_SPECIFIC_CMD = 0x00

local ADURO_BUTTON_FINGERPRINTS = {
  { mfr = "AduroSmart Eria", model = "ADUROLIGHT_CSC" },
  { mfr = "ADUROLIGHT", model = "ADUROLIGHT_CSC" },
  { mfr = "AduroSmart Eria", model = "Adurolight_NCC" },
  { mfr = "ADUROLIGHT", model = "Adurolight_NCC" }
}

local is_aduro_button = function(opts, driver, device)
  for _, fingerprint in ipairs(ADURO_BUTTON_FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
      return true
    end
  end
  return false
end

local do_configuration = function(self, device)
  for endpoint = 1,ADURO_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui, endpoint))
  end
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui, 0x02))
  device:send(device_management.build_bind_request(device, Level.ID, self.environment_info.hub_zigbee_eui, 0x03))
  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))
end

local aduro_mfg_cluster_handler = function(driver, device, zb_rx)
  local additional_fields = {
    state_change = true
  }
  local bytes = zb_rx.body.zcl_body.body_bytes
  local button_num = bytes:byte(2) + 1
  local button_name = "button" .. button_num
  local event = capabilities.button.button.pushed(additional_fields)
  local comp = device.profile.components[button_name]
  if comp ~= nil then
    device:emit_component_event(comp, event)
    device:emit_event(event)
  else
    log.warn("Attempted to emit button event for unknown button: " .. button_name)
  end
end

local aduro_device_handler = {
  NAME = "AduroLight Device handler",
  lifecycle_handlers = {
    doConfigure = do_configuration
  },
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = button_utils.build_button_handler("button4", capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = button_utils.build_button_handler("button1", capabilities.button.button.pushed)
      },
      [ADURO_MANUFACTURER_SPECIFIC_CLUSTER] = {
        [ADURO_MANUFACTURER_SPECIFIC_CMD] = aduro_mfg_cluster_handler
      }
    }
  },
  can_handle = is_aduro_button
}

return aduro_device_handler
