-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local capabilities = require "st.capabilities"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2,strict=true})
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version=2})
local t_utils = require "integration_test.utils"

local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.NOTIFICATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.SWITCH_BINARY},
    }
  }
}

local mock_sensor = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("motion-light.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x0060,
  zwave_product_type = 0x0012,
  zwave_product_id = 0x0001,
})

local function test_init()
  test.mock_device.add_test_device(mock_sensor)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Added lifecycle event should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_sensor.id, "added" }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SwitchBinary:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_sensor,
        SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
