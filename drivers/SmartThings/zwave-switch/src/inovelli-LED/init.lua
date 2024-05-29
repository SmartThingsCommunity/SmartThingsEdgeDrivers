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
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })

local LED_COLOR_CONTROL_PARAMETER_NUMBER = 13
local LED_GENERIC_SATURATION = 100
local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31SN_PRODUCT_TYPE = 0x0001
local INOVELLI_LZW31_PRODUCT_TYPE = 0x0003
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001
local LED_BAR_COMPONENT_NAME = "LEDColorConfiguration"

local function huePercentToZwaveValue(value)
  if value <= 2 then
    return 0
  elseif value >= 98 then
    return 255
  else
    return utils.round(value / 100 * 255)
  end
end

local function zwaveValueToHuePercent(value)
  if value <= 2 then
    return 0
  elseif value >= 254 then
    return 100
  else
    return utils.round(value / 255 * 100)
  end
end

local function configuration_report(driver, device, cmd)
  if cmd.args.parameter_number == LED_COLOR_CONTROL_PARAMETER_NUMBER then
    local hue = zwaveValueToHuePercent(cmd.args.configuration_value)

    local ledBarComponent = device.profile.components[LED_BAR_COMPONENT_NAME]
    if ledBarComponent ~= nil then
      device:emit_component_event(ledBarComponent, capabilities.colorControl.hue(hue))
      device:emit_component_event(ledBarComponent, capabilities.colorControl.saturation(LED_GENERIC_SATURATION))
    end
  end
end

local function set_color(driver, device, cmd)
  local value = huePercentToZwaveValue(cmd.args.color.hue)
  local config = Configuration:Set({
    parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER,
    configuration_value=value,
    size=2
  })
  device:send(config)

  local query_configuration = function()
    device:send(Configuration:Get({ parameter_number=LED_COLOR_CONTROL_PARAMETER_NUMBER }))
  end

  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_configuration)
end

local function can_handle_inovelli_led(opts, driver, device, ...)
  if device:id_match(
    INOVELLI_MANUFACTURER_ID,
    {INOVELLI_LZW31SN_PRODUCT_TYPE, INOVELLI_LZW31_PRODUCT_TYPE},
    INOVELLI_DIMMER_PRODUCT_ID
  ) then
    local subdriver = require("inovelli-LED")
    return true, subdriver
  end
  return false
end

local inovelli_led = {
  NAME = "Inovelli LED",
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    }
  },
  capability_handlers = {
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    }
  },
  can_handle = can_handle_inovelli_led,
  sub_drivers = {
    require("inovelli-LED/inovelli-lzw31sn")
  }
}

return inovelli_led
