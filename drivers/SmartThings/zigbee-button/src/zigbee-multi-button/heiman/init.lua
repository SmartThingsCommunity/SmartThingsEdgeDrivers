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

local Basic = clusters.Basic
local OnOff = clusters.OnOff
local PowerConfiguration = clusters.PowerConfiguration
local Scenes = clusters.Scenes

local HEIMAN_GROUP_CONFIGURE = "is_group_configured"
local HEIMAN_NUM_ENDPOINT = 0x04

local HEIMAN_BUTTON_FINGERPRINTS = {
  { mfr = "HEIMAN", model = "SceneSwitch-EM-3.0" }
}

local is_heiman_button = function(opts, driver, device)
  for _, fingerprint in ipairs(HEIMAN_BUTTON_FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true
      end
  end
  return false
end

local do_configure = function(self, device)
  device:send(device_management.build_bind_request(device, PowerConfiguration.ID, self.environment_info.hub_zigbee_eui))
  device:send(PowerConfiguration.attributes.BatteryVoltage:configure_reporting(device, 30, 21600, 1))
  for endpoint = 1,HEIMAN_NUM_ENDPOINT do
    device:send(device_management.build_bind_request(device, OnOff.ID, self.environment_info.hub_zigbee_eui, endpoint))
  end
  device:send(OnOff.attributes.OnOff:configure_reporting(device, 0, 600, 1))
  device:send(Basic.attributes.DeviceEnabled:write(device, true))
  if not self.datastore[HEIMAN_GROUP_CONFIGURE] then
    -- Configure adding hub to group once
    self:add_hub_to_zigbee_group(0x000F)
    self:add_hub_to_zigbee_group(0x0010)
    self:add_hub_to_zigbee_group(0x0011)
    self:add_hub_to_zigbee_group(0x0012)
    self.datastore[HEIMAN_GROUP_CONFIGURE] = true
  end
end

local function scenes_cluster_handler(driver, device, zb_rx)
  local additional_fields = {
    state_change = true
  }
  local bytes = zb_rx.body.zcl_body.body_bytes
  local button_num = bytes:byte(3)
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

local heiman_device_handler = {
  NAME = "Heiman Device handler",
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  zigbee_handlers = {
    cluster = {
      [Scenes.ID] = {
        [0x07] = scenes_cluster_handler
      }
    }
  },
  can_handle = is_heiman_button
}

return heiman_device_handler
