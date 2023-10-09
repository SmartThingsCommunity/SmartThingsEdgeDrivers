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
local button_utils = require "button_utils"

local Level = clusters.Level
local OnOff = clusters.OnOff

local function can_handle_on_off(opts, driver, device, ...)
  device.log.info_with({ hub_logs = true }, ("Calling can_handle for IKEA on off switch"))
  if device:get_model() == "TRADFRI on/off switch" then
    local subdriver = require("zigbee-multi-button.ikea.TRADFRI_on_off_switch")
    return true, subdriver
  end
  return false
end

local on_off_switch = {
  NAME = "On/Off Switch",
  zigbee_handlers = {
    cluster = {
      [OnOff.ID] = {
        [OnOff.server.commands.Off.ID] = button_utils.build_button_handler("button1", capabilities.button.button.pushed),
        [OnOff.server.commands.On.ID] = button_utils.build_button_handler("button2", capabilities.button.button.pushed)
      },
      [Level.ID] = {
        [Level.server.commands.Move.ID] = button_utils.build_button_handler("button1", capabilities.button.button.held),
        [Level.server.commands.MoveWithOnOff.ID] = button_utils.build_button_handler("button2", capabilities.button.button.held)
      },
    }
  },
  can_handle = can_handle_on_off
}

return on_off_switch
