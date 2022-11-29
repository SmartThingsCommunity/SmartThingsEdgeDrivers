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

local clusters = require "st.zigbee.zcl.clusters"
local battery_defaults = require "st.zigbee.defaults.battery_defaults"
local capabilities = require "st.capabilities"
local utils = require "st.utils"

local PowerConfiguration = clusters.PowerConfiguration

local function device_init(driver, device)
  battery_defaults.use_battery_voltage_handling(device)
  -- according to the DTH, this attribute cannot be configured for reporting
  device.thread:call_on_schedule(900, function() device:send(PowerConfiguration.attributes.BatteryVoltage:read()) end)
end

local function battery_voltage_handler(driver, device, command)
  -- this is cribbed from the DTH
  local value = command.value
  local levelsTable = {0, 20000, 40000, 60000, 80000, 100000}
  local anglesTable = {30, 55, 56, 57, 58.5, 60}

  if (value > anglesTable[#anglesTable]) then -- if the value of the angle is greater than the maximum
    value = anglesTable[#anglesTable] -- use the maximum value instead
  end

  local index = 2

  while value > anglesTable[index] do index = index+1 end

  local ratioBetweenPointXandY = (levelsTable[index] - levelsTable[index - 1]) / (anglesTable[index] - anglesTable[index - 1])
  local angleToAdd = levelsTable[index] - (anglesTable[index] * ratioBetweenPointXandY)
  local levelWithFactor = (ratioBetweenPointXandY * value) + angleToAdd
  local roundedLevelValue = utils.clamp_value(utils.round(levelWithFactor / 1000), 0, 100)

  device:emit_event(capabilities.battery.battery(roundedLevelValue))
end

local sinope_valve = {
  NAME = "Sinope Valve",
  zigbee_handlers = {
    attr = {
      [PowerConfiguration.ID] = {
        [PowerConfiguration.attributes.BatteryVoltage.ID] = battery_voltage_handler
      }
    }
  },
  lifecycle_handlers = {
    init = device_init
  },
  can_handle = function(opts, driver, device, ...)
    return device:get_manufacturer() == "Sinope Technologies"
  end
}

return sinope_valve
