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
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version=2})
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version=5})
local Meter = (require "st.zwave.CommandClass.Meter")({version=3})
local Association = (require "st.zwave.CommandClass.Association")({version=2})
local MultiChannelAssociation = (require "st.zwave.CommandClass.MultiChannelAssociation")({version=3})

local qubino_temperature_sensor_with_power = {
  {
    command_classes = {
      {value = zw.METER},
      {value = zw.BASIC},
      {value = zw.SWITCH_BINARY},
      {value = zw.SENSOR_MULTILEVEL}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("qubino-flush1-relay-temperature.yml"),
  zwave_endpoints = qubino_temperature_sensor_with_power,
  zwave_manufacturer_id = 0x0159,
  zwave_product_type = 0x0002,
  zwave_product_id = 0x0052
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "After inclusion device should be added to propper association",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_device,
        MultiChannelAssociation:Remove({grouping_identifier = 1, node_ids = {}})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Association:Set({grouping_identifier = 1, node_ids = {}})
    ))
    test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Association:Set(
          {grouping_identifier = 2, node_ids = {}},
          {encap = zw.ENCAP.AUTO, src_channel = 0, dst_channels = {4}}
        )
    ))
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
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
          SwitchBinary:Report({current_value=SwitchBinary.value.ON_ENABLE})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
              mock_device,
              Meter:Get({scale = Meter.scale.electric_meter.WATTS})
      )
    }
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
          SwitchBinary:Report({current_value = SwitchBinary.value.OFF_DISABLE})
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Meter:Get(
          {scale = Meter.scale.electric_meter.WATTS})
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

test.register_message_test(
  "Celsius temperature reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
                    sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                    scale = 0,
                    sensor_value = 21.5
                  },{encap = zw.ENCAP.AUTO, src_channel = 4, dst_channels = {0}}))
                }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
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
        SwitchBinary:Set({
          target_value = SwitchBinary.value.ON_ENABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={}
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
    mock_device:expect_native_attr_handler_registration("switch", "switch")

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
        SwitchBinary:Set({
          target_value = SwitchBinary.value.OFF_DISABLE,
          duration = 0
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels={}
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
    mock_device:expect_native_attr_handler_registration("switch", "switch")

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
  "main should be deleted or created depending on temperature reports",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zwave:__set_channel_ordering("relaxed")

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = 0,
        sensor_value = -999
      },{encap = zw.ENCAP.AUTO, src_channel = 4, dst_channels = {0}}
      )
    })

    -- test.wait_for_events()
    -- assert(utils.table_size(mock_device.profile.components) == 1, "main should be deleted after receiving wrong temperature value")

    test.wait_for_events()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = 0,
        sensor_value = 21.5
      },{encap = zw.ENCAP.AUTO, src_channel = 4, dst_channels = {0}}
      )
    })

    -- test.wait_for_events()
    -- assert(utils.table_size(mock_device.profile.components) == 2, "main should be created after receiving correct temperature value")

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    )
  end
)

test.run_registered_tests()
