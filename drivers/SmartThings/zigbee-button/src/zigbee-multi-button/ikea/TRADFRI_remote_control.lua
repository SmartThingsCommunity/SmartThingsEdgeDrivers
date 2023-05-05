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
local log = require "log"
local button_utils = require "button_utils"

local Level = clusters.Level
local OnOff = clusters.OnOff
local Scenes = clusters.Scenes
local PowerConfiguration = clusters.PowerConfiguration

local function build_button_payload_handler(pressed_type)
  return function(driver, device, zb_rx)
    local additional_fields = {
      state_change = true
    }
    local bytes = zb_rx.body.zcl_body.body_bytes
    local payload_id = bytes:byte(1)
    local button_name =
      payload_id == 0x00 and "button2" or "button4"
    local event = pressed_type(additional_fields)
    local comp = device.profile.components[button_name]
    if comp ~= nil then
      device:emit_component_event(comp, event)
      if button_name ~= "main" then
        device:emit_event(event)
      end
    else
      log.warn("Attempted to emit button event for unknown button: " .. button_name)
    end
  end
end

local function added_handler(self, device)
  for comp_name, comp in pairs(device.profile.components) do
    if comp_name == "button5" then
      device:emit_component_event(comp, capabilities.button.supportedButtonValues({"pushed"}, {visibility = { displayed = false }}))
    else
      device:emit_component_event(comp, capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = { displayed = false }}))
    end
    if comp_name == "main" then
      device:emit_component_event(comp, capabilities.button.numberOfButtons({value = 5}, {visibility = { displayed = false }}))
    else
      device:emit_component_event(comp, capabilities.button.numberOfButtons({value = 1}, {visibility = { displayed = false }}))
    end
  end
  device:send(PowerConfiguration.attributes.BatteryPercentageRemaining:read(device))
  -- device:emit_event(capabilities.button.button.pushed({state_change = false}))
end

local remote_control = {
  NAME = "Remote Control",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Toggle.ID] = button_utils.build_button_handler("button5", capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.Move.ID] = button_utils.build_button_handler("button3", capabilities.button.button.held),
        [Level.server.commands.Step.ID] = button_utils.build_button_handler("button3", capabilities.button.button.pushed),
        [Level.server.commands.MoveWithOnOff.ID] = button_utils.build_button_handler("button1", capabilities.button.button.held),
        [Level.server.commands.StepWithOnOff.ID] = button_utils.build_button_handler("button1", capabilities.button.button.pushed)
      },
      -- Manufacturer command id used in ikea
      [Scenes.ID] = {
        [0x07] = build_button_payload_handler(capabilities.button.button.pushed),
        [0x08] = build_button_payload_handler(capabilities.button.button.held)
      }
    }
  },
  lifecycle_handlers = {
    added = added_handler
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "TRADFRI remote control"
  end
}


return remote_control
