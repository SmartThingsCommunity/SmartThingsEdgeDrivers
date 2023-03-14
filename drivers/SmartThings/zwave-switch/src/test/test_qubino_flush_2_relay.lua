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
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
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

local mock_base_device = test.mock_device.build_test_zwave_device({
  profile = parent_profile,
  zwave_endpoints = qubino_flush_2_relay_endpoints,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0051
})

local mock_parent_device = test.mock_device.build_test_zwave_device({
  profile = parent_profile,
  zwave_endpoints = qubino_flush_2_relay_endpoints,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0051
})

local mock_child_2_device = test.mock_device.build_test_child_device({
  profile = child_relay_profile,
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local mock_child_3_device = test.mock_device.build_test_child_device({
  profile = child_temperature_profile,
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%02X", 3)
})

local function test_init()
  test.mock_device.add_test_device(mock_base_device)
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_child_2_device)
  test.mock_device.add_test_device(mock_child_3_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Refresh should evoke correct GETs for endpoint matching the device (parent, ep=1)",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_parent_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = { } }
      })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({}, { dst_channels = { 1 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get(
              { scale = Meter.scale.electric_meter.WATTS },
              { dst_channels = { 1 } }
          )
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get(
              { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
              { dst_channels = { 1 } }
          )
      ))
    end
)

test.register_coroutine_test(
    "Refresh should evoke correct GETs for endpoint matching the device (child2, ep=2)",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_child_2_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = { } }
      })
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({}, { dst_channels = { 2 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get(
              { scale = Meter.scale.electric_meter.WATTS },
              { dst_channels = { 2 } }
          )
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get(
              { scale = Meter.scale.electric_meter.KILOWATT_HOURS },
              { dst_channels = { 2 } }
          )
      ))
    end
)

test.register_coroutine_test(
    "Refresh should evoke correct GETs for endpoint matching the device (child3, ep=3)",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_child_3_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = { } }
      })
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
    "Switch Binary report ON_ENABLE from endpoint 1 should be handled by parent device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  { value = SwitchBinary.value.ON_ENABLE },
                  { src_channel = 1 }
              )
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
    "Switch Binary report OFF_DISABLE from endpoint 1 should be handled by parent device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report(
                  { value = SwitchBinary.value.OFF_DISABLE },
                  { src_channel = 1 }
              )
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
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Switch Binary report OFF_DISABLE from endpoint 2 should be handled by child 2 device",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SwitchBinary:Report({ value = SwitchBinary.value.OFF_DISABLE }, { src_channel = 2 })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2_device:generate_test_message("main", capabilities.switch.switch.off())
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
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report(
                  { scale = Meter.scale.electric_meter.KILOWATT_HOURS, meter_value = 5 },
                  { src_channel = 1, dst_channels = { 0 } }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Energy meter report should be handled for endpoint: 2",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report(
                  { scale = Meter.scale.electric_meter.KILOWATT_HOURS, meter_value = 5 },
                  { src_channel = 2, dst_channels = { 0 } }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 5, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Power meter report should be handled for endpoint: 1",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report(
                  { scale = Meter.scale.electric_meter.WATTS, meter_value = 5.0 },
                  { src_channel = 1, dst_channels = { 0 } }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent_device:generate_test_message("main", capabilities.powerMeter.power({ value = 5, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Power meter report should be handled for endpoint: 2",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report(
                  { scale = Meter.scale.electric_meter.WATTS, meter_value = 5.0 },
                  { src_channel = 2, dst_channels = { 0 } }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2_device:generate_test_message("main", capabilities.powerMeter.power({ value = 5, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Celsius temperature reports should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent_device.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report(
                  { sensor_type = SensorMultilevel.sensor_type.TEMPERATURE, scale = 0, sensor_value = 21.5 },
                  { encap = zw.ENCAP.AUTO, src_channel = 3, dst_channels = { 0 } }
              )
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_3_device:generate_test_message(
            "main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' })
        )
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
        mock_parent_device.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent_device,
              SwitchBinary:Set(
                  { switch_value = SwitchBinary.value.ON_ENABLE },
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({}, { dst_channels = { 1 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 1 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 1 } })
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
        mock_parent_device.id,
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

      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({}, { dst_channels = { 1 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 1 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 1 } })
      ))
    end
)

test.register_coroutine_test(
    "Switch capability on command should evoke the correct Z-Wave SETs and GETs with dest_channel 2",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_child_2_device.id,
        { capability = "switch", component = "main", command = "on", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent_device,
              SwitchBinary:Set(
                  { switch_value = SwitchBinary.value.ON_ENABLE },
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
              )
          )
      )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({}, { dst_channels = { 2 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 2 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 2 } })
      ))
    end
)

test.register_coroutine_test(
    "Switch capability off command should evoke the correct Z-Wave SETs and GETs with dest_channel 2",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({
        mock_child_2_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_parent_device,
              SwitchBinary:Set(
                  { switch_value = SwitchBinary.value.OFF_DISABLE },
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 2 } }
              )
          )
      )

      test.wait_for_events()
      test.mock_time.advance_time(1)

      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          SwitchBinary:Get({}, { dst_channels = { 2 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.WATTS }, { dst_channels = { 2 } })
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_parent_device,
          Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 2 } })
      ))
    end
)

test.register_coroutine_test(
    "Added lifecycle event should create children for parent device",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_base_device.id, "added" })
      mock_base_device:expect_device_create(
          {
            type = "EDGE_CHILD",
            label = "Qubino Switch 2",
            profile = "metering-switch",
            parent_device_id = mock_base_device.id,
            parent_assigned_child_key = "02"
          }
      )
      mock_base_device:expect_device_create(
          {
            type = "EDGE_CHILD",
            label = "Qubino Temperature Sensor",
            profile = "child-temperature",
            parent_device_id = mock_base_device.id,
            parent_assigned_child_key = "03"
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_base_device,
              SwitchBinary:Get({},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_base_device,
              Meter:Get({scale = Meter.scale.electric_meter.WATTS},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_base_device,
              Meter:Get({scale = Meter.scale.electric_meter.KILOWATT_HOURS},
                  { encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = { 1 } }
              )
          )
      )
    end
)

test.run_registered_tests()
