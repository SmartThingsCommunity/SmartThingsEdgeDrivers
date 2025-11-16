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
--- @type st.zwave.CommandClass.Association
local Association = (require "st.zwave.CommandClass.Association")({ version = 2 })
--- @type st.zwave.CommandClass.SwitchColor
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version = 1 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 1 })
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"

local utils = require "st.utils"

local ColorControlDefaults = require "st.zwave.defaults.colorControl"
local SwitchLevelDefaults = require "st.zwave.defaults.switchLevel"

local CAP_CACHE_KEY = "st.capabilities." .. capabilities.colorControl.ID
local LAST_COLOR_SWITCH_CMD_FIELD = "lastColorSwitchCmd"
local FAKE_RGB_ENDPOINT = 10

local FIBARO_MFR_ID = 0x010F
local FIBARO_RGBW_CONTROLLER_PROD_TYPE = 0x0900
local FIBARO_RGBW_CONTROLLER_PROD_ID_US = 0x2000
local FIBARO_RGBW_CONTROLLER_PROD_ID_EU = 0x1000

local function is_fibaro_rgbw_controller(opts, driver, device, ...)
  return device:id_match(
    FIBARO_MFR_ID,
    FIBARO_RGBW_CONTROLLER_PROD_TYPE,
    {FIBARO_RGBW_CONTROLLER_PROD_ID_US, FIBARO_RGBW_CONTROLLER_PROD_ID_EU}
  )
end

-- This handler is copied from defaults with scraped of sets for both WHITE channels
local function set_color(driver, device, command)
  local r, g, b = utils.hsl_to_rgb(command.args.color.hue, command.args.color.saturation, command.args.color.lightness)
  if r > 0 or g > 0 or b > 0 then
    device:set_field(CAP_CACHE_KEY, command)
  end
  local set = SwitchColor:Set({
    color_components = {
      { color_component_id=SwitchColor.color_component_id.RED, value=r },
      { color_component_id=SwitchColor.color_component_id.GREEN, value=g },
      { color_component_id=SwitchColor.color_component_id.BLUE, value=b },
    }
  })
  device:send(set)
  local query_color = function()
    -- Use a single RGB color key to trigger our callback to emit a color
    -- control capability update.
    if r ~= 0 and g ~= 0 and b ~= 0 then
      device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED }))
    else
      device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED }))
    end
  end
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_color)
end

local function switch_color_report(self, device, command)
  local event
  if command.args.color_component_id == SwitchColor.color_component_id.WARM_WHITE then
    local value = command.args.value
    if value > 0 then
      event = capabilities.switch.switch.on()
    else
      event = capabilities.switch.switch.off()
    end
    device:emit_component_event(device.profile.components["white"], event)
  else
    if device:get_field(LAST_COLOR_SWITCH_CMD_FIELD) == 0 and command.args.value == 0 then
      event = capabilities.switch.switch.off()
    else
      event = capabilities.switch.switch.on()
    end
    device:emit_component_event(device.profile.components["rgb"], event)
    command.src_channel = FAKE_RGB_ENDPOINT
    ColorControlDefaults.zwave_handlers[cc.SWITCH_COLOR][SwitchColor.REPORT](self, device, command)
  end
end

local function switch_multilevel_report(self, device, command)
  local endpoint = command.src_channel
  -- ignore multilevel reports from endpoints [1, 2, 3, 4] which mirror SwitchColor values
  -- and in addition cause wrong SwitchLevel events
  if not (endpoint >= 1 and endpoint <= 4) then
    if command.args.value == SwitchMultilevel.value.OFF_DISABLE then
      local event = capabilities.switch.switch.off()
      device:emit_component_event(device.profile.components["white"], event)
      device:emit_component_event(device.profile.components["rgb"], event)
    else
      SwitchLevelDefaults.zwave_handlers[cc.SWITCH_MULTILEVEL][SwitchMultilevel.REPORT](self, device, command)
    end
    local query = function()
      device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE }))
      device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED }))
    end
    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query)
  end
end

local function set_switch(driver, device, command, value)
  if command.component == "white" then
    local set = SwitchColor:Set({
      color_components = {
        { color_component_id=SwitchColor.color_component_id.WARM_WHITE, value = value },
      }
    })
    device:send(set)
    local query_white = function()
      device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE }))
    end
    device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_white)
  elseif command.component == "rgb" then
    device:set_field(LAST_COLOR_SWITCH_CMD_FIELD, value)
    if value == 255 then
      local setColorCommand = device:get_field(CAP_CACHE_KEY)
      if setColorCommand ~= nil then
        set_color(driver, device, setColorCommand)
      else
        local mockCommand = {args = {color = {hue = 0, saturation = 50}}}
        set_color(driver, device, mockCommand)
      end
    else
      local set = SwitchColor:Set({
        color_components = {
          { color_component_id=SwitchColor.color_component_id.RED, value=0 },
          { color_component_id=SwitchColor.color_component_id.GREEN, value=0 },
          { color_component_id=SwitchColor.color_component_id.BLUE, value=0 }
        }
      })
      device:send(set)
      local query_color = function()
        device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.RED }))
      end
      device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY, query_color)
    end
  end
end

local function set_switch_on(driver, device, command)
  set_switch(driver, device, command, 255)
end

local function set_switch_off(driver, device, command)
  set_switch(driver, device, command, 0)
end

local function device_added(self, device)
  device:send(Association:Set({grouping_identifier = 5, node_ids = {self.environment_info.hub_zwave_id}}))
  device:refresh()
end

local function endpoint_to_component(device, ep)
  if ep == FAKE_RGB_ENDPOINT then
    return "rgb"
  else
    return "main"
  end
end

local function device_init(self, device)
  device:set_endpoint_to_component_fn(endpoint_to_component)
end

local fibaro_rgbw_controller = {
  NAME = "Fibaro RGBW Controller",
  zwave_handlers = {
    [cc.SWITCH_COLOR] = {
      [SwitchColor.REPORT] = switch_color_report
    },
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.REPORT] = switch_multilevel_report
    }
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = set_switch_on,
      [capabilities.switch.commands.off.NAME] = set_switch_off
    },
    [capabilities.colorControl.ID] = {
      [capabilities.colorControl.commands.setColor.NAME] = set_color
    },
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init
  },
  can_handle = is_fibaro_rgbw_controller,
}

return fibaro_rgbw_controller
