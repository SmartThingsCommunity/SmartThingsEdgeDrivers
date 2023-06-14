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
local device_management = require "st.zigbee.device_management"
local zcl_commands = require "st.zigbee.zcl.global_commands"

local function present_value_attr_handler(driver, device, value, zb_rx)
  local event
  local additional_fields = {
    state_change = true
  }
  if value.value == 0x0001 then
    event = capabilities.button.button.pushed(additional_fields)
    device:emit_event(event)
  end
  if value.value == 0x0002 then
    event = capabilities.button.button.double(additional_fields)
    device:emit_event(event)
  end
  if value.value == 0x0000 then
    event = capabilities.button.button.held(additional_fields)
    device:emit_event(event)
  end
end

local function device_added(driver, device)
  device:emit_event(capabilities.button.supportedButtonValues({ "pushed", "double", "held" }))
  device:emit_event(capabilities.button.numberOfButtons({value = 1}))
end

local thirdreality_device_handler = {
  NAME = "ThirdReality Smart Button",
  lifecycle_handlers = {
    added = device_added
  },
  zigbee_handlers = {
    attr = {
      [0x0012] = {
        [0x0055] = present_value_attr_handler
      }
    }
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Third Reality, Inc" and device:get_model() == "3RSB22BZ"
  end
}

return thirdreality_device_handler
