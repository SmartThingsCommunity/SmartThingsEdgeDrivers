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
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 1 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 4 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 7 })

local qubino_flush_2_relay_endpoints = {
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
      { value = zw.METER },
      { value = zw.SENSOR_MULTILEVEL }
    }
  },
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
      { value = zw.METER },
    }
  },
  {
    command_classes = {
      { value = zw.SWITCH_BINARY },
      { value = zw.METER },
    }
  },
  {
    command_classes = {
      { value = zw.SENSOR_MULTILEVEL }
    }
  }
}

local parent_profile = t_utils.get_profile_definition("qubino-flush2-relay.yml")
local child_relay_profile = t_utils.get_profile_definition("metering-switch.yml")
local child_temperature_profile = t_utils.get_profile_definition("child-temperature.yml")

local mock_parent_device = test.mock_device.build_test_zwave_device({
  profile = parent_profile,
  zwave_endpoints = qubino_flush_2_relay_endpoints,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0051
})

local mock_child_1_device = test.mock_device.build_test_child_device({
  profile = child_relay_profile,
  device_network_id = string.format("%s:%02X", mock_parent_device.device_network_id, 1),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 1)
})

local mock_child_2_device = test.mock_device.build_test_child_device({
  profile = child_relay_profile,
  device_network_id = string.format("%s:%02X", mock_parent_device.device_network_id, 2),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local mock_child_3_device = test.mock_device.build_test_child_device({
  profile = child_temperature_profile,
  device_network_id = string.format("%s:%02X", mock_parent_device.device_network_id, 3),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 3)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_child_1_device)
  test.mock_device.add_test_device(mock_child_2_device)
  test.mock_device.add_test_device(mock_child_3_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Refresh sends commands to all endpoints including base device",
    function()
      -- refresh commands for zwave devices do not have guaranteed ordering
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_parent_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = { } }
      })
      for i = 0, 2, 1 do
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            SwitchBinary:Get({}, { dst_channels = { i } })
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.WATTS },
                { dst_channels = { i } }
            )
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
                { dst_channels = { i } }
            )
        ))
      end
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SensorMultilevel:Get(
              { sensor_type = SensorMultilevel.sensor_type.TEMPERATURE },
              { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 3 } }
          )
      ))
    end
)

