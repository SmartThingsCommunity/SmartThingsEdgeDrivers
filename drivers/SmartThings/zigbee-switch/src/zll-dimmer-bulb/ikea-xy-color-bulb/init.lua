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
local configurationMap = require "configurations"
local utils = require "st.utils"

local ColorControl = clusters.ColorControl

local CURRENT_X = "current_x_value" -- y value from xyY color space
local CURRENT_Y = "current_y_value" -- x value from xyY color space
local Y_TRISTIMULUS_VALUE = "y_tristimulus_value" -- Y tristimulus value which is used to convert color xyY -> RGB -> HSV

local IKEA_XY_COLOR_BULB_FINGERPRINTS = {
  ["IKEA of Sweden"] = {
    ["TRADFRI bulb E27 CWS opal 600lm"] = true,
    ["TRADFRI bulb E26 CWS opal 600lm"] = true
  }
}

local function can_handle_ikea_xy_color_bulb(opts, driver, device)
  return (IKEA_XY_COLOR_BULB_FINGERPRINTS[device:get_manufacturer()] or {})[device:get_model()] or false
end

local device_init = function(self, device)
  device:remove_configured_attribute(ColorControl.ID, ColorControl.attributes.CurrentHue.ID)
  device:remove_configured_attribute(ColorControl.ID, ColorControl.attributes.CurrentSaturation.ID)
  device:remove_monitored_attribute(ColorControl.ID, ColorControl.attributes.CurrentHue.ID)
  device:remove_monitored_attribute(ColorControl.ID, ColorControl.attributes.CurrentSaturation.ID)

  local configuration = configurationMap.get_device_configuration(device)
  if configuration ~= nil then
    for _, attribute in ipairs(configuration) do
      device:add_configured_attribute(attribute)
      device:add_monitored_attribute(attribute)
    end
  end
end

local function store_xyY_values(device, x, y, Y)
  device:set_field(Y_TRISTIMULUS_VALUE, Y)
  device:set_field(CURRENT_X, x)
  device:set_field(CURRENT_Y, y)
end

local query_device = function(device)
  return function()
    device:send(ColorControl.attributes.CurrentX:read(device))
    device:send(ColorControl.attributes.CurrentY:read(device))
  end
end

local function set_color_handler(driver, device, cmd)
  local hue = cmd.args.color.hue > 99 and 99 or cmd.args.color.hue
  local sat = cmd.args.color.saturation
  local x, y, Y = utils.safe_hsv_to_xy(hue, sat)
  store_xyY_values(device, x, y, Y)
  switch_defaults.on(driver,device,cmd)

  device:send(ColorControl.commands.MoveToColor(device, x, y, 0x0000))

  device.thread:call_with_delay(2, query_device(device))
end

local function set_hue_handler(driver, device, cmd)
  local sat = device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.saturation.NAME)
  local hue = cmd.args.hue > 99 and 99 or cmd.args.hue
  local x, y, Y = utils.safe_hsv_to_xy(hue, sat)
  store_xyY_values(device, x, y, Y)
  switch_defaults.on(driver,device,cmd)

  device:send(ColorControl.commands.MoveToColor(device, x, y, 0x0000))

  device.thread:call_with_delay(2, query_device(device))
end

local function set_saturation_handler(driver, device, cmd)
  local hue = device:get_latest_state("main", capabilities.colorControl.ID, capabilities.colorControl.hue.NAME)
  local x, y, Y = utils.safe_hsv_to_xy(hue, cmd.args.saturation)
  store_xyY_values(device, x, y, Y)
  switch_defaults.on(driver,device,cmd)

  device:send(ColorControl.commands.MoveToColor(device, x, y, 0x0000))

  device.thread:call_with_delay(2, query_device(device))
end

local function current_x_attr_handler(driver, device, value, zb_rx)
  local Y_tristimulus = device:get_field(Y_TRISTIMULUS_VALUE)
  local y = device:get_field(CURRENT_Y)
  local x = value.value

  if y then
    local hue, saturation = utils.safe_xy_to_hsv(x, y, Y_tristimulus)

    device:emit_event(capabilities.colorControl.hue(hue))
    device:emit_event(capabilities.colorControl.saturation(saturation))
  end

  device:set_field(CURRENT_X, x)
end

local function current_y_attr_handler(driver, device, value, zb_rx)
  local Y_tristimulus = device:get_field(Y_TRISTIMULUS_VALUE)
  local x = device:get_field(CURRENT_X)
  local y = value.value

  if x then
    local hue, saturation = utils.safe_xy_to_hsv(x, y, Y_tristimulus)

    device:emit_event(capabilities.colorControl.hue(hue))
    device:emit_event(capabilities.colorControl.saturation(saturation))
  end

  device:set_field(CURRENT_Y, y)
end

local ikea_xy_color_bulb = {
  NAME = "IKEA XY Color Bulb",
  lifecycle_handlers = {
    init = device_init
  },
  capability_handlers = {
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color_handler,
      [capabilities.colorControl.commands.setHue.NAME] = set_hue_handler,
      [capabilities.colorControl.commands.setSaturation.NAME] = set_saturation_handler
    }
  },
  zigbee_handlers = {
    attr = {
      [ColorControl.ID] = {
        [ColorControl.attributes.CurrentX.ID] = current_x_attr_handler,
        [ColorControl.attributes.CurrentY.ID] = current_y_attr_handler
      }
    }
  },
  can_handle = can_handle_ikea_xy_color_bulb
}

return ikea_xy_color_bulb
