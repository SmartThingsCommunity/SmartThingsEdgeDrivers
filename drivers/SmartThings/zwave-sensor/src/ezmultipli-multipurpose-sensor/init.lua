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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({version=1})
--- @type st.zwave.CommandClass.SwitchColor
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({version=1})
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})

local CAP_CACHE_KEY = "st.capabilities." .. capabilities.colorControl.ID

local EZMULTIPLI_MULTIPURPOSE_SENSOR_FINGERPRINTS = {
  { manufacturerId = 0x001E, productType = 0x0004, productId = 0x0001 }
}

local function can_handle_ezmultipli_multipurpose_sensor(opts, driver, device, ...)
  for _, fingerprint in ipairs(EZMULTIPLI_MULTIPURPOSE_SENSOR_FINGERPRINTS) do
    if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
      return true
    end
  end
  return false
end

local function basic_report_handler(driver, device, cmd)
  local event
  local value = (cmd.args.target_value ~= nil) and cmd.args.target_value or cmd.args.value
  if value == SwitchBinary.value.OFF_DISABLE then
    event = capabilities.switch.switch.off()
    device:emit_event_for_endpoint(cmd.src_channel, capabilities.colorControl.hue(0))
    device:emit_event_for_endpoint(cmd.src_channel, capabilities.colorControl.saturation(0))
  else
    event = capabilities.switch.switch.on()
  end

  device:emit_event_for_endpoint(cmd.src_channel, event)
end

local function set_color(driver, device, command)
  local hue = command.args.color.hue
  local saturation = command.args.color.saturation

  local r, g, b = utils.hsl_to_rgb(hue, saturation)

  -- device only supports a value of 255 or 0 for each color channel
  r = (r >= 191) and 255 or 0
  g = (g >= 191) and 255 or 0
  b = (b >= 191) and 255 or 0

  local myhue, mysaturation = utils.rgb_to_hsl(r, g, b)

  command.args.color.hue = myhue
  command.args.color.saturation = mysaturation

  device:set_field(CAP_CACHE_KEY, command)

  local set = SwitchColor:Set({
    color_components = {
      { color_component_id=SwitchColor.color_component_id.RED, value=r },
      { color_component_id=SwitchColor.color_component_id.GREEN, value=g },
      { color_component_id=SwitchColor.color_component_id.BLUE, value=b }
    },
  })
  device:send_to_component(set, command.component)
  local query_color = function()
    -- Use a single RGB color key to trigger our callback to emit a color
    -- control capability update.
    device:send_to_component(
      SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED }),
      command.component
    )
  end
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_color)
end

local ezmultipli_multipurpose_sensor = {
  NAME = "EZmultiPli Multipurpose Sensor",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = basic_report_handler
    },
  },
  capability_handlers = {
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    }
  },
  can_handle = can_handle_ezmultipli_multipurpose_sensor
}

return ezmultipli_multipurpose_sensor