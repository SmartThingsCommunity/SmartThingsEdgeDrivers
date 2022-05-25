local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local zooz_zen_dimmer_relay_endpoints = {
  {
    command_classes = {
      { value = zw.METER },
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL }
    }
  }
}

local zooz_zen_dimmer_relay = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("zooz-zen-30-dimmer-relay.yml"),
  zwave_endpoints = zooz_zen_dimmer_relay_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA008
})

local function test_init()
  test.mock_device.add_test_device(zooz_zen_dimmer_relay)
end
test.set_test_init_function(test_init)

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter powerFailureParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { powerFailureParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 12,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 0
  test.register_coroutine_test(
    "Parameter ledSceneControlParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { ledSceneControlParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 7,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter relayLedModeParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { relayLedModeParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 2,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter relayLedColorParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { relayLedColorParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 4,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter relayLedBrightnessParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { relayLedBrightnessParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 6,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 10
  test.register_coroutine_test(
    "Parameter relayAutoOffParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { relayAutoOffParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 10,
            configuration_value = new_param_value,
            size = 4
          })
        )
      )
    end
  )
end

do
  local new_param_value = 5
  test.register_coroutine_test(
    "Parameter relayAutoOnParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { relayAutoOnParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 11,
            configuration_value = new_param_value,
            size = 4
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter relayLoadControlParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { relayLoadControlParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 20,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter relayPhysicalDisabledBeh should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { relayPhysicalDisabledBeh = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 25,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerLedModeParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerLedModeParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 1,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerLedColorParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerLedColorParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 3,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerLedBrightParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerLedBrightParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 5,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 15
  test.register_coroutine_test(
    "Parameter dimmerAutoOffParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerAutoOffParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 8,
            configuration_value = new_param_value,
            size = 4
          })
        )
      )
    end
  )
end

do
  local new_param_value = 15
  test.register_coroutine_test(
    "Parameter dimmerAutoOnParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerAutoOnParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 9,
            configuration_value = new_param_value,
            size = 4
          })
        )
      )
    end
  )
end

do
  local new_param_value = 50
  test.register_coroutine_test(
    "Parameter dimmerRampRateParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerRampRateParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 13,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 50
  test.register_coroutine_test(
    "Parameter dimmerPaddleRampParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerPaddleRampParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 21,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerMinimumBrightParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerMinimumBrightParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 14,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerMaximumBrightParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerMaximumBrightParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 15,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerCustomBrightParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerCustomBrightParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 23,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerBrightControlParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerBrightControlParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 18,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter dimmerDoubleTapFuncParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerDoubleTapFuncParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 17,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerLoadControlParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerLoadControlParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 19,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 1
  test.register_coroutine_test(
    "Parameter dimmerPhysDisBehParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerPhysDisBehParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 24,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerNightBrightParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerNightBrightParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 26,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

do
  local new_param_value = 2
  test.register_coroutine_test(
    "Parameter dimmerPaddleControlParam should be updated in the device configuration after change",
    function()
      test.socket.device_lifecycle:__queue_receive(zooz_zen_dimmer_relay:generate_info_changed({ preferences = { dimmerPaddleControlParam = new_param_value } }))
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          zooz_zen_dimmer_relay,
          Configuration:Set({
            parameter_number = 27,
            configuration_value = new_param_value,
            size = 1
          })
        )
      )
    end
  )
end

test.run_registered_tests()
