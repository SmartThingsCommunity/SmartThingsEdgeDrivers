-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.utils
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
--- @type st.zwave.CommandClass.Configuration
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
--- @type st.zwave.CommandClass.SwitchColor
local SwitchColor = (require "st.zwave.CommandClass.SwitchColor")({ version = 3 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })


local WARM_WHITE_CONFIG = 0x51
local COLD_WHITE_CONFIG = 0x52
local SWITCH_COLOR_QUERY_DELAY = 2
local DEFAULT_COLOR_TEMPERATURE = 2700


local function onoff_level_report_handler(self, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  device:emit_event(value == SwitchMultilevel.value.OFF_DISABLE and capabilities.switch.switch.off() or capabilities.switch.switch.on())

  if value >= 0 then
    device:emit_event(capabilities.switchLevel.level(value >= 99 and 100 or value))
  end
end

local function switch_color_report(driver, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value

  if value == 0xFF then
    local parameter_number = cmd.args.color_component_id == SwitchColor.color_component_id.WARM_WHITE and WARM_WHITE_CONFIG or COLD_WHITE_CONFIG
    device:send(Configuration:Get({parameter_number = parameter_number}))
  end
end

local function configuration_report(driver, device, cmd)
  local parameter_number = cmd.args.parameter_number

  if parameter_number == WARM_WHITE_CONFIG or parameter_number == COLD_WHITE_CONFIG then
    device:emit_event(capabilities.colorTemperature.colorTemperature(cmd.args.configuration_value))
  end
end

local function set_color_temperature(driver, device, cmd)
  local temp = cmd.args.temperature
  temp = utils.round(temp)
  local warm_value = temp < 5000 and 255 or 0
  local cold_value = temp >= 5000 and 255 or 0
  local parameter_number = temp < 5000 and WARM_WHITE_CONFIG or COLD_WHITE_CONFIG

  device:send(Configuration:Set({parameter_number = parameter_number, size = 2, configuration_value = cmd.args.temperature}))
  device:send(SwitchColor:Set({
    color_components = {
      { color_component_id=SwitchColor.color_component_id.WARM_WHITE, value=warm_value },
      { color_component_id=SwitchColor.color_component_id.COLD_WHITE, value=cold_value }
    }
  }))

  local is_on = device:get_latest_state("main", capabilities.switch.ID, capabilities.switch.switch.NAME)
  if is_on == "off" then
    device:send(SwitchMultilevel:Set({value = 0xFF}))
    device:send(SwitchMultilevel:Get({}))
  end

  local query_temp = function()
    device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.WARM_WHITE }))
    device:send(SwitchColor:Get({ color_component_id=SwitchColor.color_component_id.COLD_WHITE }))
  end
  device.thread:call_with_delay(SWITCH_COLOR_QUERY_DELAY, query_temp)
end

local device_added = function(self, device)
  device:emit_event(capabilities.colorTemperature.colorTemperature(DEFAULT_COLOR_TEMPERATURE))
end

local aeon_multiwhite_bulb = {
  NAME = "aeon multiwhite bulb",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.REPORT] = onoff_level_report_handler,
      [Basic.SET] = onoff_level_report_handler
    },
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.REPORT] = onoff_level_report_handler
    },
    [cc.SWITCH_COLOR] = {
      [SwitchColor.REPORT] = switch_color_report
    },
    [cc.CONFIGURATION] = {
      [Configuration.REPORT] = configuration_report
    }
  },
  capability_handlers = {
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = set_color_temperature
    }
  },
  can_handle = require("aeon-multiwhite-bulb.can_handle"),
  lifecycle_handlers = {
    added = device_added
  }
}

return aeon_multiwhite_bulb
