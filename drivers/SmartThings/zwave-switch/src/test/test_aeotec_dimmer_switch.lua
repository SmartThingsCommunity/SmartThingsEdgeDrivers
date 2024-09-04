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
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local constants = require "st.zwave.constants"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"

local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version=2 })
local SwitchMultilevel = (require "st.zwave.CommandClass.SwitchMultilevel")({ version=4 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version=3 })

local Configuration = (require "st.zwave.CommandClass.Configuration")({ version=4 })


local aeotec_dimmer_endpoints = {
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
  profile = t_utils.get_profile_definition("metering-dimmer.yml"),
  zwave_endpoints = aeotec_dimmer_endpoints,
  zwave_manufacturer_id = 0x0086,
  zwave_product_type = 0x0003,
  zwave_product_id = 0x0063
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Device should be configured",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({ parameter_number=80, size=1, configuration_value=2 })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({ parameter_number=101, size=4, configuration_value=12 })
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
      mock_device,
      Configuration:Set({ parameter_number=111, size=4, configuration_value=300 })
    ))
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Device should be polled with refresh right after inclusion",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_device.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch Binary report ON_ENABLE should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({ current_value = SwitchBinary.value.ON_ENABLE })
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
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Switch Binary report OFF_DISABLE should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchBinary:Report({ current_value = SwitchBinary.value.OFF_DISABLE })
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
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Z-Wave SwitchMultilevel reports with value-off should evoke Switch capability off events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = SwitchMultilevel.value.OFF_DISABLE,
            duration = 0
          })
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
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    }
  }
)

test.register_message_test(
  "Z-Wave SwitchMultilevel reports with non-zero values should evoke Switch and Switch Level capability events",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          SwitchMultilevel:Report({
            target_value = 0,
            current_value = 5,
            duration = 0
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switchLevel.level(5))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get({ scale = Meter.scale.electric_meter.WATTS })
      )
    }
  }
)

test.register_message_test(
  "Power meter report should be handled by main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(Meter:Report(
        {
          scale = Meter.scale.electric_meter.WATTS,
          meter_value = 55
        })
      )}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 55, unit = "W" }))
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

test.register_coroutine_test(
  "Switch capability on command should evoke the correct Z-Wave SETs and GETs with dest_channel 0",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} }
    })
    mock_device:expect_native_cmd_handler_registration("switch", "on")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Set({
          value = 0xFF,
          duration = "default"
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {}
        })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_device.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.ON_ENABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {}
        }
      )
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.on())
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
            dst_channels={}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dest_channel 0",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "main", command = "off", args = {} }
    })
    mock_device:expect_native_cmd_handler_registration("switch", "off")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Set({
          value = 0x00,
          duration = "default"
        },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 0,
            dst_channels = {}
          })
      )
    )

    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_device.id,
      SwitchBinary:Report(
        {
          current_value = SwitchBinary.value.OFF_DISABLE
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = {}
        }
      )
    })

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.off())
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
            dst_channels = {}
          }
        )
      )
    )
  end
)

test.register_coroutine_test(
  "SwitchLevel capability setLevel commands should evoke the correct Z-Wave SETs and GETs",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switchLevel", command = "setLevel", args = { 50 } }
    })
    mock_device:expect_native_cmd_handler_registration("switchLevel", "setLevel")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Set({
          value = 50,
          duration = constants.DEFAULT_DIMMING_DURATION
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        SwitchMultilevel:Get({})
      )
    )
  end
)

test.run_registered_tests()
