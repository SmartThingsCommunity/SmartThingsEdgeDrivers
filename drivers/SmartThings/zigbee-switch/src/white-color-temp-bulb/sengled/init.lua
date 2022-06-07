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
local switch_defaults = require "st.zigbee.defaults.switch_defaults"

local ColorControl = clusters.ColorControl

local SENGLED_BULB_FINGERPRINTS = {
  ["sengled"] = {
    ["Z01-A19NAE26"] = true
  }
}

local function can_handle_sengled_bulb(opts, driver, device)
  return (SENGLED_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()] or false
end

local function set_color_temperature_handler(driver, device, cmd)
  switch_defaults.on(driver, device, cmd)
  local temp_in_mired = math.floor(1000000 / cmd.args.temperature)
  device:send(ColorControl.commands.MoveToColorTemperature(device, temp_in_mired, 0x0100))

  device.thread:call_with_delay(1, function(d)
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
  end)
end

local sengled_bulb = {
  NAME = "Sengled Bulb",
  capability_handlers = {
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature_handler
    }
  },
  can_handle = can_handle_sengled_bulb
}

return sengled_bulb
