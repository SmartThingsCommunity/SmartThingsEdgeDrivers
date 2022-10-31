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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})
local Configuration = (require "st.zwave.CommandClass.Configuration")({version=1})

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
  },
  {
    command_classes = {
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY},
      {value = zw.SWITCH_MULTILEVEL},
      {value = zw.METER}
    }
  },
  {
    command_classes = {
      {value = zw.CENTRAL_SCENE}
    }
  },
  {
    command_classes = {
      {value = zw.CENTRAL_SCENE}
    }
  },
  {
    command_classes = {
      {value = zw.CENTRAL_SCENE}
    }
  },
  {
    command_classes = {
      {value = zw.CENTRAL_SCENE}
    }
  },
  {
    command_classes = {
      {value = zw.CENTRAL_SCENE}
    }
  },
  {
    command_classes = {
      {value = zw.CENTRAL_SCENE}
    }
  }
}

local switch_endpoints = {
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  },
  {
    command_classes = {
      {value = zw.SWITCH_BINARY}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("switch-1-button-6-power-energy.yml"),
    zwave_endpoints = sensor_endpoints,
    zwave_manufacturer_id = 0x010F,
    zwave_product_type = 0x0203,
    zwave_product_id = 0x1000
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by main componet",
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
              src_channel = 1,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    }
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by main switch1 component",
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
              dst_channels={2}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1", capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by main componet",
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
              src_channel = 0,
              dst_channels={0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by main switch1 component",
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
              dst_channels={2}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1", capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({scale = Meter.scale.electric_meter.WATTS},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    }
  }
)

test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    )
  end
)


test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs with dest_channel 1",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "switch1", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "main", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={1}
        })
      )
    )
  end
)


test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs with dest_channel 1",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "switch1", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchBinary:Get({},
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={2}
        })
      )
    )
  end
)

test.register_message_test(
  "Central Scene notification Button pushed should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button1", capabilities.button.button.pushed({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
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
      message = mock_device:generate_test_message("button1", capabilities.button.button.held({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button down_hold should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 1,
        key_attributes=CentralScene.key_attributes.KEY_HELD_DOWN}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button1", capabilities.button.button.down_hold({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button double should be handled",
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
      message = mock_device:generate_test_message("button3", capabilities.button.button.double({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button pushed_3x should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 1,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_3_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button5", capabilities.button.button.pushed_3x({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button pushed should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_1_TIME}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button2", capabilities.button.button.pushed({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button held should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 2,
        key_attributes=CentralScene.key_attributes.KEY_RELEASED}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button2", capabilities.button.button.held({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button down_hold should be handled",
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
      message = mock_device:generate_test_message("button2", capabilities.button.button.down_hold({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button double should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(CentralScene:Notification({
        scene_number = 2,
        key_attributes=CentralScene.key_attributes.KEY_PRESSED_2_TIMES}))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button4", capabilities.button.button.double({
        state_change = true }))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button pushed should be handled",
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
      message = mock_device:generate_test_message("button6", capabilities.button.button.pushed_3x({
        state_change = true }))
    }
  }
)

test.register_coroutine_test(
    "infoChanged() should send the SET command for Configuation value",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed(
          {
              preferences = {
                restoreState = 0,
                ch1OperatingMode = 2,
                ch1ReactionToSwitch = 2,
                ch1TimeParameter = 500,
                ch1PulseTime = 50,
                ch2OperatingMode = 4,
                ch2ReactionToSwitch = 2,
                ch2TimeParameter = 600,
                ch2PulseTime = 90,
                switchType = 0,
                flashingReports = 1,
                s1ScenesSent = 2,
                s2ScenesSent = 3,
                ch1EnergyReports = 500,
                ch2EnergyReports = 1000,
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
              Configuration:Set({parameter_number=15, size=1, configuration_value=4})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=16, size=1, configuration_value=2})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=17, size=2, configuration_value=600})
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Configuration:Set({parameter_number=18, size=1, configuration_value=90})
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
              Configuration:Set({parameter_number=57, size=2, configuration_value=1000})
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
