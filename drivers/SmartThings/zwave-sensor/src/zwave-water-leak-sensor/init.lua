-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })

local function basic_set_handler(driver, device, cmd)
  local value = cmd.args.target_value and cmd.args.target_value or cmd.args.value
  device:emit_event(value == 0xFF and capabilities.waterSensor.water.wet() or capabilities.waterSensor.water.dry())
end

local water_leak_sensor = {
  NAME = "Water Leak Sensor",
  zwave_handlers = {
    [cc.BASIC] = {
      [Basic.SET] = basic_set_handler
    }
  },
  can_handle = require("zwave-water-leak-sensor.can_handle"),
}

return water_leak_sensor
