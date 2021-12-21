-- Copyright 2021 SmartThings
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
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })

-- supported command classes
local double_switch_endpoints = {
  {
    command_classes = {
      {value = zw.METER},
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY}
    },
    command_classes = {
      {value = zw.METER},
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("fibaro-walli-double-switch.yml"),
    zwave_endpoints = double_switch_endpoints,
    zwave_manufacturer_id = 0x010F,
    zwave_product_type = 0x1B01,
    zwave_product_id = 0x1000
})

local function  test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by main component",
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
              target_value = SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 1,
              dst_channels = {0}
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
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by main component",
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
              target_value=SwitchBinary.value.OFF_DISABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 1,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
    }
  }
)

test.register_message_test(
  "Power meter report should be handled by main component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 55
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 1,
          dst_channels= {0}
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  capabilities.powerMeter.power({ value = 55, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Energy meter report should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5
        })
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
  "Switch Binary report ON_ENABLE should be handled by switch1 component",
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
              target_value = SwitchBinary.value.ON_ENABLE
            },
            {
              encap = zw.ENCAP.AUTO,
              src_channel = 2,
              dst_channels = {0}
            }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1",  capabilities.switch.switch.on())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    }
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by switch1 component",
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
            target_value=SwitchBinary.value.OFF_DISABLE
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 2,
            dst_channels = {0}
          }
          )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1",  capabilities.switch.switch.off())
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    }
  }
)

test.register_message_test(
  "Power meter report should be handled by switch1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 55
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 2,
          dst_channels= {0}
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1",  capabilities.powerMeter.power({ value = 55, unit = "W" }))
    }
  }
)

test.register_message_test(
  "Energy meter report should be handled by switch1 component",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "init" }
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.KILOWATT_HOURS,
          meter_value = 5
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 2,
          dst_channels= {0}
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("switch1",  capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
    }
  }
)

test.register_coroutine_test(
  "Switch capability on command should evoke the correct Z-Wave SETs and GETs with dest_channel 1",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")
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

    test.socket.zwave:__queue_receive({
      mock_device.id,
      SwitchBinary:Report(
        {
          target_value = SwitchBinary.value.ON_ENABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {1}
        }
      )
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",  capabilities.switch.switch.on())
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dest_channel 1",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")
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

    test.socket.zwave:__queue_receive({
      mock_device.id,
      SwitchBinary:Report(
        {
          target_value = SwitchBinary.value.OFF_DISABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {1}
        }
      )
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",  capabilities.switch.switch.off())
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability on commands should evoke the correct Z-Wave SETs and GETs with dest_channel 1",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")
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

    test.socket.zwave:__queue_receive({
      mock_device.id,
      SwitchBinary:Report(
        {
          target_value = SwitchBinary.value.ON_ENABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 1,
          dst_channels = {0}
        }
      )
    })

    test.socket.capability:__expect_send(
            mock_device:generate_test_message("main",  capabilities.switch.switch.on())
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={1}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off commands should evoke the correct Z-Wave SETs and GETs with dest_channel 2",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")
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

    test.socket.zwave:__queue_receive({
      mock_device.id,
      SwitchBinary:Report(
        {
          target_value = SwitchBinary.value.OFF_DISABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 2,
          dst_channels = {0}
        }
      )
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("switch1",  capabilities.switch.switch.off())
    )

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {
            scale = Meter.scale.electric_meter.WATTS
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels={2}
          }
        )
      )
    )
  end
)

test.run_registered_tests()
