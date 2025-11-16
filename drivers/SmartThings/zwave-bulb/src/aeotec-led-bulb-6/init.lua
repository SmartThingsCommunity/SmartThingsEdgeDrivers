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
--- @type st.zwave.CommandClass.SwitchColor
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version=3 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })

local AEOTEC_MFR_ID = 0x0371
local AEOTEC_LED_BULB_6_PRODUCT_TYPE_US = 0x0103
local AEOTEC_LED_BULB_6_PRODUCT_TYPE_EU = 0x0003
local AEOTEC_LED_BULB_6_PRODUCT_ID = 0x0002
local WARM_WHITE_CONFIG = 0x51
local COLD_WHITE_CONFIG = 0x52

local zwave_handlers = {}

--- Handle a Configuration Report command received from an Aeotec bulb.
--- If the config report contains white temperature information, publish a
--- corresponding ST color temperature color event.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.Configuration.Report
function zwave_handlers.configuration_report(driver, device, cmd)
  local pn = cmd.args.parameter_number
  if pn ~= WARM_WHITE_CONFIG and pn ~= COLD_WHITE_CONFIG then
    return
  end
  if cmd.args.configuration_value > 0 then
    device:emit_event(capabilities.colorTemperature.colorTemperature(
      cmd.args.configuration_value))
  end
end

local capability_handlers = {}

-- Issue the Aeotec-specific config to set color temperature.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd table ST color control capability command
function capability_handlers.set_color_temperature(driver, device, cmd)
  local duration = constants.DEFAULT_DIMMING_DURATION
  local temp = cmd.args.temperature
  temp = utils.round(temp)
  local ww = temp < 5000 and 255 or 0
  local cw = temp >= 5000 and 255 or 0
  local parameter_number = temp < 5000 and WARM_WHITE_CONFIG or COLD_WHITE_CONFIG
  local config = Configuration:Set({
    parameter_number=parameter_number,
    configuration_value=temp
  })
  device:send(config)
  local set = SwitchColor:Set({
    color_components = {
      { color_component_id=SwitchColor.color_component_id.RED, value=0 },
      { color_component_id=SwitchColor.color_component_id.GREEN, value=0 },
      { color_component_id=SwitchColor.color_component_id.BLUE, value=0 },
      { color_component_id=SwitchColor.color_component_id.WARM_WHITE, value=ww },
      { color_component_id=SwitchColor.color_component_id.COLD_WHITE, value=cw },
    },
    duration=duration
  })
  device:send(set)
  local query_temp = function()
    device:send(Configuration:Get({ parameter_number=parameter_number }))
  end
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_temp)
end

--- Issue appropriate Get commands to bootstrap initial state.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
function capability_handlers.refresh(driver, device)
  device:send(SwitchMultilevel:Get({}))
  device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED }))
  device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.GREEN }))
  device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.BLUE }))
  device:send(Configuration:Get({ parameter_number=WARM_WHITE_CONFIG }))
  device:send(Configuration:Get({ parameter_number=COLD_WHITE_CONFIG }))
end

--- Determine whether the passed device is an Aeotec LED Bulb 6.
---
--- @param driver Driver driver instance
--- @param device Device device isntance
--- @return boolean true if the device is an Aeotec LED Bulb 6, else false
local function is_aeotec_led_bulb_6(opts, driver, device, ...)
  return device:id_match(
    AEOTEC_MFR_ID,
    { AEOTEC_LED_BULB_6_PRODUCT_TYPE_US, AEOTEC_LED_BULB_6_PRODUCT_TYPE_EU },
    AEOTEC_LED_BULB_6_PRODUCT_ID)
end

local aeotec_led_bulb_6 = {
  NAME = "Aeotec LED Bulb 6",
  zwave_handlers = {
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = zwave_handlers.configuration_report
    }
  },
  capability_handlers = {
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = capability_handlers.set_color_temperature
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = capability_handlers.refresh
    }
  },
  can_handle = is_aeotec_led_bulb_6,
}

return aeotec_led_bulb_6
