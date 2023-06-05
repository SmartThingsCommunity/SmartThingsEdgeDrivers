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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Basic = (require "st.zwave.CommandClass.Basic")({ version=1 })

-- supported comand classes
local sensor_endpoints = {
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.METER},
      {value = zw.CENTRAL_SCENE}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("switch-button-power-energy.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x010F,
    zwave_product_type = 0x0403,
    zwave_product_id = 0x1000
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should use Basic SETs despite supporting Switch Multilevel (on)",
  function ()
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
  end
)

test.register_coroutine_test(
  "Device should use Basic SETs despite supporting Switch Multilevel (off)",
  function ()
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
  end
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.ON_ENABLE
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE from source channel 2 should be discarded",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.OFF_DISABLE
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE from source channel 2 should be discarded",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report(
            {
              current_value=SwitchBinary.value.OFF_DISABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_PRESSED_1_TIME attribute should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 2,
              key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.pushed({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_PRESSED_1_TIME attribute from source channel 2 should be discared",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 2,
              key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_RELEASED attribute should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 1,
        key_attributes=CentralScene.key_attributes.KEY_RELEASED}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.held({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_RELEASED attribute from source channel 2 should be discared",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 2,
              key_attributes=CentralScene.key_attributes.KEY_RELEASED
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_HELD_DOWN attribute should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 2,
        key_attributes=CentralScene.key_attributes.KEY_HELD_DOWN}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.down_hold({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_HELD_DOWN attribute from source channel 2 should be discared",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 2,
              key_attributes=CentralScene.key_attributes.KEY_HELD_DOWN
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_PRESSED_2_TIMES attribute should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_2_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.double({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_PRESSED_2_TIMES attribute from source channel 2 should be discared",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 2,
              key_attributes=CentralScene.key_attributes.KEY_PRESSED_2_TIMES
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_PRESSED_3_TIMES attribute should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_3_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.pushed_3x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification KEY_PRESSED_3_TIMES attribute from source channel 2 should be discared",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 2,
              key_attributes=CentralScene.key_attributes.KEY_PRESSED_3_TIMES
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_message_test(
  "Energy meter report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
        scale = Meter.scale.electric_meter.KILOWATT_HOURS,
        meter_value = 5})
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    }
  }
)

test.register_message_test(
  "Energy meter report from source channel 2 should be discarded",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report(
            {
              scale = Meter.scale.electric_meter.KILOWATT_HOURS,
              meter_value = 5
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    },
  }
)

test.register_message_test(
  "Power meter report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report({
        scale = Meter.scale.electric_meter.WATTS,
        meter_value = 27})
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 27, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Power meter report  from source channel 2 should be discarded",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          Meter:Report(
            {
              scale = Meter.scale.electric_meter.WATTS,
              meter_value = 5
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels={0}
            }
          )
        )
      }
    }
  }
)

test.register_coroutine_test(
    "infoChanged() should send the SET command for Configuration value",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive({mock_device.id, "init"})
      test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed(
          {
              preferences = {
                restoreState = 0,
                ch1OperatingMode = 2,
                ch1ReactionToSwitch = 2,
                ch1TimeParameter = 500,
                ch1PulseTime = 50,
                switchType = 0,
                flashingReports = 1,
                s1ScenesSent = 2,
                s2ScenesSent = 3,
                ch1EnergyReports = 500,
                periodicPowerReports = 10,
                periodicEnergyReports = 600
              }
          }
      ))

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=9, size=1, configuration_value=0})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=10, size=1, configuration_value=2})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=11, size=1, configuration_value=2})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=12, size=2, configuration_value=500})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=13, size=2, configuration_value=50})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=20, size=1, configuration_value=0})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=21, size=1, configuration_value=1})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=28, size=1, configuration_value=2})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=29, size=1, configuration_value=3})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
            Configuration:Set({parameter_number=53, size=2, configuration_value=500})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=58, size=2, configuration_value=10})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=59, size=2, configuration_value=600})
          )
      )

    end
)

test.run_registered_tests()