test.register_message_test(
    "Switch Binary report ON_ENABLE from endpoint 0 should be handled by parent device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({ value = SwitchBinary.value.ON_ENABLE })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.on())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Switch Binary report OFF_DISABLE from endpoint 0 should be handled by parent device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({ value = SwitchBinary.value.OFF_DISABLE })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.switch.switch.off())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Switch Binary report ON_ENABLE from endpoint 1 should be handled by child 1 device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({ value = SwitchBinary.value.ON_ENABLE }, { src_channel = 1 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_1_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            SwitchBinary:Get({}, { dst_channels = { 0 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 0 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 0 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Switch Binary report ON_ENABLE from endpoint 2 should be handled by child 2 device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({ value = SwitchBinary.value.ON_ENABLE }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2_device:generate_test_message("main", capabilities.switch.switch.on())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            SwitchBinary:Get({}, { dst_channels = { 0 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 0 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 0 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Energy meter report should be handled for endpoint: 1",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_parent_device.id, zw_test_utils.zwave_test_build_receive_command(
            Meter:Report({
              scale = Meter.scale.electric_meter.KILOWATT_HOURS,
              meter_value = 5
            }, {
              src_channel = 1,
              dst_channels = { 0 }
            })
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_1_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Energy meter report should be handled for endpoint: 2",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_parent_device.id, zw_test_utils.zwave_test_build_receive_command(
            Meter:Report({
              scale = Meter.scale.electric_meter.KILOWATT_HOURS,
              meter_value = 5
            }, {
              src_channel = 2,
              dst_channels = { 0 }
            })
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Energy meter report should be handled for endpoint: 0",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_parent_device.id, zw_test_utils.zwave_test_build_receive_command(
            Meter:Report({
              scale = Meter.scale.electric_meter.KILOWATT_HOURS,
              meter_value = 10
            }, {
              src_channel = 0,
              dst_channels = {}
            })
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 10, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Power meter report should be handled for endpoint: 1",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_parent_device.id, zw_test_utils.zwave_test_build_receive_command(
            Meter:Report({
              scale = Meter.scale.electric_meter.WATTS,
              meter_value = 5.0
            }, {
              src_channel = 1,
              dst_channels = { 0 }
            })
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_1_device:generate_test_message("main", capabilities.powerMeter.power({ value = 5, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Power meter report should be handled for endpoint: 2",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_parent_device.id, zw_test_utils.zwave_test_build_receive_command(
            Meter:Report({
              scale = Meter.scale.electric_meter.WATTS,
              meter_value = 5.0
            }, {
              src_channel = 2,
              dst_channels = { 0 }
            })
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2_device:generate_test_message("main", capabilities.powerMeter.power({ value = 5, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Power meter report should be handled for endpoint: 0",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_parent_device.id, zw_test_utils.zwave_test_build_receive_command(
            Meter:Report({
              scale = Meter.scale.electric_meter.WATTS,
              meter_value = 10.0
            }, {
              src_channel = 0,
              dst_channels = {}
            })
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.powerMeter.power({ value = 10, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Celsius temperature reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_parent_device.id, zw_test_utils.zwave_test_build_receive_command(
            SensorMultilevel:Report({
              sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
              scale = 0,
              sensor_value = 21.5
            }, {
              encap = zw.ENCAP.AUTO,
              src_channel = 3,
              dst_channels = { 0 }
            })
        ) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
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
        mock_parent_device.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })

      for i = 0, 2 do
        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_parent_device,
                SwitchBinary:Set(
                    { switch_value = SwitchBinary.value.ON_ENABLE },
                    { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { i } }
                )
            )
        )
      end

      test.wait_for_events()
      test.mock_time.advance_time(1)

      for i = 0, 2, 1 do
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            SwitchBinary:Get({}, { dst_channels = { i } })
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.WATTS },
                { dst_channels = { i } }
            )
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
                { dst_channels = { i } }
            )
        ))
      end
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SensorMultilevel:Get(
              { sensor_type = SensorMultilevel.sensor_type.TEMPERATURE },
              { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 3 } }
          )
      ))
    end
)

test.register_coroutine_test(
    "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dest_channel 0",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_parent_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })

      for i = 0, 2 do
        test.socket.zwave:__expect_send(
            zw_test_utils.zwave_test_build_send_command(
                mock_parent_device,
                SwitchBinary:Set(
                    { switch_value = SwitchBinary.value.OFF_DISABLE },
                    { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { i } }
                )
            )
        )
      end

      test.wait_for_events()
      test.mock_time.advance_time(1)

      for i = 0, 2, 1 do
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            SwitchBinary:Get({}, { dst_channels = { i } })
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.WATTS },
                { dst_channels = { i } }
            )
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
                { dst_channels = { i } }
            )
        ))
      end
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SensorMultilevel:Get(
              { sensor_type = SensorMultilevel.sensor_type.TEMPERATURE },
              { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 3 } }
          )
      ))
    end
)

test.register_coroutine_test(
    "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dest_channel 1",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_child_1_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent_device,
              SwitchBinary:Set(
                  { switch_value = SwitchBinary.value.OFF_DISABLE },
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      for i = 0, 2, 1 do
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            SwitchBinary:Get({}, { dst_channels = { i } })
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.WATTS },
                { dst_channels = { i } }
            )
        ))
        test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
            mock_parent_device,
            Meter:Get(
                { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
                { dst_channels = { i } }
            )
        ))
      end
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SensorMultilevel:Get(
              { sensor_type = SensorMultilevel.sensor_type.TEMPERATURE },
              { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 3 } }
          )
      ))
    end
)

test.run_registered_tests()
