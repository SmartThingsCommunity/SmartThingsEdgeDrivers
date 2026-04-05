-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


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
  can_handle = require("sinope.can_handle"),
}

return sinope_valve
