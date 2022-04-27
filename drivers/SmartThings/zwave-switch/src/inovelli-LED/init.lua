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
--- @type st.zwave.CommandClass.CentralScene
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=3})

local LED_COLOR_CONTROL_PARAMETER_NUMBER = 13
local LED_GENERIC_SATURATION = 100
local INOVELLI_MANUFACTURER_ID = 0x031E
local INOVELLI_LZW31SN_PRODUCT_TYPE = 0x0001
local INOVELLI_LZW31_PRODUCT_TYPE = 0x0003
local INOVELLI_DIMMER_PRODUCT_ID = 0x0001

local function button_to_component(buttonId)
  if buttonId > 0 then
    return string.format("button%d", buttonId)
  end
end

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
    device:emit_event(capabilities.colorControl.hue(hue))
    device:emit_event(capabilities.colorControl.saturation(LED_GENERIC_SATURATION))
  end
end

local map_key_attribute_to_capability = {
  [CentralScene.key_attributes.KEY_PRESSED_1_TIME] = capabilities.button.button.pushed,
  [CentralScene.key_attributes.KEY_RELEASED] = capabilities.button.button.held,
  [CentralScene.key_attributes.KEY_HELD_DOWN] = capabilities.button.button.down_hold,
  [CentralScene.key_attributes.KEY_PRESSED_2_TIMES] = capabilities.button.button.double,
  [CentralScene.key_attributes.KEY_PRESSED_3_TIMES] = capabilities.button.button.pushed_3x,
  [CentralScene.key_attributes.KEY_PRESSED_4_TIMES] = capabilities.button.button.pushed_4x,
  [CentralScene.key_attributes.KEY_PRESSED_5_TIMES] = capabilities.button.button.pushed_5x,
}

local function central_scene_notification_handler(self, device, cmd)
  if ( cmd.args.scene_number ~= nil and cmd.args.scene_number ~= 0 ) then
    local button_number = cmd.args.scene_number
    local capability_attribute = map_key_attribute_to_capability[cmd.args.key_attributes]
    local additional_fields = {
      state_change = true
    }

    local event
    if capability_attribute ~= nil then
      event = capability_attribute(additional_fields)
    end

    if event ~= nil then
      -- device reports scene notifications from endpoint 0 (main) but central scene events have to be emitted for button components: 1,2,3
      local comp = device.profile.components[button_to_component(button_number)]
      if comp ~= nil then
        device:emit_component_event(comp, event)
      end
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

  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY + constants.DEFAULT_DIMMING_DURATION, query_configuration)
end

local function can_handle_inovelli_led(opts, driver, device, ...)
  if device:id_match(
    INOVELLI_MANUFACTURER_ID,
    {INOVELLI_LZW31SN_PRODUCT_TYPE, INOVELLI_LZW31_PRODUCT_TYPE},
    INOVELLI_DIMMER_PRODUCT_ID
  ) then
    return true
  end
  return false
end

local inovelli_led = {
  NAME = "Inovelli LED",
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    },
    [cc.CENTRAL_SCENE] = {
      [CentralScene.NOTIFICATION] = central_scene_notification_handler
    }
  },
  capability_handlers = {
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    }
  },
  can_handle = can_handle_inovelli_led
}

return inovelli_led
