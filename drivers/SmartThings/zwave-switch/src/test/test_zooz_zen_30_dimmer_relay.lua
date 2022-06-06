local zw = require "st.zwave"
local test = require "integration_test"
local zw_test_utils = require "integration_test.zwave_test_utils"
local test_utils = require "integration_test.utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version = 4 })
local CentralScene = (require "st.zwave.CommandClass.CentralScene")({version=1})
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"

local zooz_zen_30_dimmer_relay_endpoints = {
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.CENTRAL_SCENE }
    },
    command_classes = {
      { value = zw.SWITCH_BINARY }
    }
  }
}

local mock_zooz_zen_30_dimmer_relay = test.mock_device.build_test_zwave_device({
  profile = test_utils.get_profile_definition("zooz-zen-30-dimmer-relay.yml"),
  zwave_endpoints = zooz_zen_30_dimmer_relay_endpoints,
  zwave_manufacturer_id = 0x027A,
  zwave_product_type = 0xA000,
  zwave_product_id = 0xA008
})

local function test_init()
  test.mock_device.add_test_device(mock_zooz_zen_30_dimmer_relay)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Switch capability on command should evoke the correct Z-Wave SETs and GETs with dst_channel 0",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_zen_30_dimmer_relay.id,
      { capability = "switch", component = "main", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {0}
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {0}
          })
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dst_channel 0",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_zooz_zen_30_dimmer_relay.id,
      { capability = "switch", component = "main", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {0}
          })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {0}
          })
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs dst_channel 1",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_zen_30_dimmer_relay.id,
      { capability = "switch", component = "switch1", command = "on", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs dst_channel 1",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_zen_30_dimmer_relay.id,
      { capability = "switch", component = "switch1", command = "off", args = {} }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {1}
        }
        )
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchBinary:Get({},
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {1}
          })
      )
    )
  end
)

test.register_coroutine_test(
  "SwitchLevel capability setLevel commands should evoke the correct Z-Wave SETs and GETs",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({
      mock_zooz_zen_30_dimmer_relay.id,
      { capability = "switchLevel", component = "main", command = "setLevel", args = { 10 } }
    })
    test.socket.capability:__expect_send(
      mock_zooz_zen_30_dimmer_relay:generate_test_message(
        "main", capabilities.switch.switch.on()
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchMultilevel:Set({
          value = 10,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_zooz_zen_30_dimmer_relay,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.register_message_test(
  "Z-Wave SwitchMultilevel reports with non-zero values should evoke Switch and Switch Level capability events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            current_value = 0,
            target_value = 50,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.switchLevel.level(50))
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'up' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x01,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_1_TIME
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.up())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'down' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x02,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_1_TIME
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.down())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'pushed' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x03,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_1_TIME
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.pushed())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'up_2x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x01,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_2_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.up_2x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'down_2x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x02,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_2_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.down_2x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'pushed_2x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x03,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_2_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.pushed_2x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'up_3x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x01,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_3_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.up_3x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'down_3x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x02,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_3_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.down_3x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'pushed_3x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x03,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_3_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.pushed_3x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'up_4x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x01,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_4_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.up_4x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'down_4x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x02,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_4_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.down_4x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'pushed_4x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x03,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_4_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.pushed_4x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'up_5x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x01,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_5_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.up_5x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'down_5x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x02,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_5_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.down_5x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'pushed_5x' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x03,
              key_attributes = CentralScene.key_attributes.KEY_PRESSED_5_TIMES
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.pushed_5x())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'up_hold' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x01,
              key_attributes = CentralScene.key_attributes.KEY_HELD_DOWN
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.up_hold())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'down_hold' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x02,
              key_attributes = CentralScene.key_attributes.KEY_HELD_DOWN
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.down_hold())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'held' should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x03,
              key_attributes = CentralScene.key_attributes.KEY_HELD_DOWN
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_zooz_zen_30_dimmer_relay:generate_test_message("main", capabilities.button.button.held())
    }
  }
)

test.register_message_test(
  "Central Scene notification Button 'released' should not be handled, not supported by SmartThings",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_zooz_zen_30_dimmer_relay.id,
        zw_test_utils.zwave_test_build_receive_command(
          CentralScene:Notification(
            {
              scene_number = 0x03,
              key_attributes = 0x01
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send"
    }
  }
)

test.run_registered_tests()

