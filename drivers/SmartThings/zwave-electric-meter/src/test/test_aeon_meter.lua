-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
local t_utils = require "integration_test.utils"

local AEON_MFR_ID = 0x0086
local AEON_METER_PROD_TYPE = 0x0002
local AEON_METER_PROD_ID = 0x0009

local aeon_meter_endpoints = {
  {
    command_classes = {
      {value = zw.METER}
    }
  }
}

local mock_meter = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-electric-meter.yml"),
  zwave_endpoints = aeon_meter_endpoints,
  zwave_manufacturer_id = AEON_MFR_ID,
  zwave_product_type = AEON_METER_PROD_TYPE,
  zwave_product_id = AEON_METER_PROD_ID
})


local function test_init()
  test.mock_device.add_test_device(mock_meter)
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Power meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_meter.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 27})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_meter:generate_test_message("main", capabilities.powerMeter.power({ value = 27, unit = "W" }))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Energy meter report should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_meter.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5})
        )}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_meter:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
      }
    },
    {
       min_api_version = 19
    }
)

test.register_message_test(
    "Refresh shall include Meter:Get()",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_meter.id, "added" },
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Meter:Get({scale = Meter.scale.electric_meter.WATTS})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS})
        )
      },
    },
    {
      inner_block_ordering = "relaxed"
    },
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "Aeon Meter should be configured correctly",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_meter.id, "doConfigure" })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Configuration:Set({parameter_number = 101, size = 4, configuration_value = 4})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Configuration:Set({parameter_number = 111, size = 4, configuration_value = 300})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Configuration:Set({parameter_number = 102, size = 4, configuration_value = 8})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Configuration:Set({parameter_number = 112, size = 4, configuration_value = 300})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_meter,
          Configuration:Set({parameter_number = 103, size = 4, configuration_value = 0})
      ))
      mock_meter:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end,
    {
       min_api_version = 19
    }
)


test.run_registered_tests()
