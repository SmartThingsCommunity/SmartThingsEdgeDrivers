-- Copyright 2023 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })
--- @type st.zwave.CommandClass.SensorBinary
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({version = 2})
--- @type st.zwave.CommandClass.Battery
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

local sensor_endpoints = {
  {
    command_classes = {
      {value = cc.WAKE_UP},
      {value = cc.SENSOR_BINARY},
      {value = cc.BATTERY},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("contact-battery-tamperalert.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x014F,
  zwave_product_type = 0x2001,
  zwave_product_id = 0x0102,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Wakeup notification should not poll binary sensor if device has contact state",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command( WakeUp:Notification({ })) }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SensorBinary:Get({sensor_type = SensorBinary.sensor_type.DOOR_WINDOW})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Battery:Get({ })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        WakeUp:IntervalGet({ })
      )
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command( SensorBinary:Report({
        sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
        sensor_value = 0x00
      })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command( WakeUp:Notification({ })) }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Battery:Get({ })
      )
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.run_registered_tests()
