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
local colorTemperature_defaults = require "st.zigbee.defaults.colorTemperature_defaults"

local ColorControl = clusters.ColorControl

local function set_color_temperature_handler(driver, device, cmd)
  colorTemperature_defaults.set_color_temperature(driver, device, cmd)

  device.thread:call_with_delay(1, function(d)
    device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
  end)
end

local white_color_temp_bulb = {
  NAME = "White Color Temp Bulb",
  capability_handlers = {
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature_handler
    }
  },
  sub_drivers = require("white-color-temp-bulb.sub_drivers"),
  can_handle = require("white-color-temp-bulb.can_handle"),
}

return white_color_temp_bulb
