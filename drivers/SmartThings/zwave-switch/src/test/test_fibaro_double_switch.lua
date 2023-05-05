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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1, strict = true })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })

local ON = 0xFF
local OFF = 0x00

local sensor_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SWITCH_BINARY },
      { value = zw.SWITCH_MULTILEVEL },
      { value = zw.METER },
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  },
  {
    command_classes = {
      { value = zw.CENTRAL_SCENE }
    }
  }
}

local base_parent = test.mock_device.build_test_zwave_device({
  label = "Fibaro Double Switch",
  profile = t_utils.get_profile_definition("fibaro-double-switch.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x0203,
  zwave_product_id = 0x1000
})

local mock_parent = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("fibaro-double-switch.yml"),
  zwave_endpoints = sensor_endpoints,
  zwave_manufacturer_id = 0x010F,
  zwave_product_type = 0x0203,
  zwave_product_id = 0x1000
})

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("metering-switch.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(base_parent)
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Switch Binary report ON_ENABLE should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.ON_ENABLE,
                    current_value = SwitchBinary.value.ON_ENABLE,
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 1,
                    dst_channels = { 0 }
                  }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS },
                {
                  encap = zw.ENCAP.AUTO,
                  src_channel = 0,
                  dst_channels = { 1 }
                })
        )
      }
    }
)

test.register_message_test(
    "Switch Binary report ON_ENABLE should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_child.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.ON_ENABLE,
                    current_value = SwitchBinary.value.ON_ENABLE
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 2,
                    dst_channels = { 0 }
                  }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS },
                {
                  encap = zw.ENCAP.AUTO,
                  src_channel = 0,
                  dst_channels = { 2 }
                })
        )
      }
    }
)
test.register_message_test(
    "Switch Binary report OFF_DISABLE should be handled by parent device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.OFF_DISABLE
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 1,
                    dst_channels = { 0 }
                  }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS },
                {
                  encap = zw.ENCAP.AUTO,
                  src_channel = 0,
                  dst_channels = { 1 }
                })
        )
      }
    }
)

test.register_message_test(
    "Switch Binary report OFF_DISABLE should be handled by child device",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = { mock_parent.id, "init" }
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  {
                    target_value = SwitchBinary.value.OFF_DISABLE
                  },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 2,
                    dst_channels = { 0 }
                  }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS },
                {
                  encap = zw.ENCAP.AUTO,
                  src_channel = 0,
                  dst_channels = { 2 }
                })
        )
      }
    }
)

test.register_coroutine_test(
    "Switch capability on commands should evoke the correct Z-Wave SETs and GETs on parent device",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Basic:Set({
                value = ON
              },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 1 }
                  })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({},
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 1 }
                  })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability on commands should evoke the correct Z-Wave SETs and GETs on child device",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Basic:Set({
                value = ON
              },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 2 }
                  })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({},
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 2 }
                  })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability off commands should evoke the correct Z-Wave SETs and GETs on parent device",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_parent.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Basic:Set({
                value = OFF
              },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 1 }
                  })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({},
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 1 }
                  })
          )
      )
    end
)

test.register_coroutine_test(
    "Switch capability off commands should evoke the correct Z-Wave SETs and GETs on child device",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive({
        mock_child.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Basic:Set({
                value = OFF
              },
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 2 }
                  })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              SwitchBinary:Get({},
                  {
                    encap = zw.ENCAP.AUTO,
                    src_channel = 0,
                    dst_channels = { 2 }
                  })
          )
      )
    end
)

test.register_coroutine_test(
    "infoChanged() should send the SET command for Configuation value",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive(mock_parent:generate_info_changed(
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
              mock_parent,
              Configuration:Set({ parameter_number = 9, size = 1, configuration_value = 0 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 10, size = 1, configuration_value = 2 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 11, size = 1, configuration_value = 2 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 12, size = 2, configuration_value = 500 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 13, size = 2, configuration_value = 50 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 15, size = 1, configuration_value = 4 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 16, size = 1, configuration_value = 2 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 17, size = 2, configuration_value = 600 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 18, size = 1, configuration_value = 90 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 20, size = 1, configuration_value = 0 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 21, size = 1, configuration_value = 1 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 28, size = 1, configuration_value = 2 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 29, size = 1, configuration_value = 3 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 53, size = 2, configuration_value = 500 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 57, size = 2, configuration_value = 1000 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 58, size = 2, configuration_value = 10 })
          )
      )

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent,
              Configuration:Set({ parameter_number = 59, size = 2, configuration_value = 600 })
          )
      )

    end
)

test.register_coroutine_test(
    "added lifecycle event should create children in parent device",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ base_parent.id, "added" })
      base_parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Fibaro Double Switch (CH2)",
        profile = "metering-switch",
        parent_device_id = base_parent.id,
        parent_assigned_child_key = "02"
      })
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              base_parent,
              SwitchBinary:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              base_parent,
              Basic:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              base_parent,
              Meter:Get(
                  { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              base_parent,
              Meter:Get(
                  { scale = Meter.scale.electric_meter.WATTS },
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
    end
)

test.run_registered_tests()
