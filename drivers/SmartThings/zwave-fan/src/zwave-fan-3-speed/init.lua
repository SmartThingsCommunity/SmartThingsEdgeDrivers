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

local log = require "log"
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Basic
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local fan_speed_helper = (require "zwave_fan_helpers")

local FAN_3_SPEED_FINGERPRINTS = {
  {mfr = 0x001D, prod = 0x1001, model = 0x0334}, -- Leviton 3-Speed Fan Controller
  {mfr = 0x0063, prod = 0x4944, model = 0x3034}, -- GE In-Wall Smart Fan Control
  {mfr = 0x0063, prod = 0x4944, model = 0x3131}, -- GE In-Wall Smart Fan Control
  {mfr = 0x0039, prod = 0x4944, model = 0x3131}, -- Honeywell Z-Wave Plus In-Wall Fan Speed Control
  {mfr = 0x0063, prod = 0x4944, model = 0x3337}, -- GE In-Wall Smart Fan Control
}

local function map_fan_3_speed_to_switch_level (speed)
  if speed == fan_speed_helper.fan_speed.OFF then
    return fan_speed_helper.levels_for_3_speed.OFF -- off
  elseif speed == fan_speed_helper.fan_speed.LOW then
    return fan_speed_helper.levels_for_3_speed.LOW -- low
  elseif speed == fan_speed_helper.fan_speed.MEDIUM then
    return fan_speed_helper.levels_for_3_speed.MEDIUM -- mediom
  elseif speed == fan_speed_helper.fan_speed.HIGH or speed == fan_speed_helper.fan_speed.MAX then
    return fan_speed_helper.levels_for_3_speed.HIGH -- high and max
  else
    log.error (string.format("3 speed fan driver: invalid speed: %d", speed))
  end
end

local function map_switch_level_to_fan_3_speed (level)
  if (level == fan_speed_helper.levels_for_3_speed.OFF) then
    return fan_speed_helper.fan_speed.OFF
  elseif (fan_speed_helper.levels_for_3_speed.OFF < level and level <= fan_speed_helper.levels_for_3_speed.LOW) then
    return fan_speed_helper.fan_speed.LOW
  elseif (fan_speed_helper.levels_for_3_speed.LOW < level and level <= fan_speed_helper.levels_for_3_speed.MEDIUM) then
    return fan_speed_helper.fan_speed.MEDIUM
  elseif (fan_speed_helper.levels_for_3_speed.MEDIUM < level and level <= fan_speed_helper.levels_for_3_speed.MAX) then
    return fan_speed_helper.fan_speed.HIGH
  else
    log.error (string.format("3 speed fan driver: invalid level: %d", level))
  end
end

--- Determine whether the passed device is a 3-speed fan
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @return boolean true if the device is an 3-speed fan, else false
local function is_fan_3_speed(opts, driver, device, ...)
  for _, fingerprint in ipairs(FAN_3_SPEED_FINGERPRINTS) do
    if device:id_match(fingerprint.mfr, fingerprint.prod, fingerprint.model) then
      return true
    end
  end
  return false
end

local capability_handlers = {}

--- Issue a level-set command to the specified device.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command table ST level capability command
function capability_handlers.fan_speed_set(driver, device, command)
  fan_speed_helper.capability_handlers.fan_speed_set(driver, device, command, map_fan_3_speed_to_switch_level)
end

local zwave_handlers = {}

--- Convert `SwitchMultilevel` level {0 - 99}
--- into `FanSpeed` speed { 0, 1, 2, 3, 4}
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.SwitchMultilevel.Report
function zwave_handlers.fan_multilevel_report(driver, device, cmd)
  fan_speed_helper.zwave_handlers.fan_multilevel_report(driver, device, cmd, map_switch_level_to_fan_3_speed)
end

local zwave_fan_3_speed = {
  capability_handlers = {
    [capabilities.fanSpeed.ID] = {
      [capabilities.fanSpeed.commands.setFanSpeed.NAME] = capability_handlers.fan_speed_set
    }
  },
  zwave_handlers = {
    [cc.SWITCH_MULTILEVEL] = {
      [SwitchMultilevel.REPORT] = zwave_handlers.fan_multilevel_report
    },
    [cc.BASIC] = {
      [Basic.REPORT] = zwave_handlers.fan_multilevel_report
    }
  },
  NAME = "Z-Wave fan 3 speed",
  can_handle = is_fan_3_speed,
}

return zwave_fan_3_speed
