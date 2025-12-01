-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })
local t_utils = require "integration_test.utils"

local FIBARO_WALLI_DOUBLE_SWITCH_MANUFACTURER_ID = 0x010F
local FIBARO_WALLI_DOUBLE_SWITCH_PRODUCT_TYPE = 0x1B01
local FIBARO_WALLI_DOUBLE_SWITCH_PRODUCT_ID = 0x1000

local fibaro_walli_double_switch_endpoints = {
  {command_classes = {
    {value = zw.METER},
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }},
  {command_classes = {
    {value = zw.METER},
    {value = zw.BASIC},
    {value = zw.SWITCH_BINARY}
  }}
}

local mock_fibaro_walli_double_switch = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-walli-double-switch.yml"),
  zwave_endpoints = fibaro_walli_double_switch_endpoints,
  zwave_manufacturer_id = FIBARO_WALLI_DOUBLE_SWITCH_MANUFACTURER_ID,
  zwave_product_type = FIBARO_WALLI_DOUBLE_SWITCH_PRODUCT_TYPE,
  zwave_product_id = FIBARO_WALLI_DOUBLE_SWITCH_PRODUCT_ID
})

local function test_init()
  test.mock_device.add_test_device(mock_fibaro_walli_double_switch)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Parameter 11 should be updated in the device configuration after change",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_double_switch:generate_info_changed({preferences = {ledFrameColourWhenOn = 7}}))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_walli_double_switch,
        Configuration:Set({
          parameter_number = 11,
          configuration_value = 7,
          size=1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Parameter 12 should be updated in the device configuration after change",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_double_switch:generate_info_changed({preferences = {ledFrameColourWhenOff = 1}}))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_walli_double_switch,
        Configuration:Set({
          parameter_number = 12,
          configuration_value = 1,
          size=1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Parameter 13 should be updated in the device configuration after change",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_double_switch:generate_info_changed({preferences = {ledFrameBrightness = 50}}))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_walli_double_switch,
        Configuration:Set({
          parameter_number = 13,
          configuration_value = 50,
          size=1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Parameter 20 should be updated in the device configuration after change",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_double_switch:generate_info_changed({preferences = {buttonsOperation = 2}}))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_walli_double_switch,
        Configuration:Set({
          parameter_number = 20,
          configuration_value = 2,
          size=1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Parameter 24 should be updated in the device configuration after change",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_double_switch:generate_info_changed({preferences = {buttonsOrientation = true}}))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_walli_double_switch,
        Configuration:Set({
          parameter_number = 24,
          configuration_value = 1,
          size=1
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Parameter 25 should be updated in the device configuration after change",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_fibaro_walli_double_switch:generate_info_changed({preferences = {outputsOrientation = true}}))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_walli_double_switch,
        Configuration:Set({
          parameter_number = 25,
          configuration_value = 1,
          size=1
        })
      )
    )
  end
)

test.run_registered_tests()
