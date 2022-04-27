-- Copyright 2021 SmartThings
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
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.SwitchMultilevel
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({version=4,strict=true})
--- @type st.zwave.constants
local constants = require "st.zwave.constants"

local capability_handlers = {}
--- Issue a level-set command to the specified device.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command table ST level capability command
--- @param map_fan_speed_to_switch_level function
---        convert 0-99 switch level range into 0-4 fan speed range
function capability_handlers.fan_speed_set(driver, device, command, map_fan_speed_to_switch_level)
  if map_fan_speed_to_switch_level == nil then
    error ("Invalid map_fan_speed_to_switch_level function provided.")
  end

  local level = map_fan_speed_to_switch_level(command.args.speed)
  local duration = constants.DEFAULT_DIMMING_DURATION
  local set = SwitchMultilevel:Set({ value=level, duration=duration })
  device:send(set)
  local query_level = function()
    device:send(SwitchMultilevel:Get({}))
  end
  device.thread:call_with_delay(constants.DEFAULT_GET_STATUS_DELAY + duration, query_level)
end

local zwave_handlers = {}



--- Convert `SwitchMultilevel` level {0 - 99}
--- into `FanSpeed` speed { 0, 1, 2, 3, 4}
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param cmd st.zwave.CommandClass.SwitchMultilevel
function zwave_handlers.fan_multilevel_report(driver, device, cmd, map_switch_level_to_fan_speed)
  local event
  if cmd.args.target_value ~= nil and cmd.args.target_value >= 0 then
    -- Target value is our best inidicator of eventual state.
    -- If we see this, it should be considered authoritative.
    event = capabilities.fanSpeed.fanSpeed(map_switch_level_to_fan_speed(cmd.args.target_value))
  elseif cmd.args.value ~= nil and cmd.args.value >= 0 then
    event = capabilities.fanSpeed.fanSpeed(map_switch_level_to_fan_speed(cmd.args.value))
  end

  if event ~= nil then
    device:emit_event(event)
  end

  -- emit events SwitchLevel capabilities
  local switch_report_handlers = driver.zwave_handlers[cc.SWITCH_MULTILEVEL][SwitchMultilevel.REPORT]
  for _, handler in ipairs(switch_report_handlers) do
    handler(driver, device, cmd)
  end
end

local helpers  = {
  capability_handlers = capability_handlers,
  zwave_handlers = zwave_handlers,
  fan_speed = {
    OFF = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
    MAX = 4
  },
  levels_for_3_speed = {
    OFF = 0,
    LOW = 32, -- 3-Speed Fan Controller treat 33 as medium
    MEDIUM = 66,
    HIGH = 99,
    MAX = 99,
  },
  levels_for_4_speed = {
    OFF = 0,
    LOW = 25,
    MEDIUM = 50,
    HIGH = 75,
    MAX = 99,
  }
}

return helpers
