-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"

local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=2 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })

local aeotec_smart_switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.METER },
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("metering-switch.yml"),
  zwave_endpoints = aeotec_smart_switch_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x0060
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should use Basic SETs and GETs despite supporting Switch Multilevel (on)",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", command = "on", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({
          value = 0xFF
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Device should use Basic SETs and GETs despite supporting Switch Multilevel (off)",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(3, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", command = "off", args = {}}
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Basic:Set({
          value = 0x00
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(3)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({})
      )
    )
  end
)

test.run_registered_tests()
