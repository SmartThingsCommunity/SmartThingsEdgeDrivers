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

local WindowCovering = clusters.WindowCovering

local function build_button_handler(button_name, pressed_type)
  return function(driver, device, zb_rx)
    local additional_fields = {
      state_change = true
    }
    local event = pressed_type(additional_fields)
    local comp = device.profile.components[button_name]
    if comp ~= nil then
      device:emit_component_event(comp, event)
    else
      log.warn("Attempted to emit button event for unknown button: " .. button_name)
    end
  end
end

local open_close_remote = {
  NAME = "Open/Close Remote",
  zigbee_handlers = {
    cluster = {
      [WindowCovering.ID] = {
        [WindowCovering.server.commands.UpOrOpen.ID] = build_button_handler("button1", capabilities.button.button.pushed),
        [WindowCovering.server.commands.DownOrClose.ID] = build_button_handler("button2", capabilities.button.button.pushed)
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_model() == "TRADFRI open/close remote"
  end
}

return open_close_remote
