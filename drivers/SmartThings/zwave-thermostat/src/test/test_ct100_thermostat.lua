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
local zw_test_utilities = require "integration_test.zwave_test_utils"
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({version = 2})
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })
local ThermostatOperatingState = (require "st.zwave.CommandClass.ThermostatOperatingState")({ version = 1 })
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({ version = 3 })
local MultiChannel = (require "st.zwave.CommandClass.MultiChannel")({ version = 2 })
local zw = require "st.zwave"
local t_utils = require "integration_test.utils"

-- supported comand classes
local thermostat_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = zw.THERMOSTAT_FAN_MODE},
      {value = zw.THERMOSTAT_MODE},
      {value = zw.THERMOSTAT_OPERATING_STATE},
      {value = zw.THERMOSTAT_SETPOINT},
      {value = zw.SENSOR_MULTILEVEL},
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
  {
    profile = t_utils.get_profile_definition("base-thermostat.yml"),
    zwave_endpoints = thermostat_endpoints,
    zwave_manufacturer_id = 0x0098,
    zwave_product_type = 0x6401,
    zwave_product_id = 0x0107
  }
)
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Refresh Capability Command should refresh Thermostat device",
  {
    {
      channel = "environment_update",
      direction = "receive",
      message = { "zwave", { hub_node_id = 0 } },
    },
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatFanMode:SupportedGet({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatMode:SupportedGet({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatFanMode:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatMode:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatOperatingState:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({},
        { dst_channels = {1}}
      )
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({},
        { dst_channels = {2}}
      )
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        Battery:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "Thermostat setpoint reports should be handled",
  function()
    mock_device:set_field("heating_setpoint_is_limited", true, {persist = true})

    -- receiving a report in fahrenheit should make subsequent sets also be sent in fahrenheit
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        zw_test_utilities.zwave_test_build_receive_command(
          ThermostatSetpoint:Report(
          {
            setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
            scale = 0,
            value = 68.0
          })
        )
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 68, unit = "C"})
    ))
  end
)

test.register_coroutine_test(
  "Thermostat setpoint reports should be handled",
  function()
    mock_device:set_field("cooling_setpoint_is_limited", true, {persist = true})

    -- receiving a report in fahrenheit should make subsequent sets also be sent in fahrenheit
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        zw_test_utilities.zwave_test_build_receive_command(
          ThermostatSetpoint:Report(
          {
            setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
            scale = 0,
            value = 68.0
          })
        )
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 68, unit = "C"})
    ))
  end
)

test.register_coroutine_test(
  "Encapsulated humidity reports should be parsed correctly",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      zw_test_utilities.zwave_test_build_receive_command(
        SensorMultilevel:Report(
          {
            sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
            sensor_value = 45
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 2,
            dst_channels = {0}
          }
        )
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.relativeHumidityMeasurement.humidity({value = 45})
    ))
  end
)

test.register_message_test(
  "Thermostat mode reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.HEAT })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "heat" }))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatOperatingState:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1})
      )
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
                  setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
                  scale = 0,
                  precision = 0,
                  value = 25 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25, unit = "C" }))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1})
      )
    }
  }
)

test.register_message_test(
  "Thermostat mode reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.COOL })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "cool" }))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatOperatingState:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1})
      )
    },
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
                  setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
                  scale = 0,
                  precision = 0,
                  value = 25 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 25, unit = "C" }))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1})
      )
    }
  }
)

test.register_coroutine_test(
  "Setting cooling setpoint should be handled",
  function()

    test.timer.__create_and_queue_test_time_advance_timer(.5, "oneshot")
    mock_device:set_field("temperature_scale", 0, {persist = true})

    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 25 } } })

    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = 0,
          precision = 0,
          value = 25
        })
      )
    )
    test.wait_for_events()
    test.mock_time.advance_time(.5)
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1})
      )
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        zw_test_utilities.zwave_test_build_receive_command(
          ThermostatSetpoint:Report(
          {
            setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
            scale = 0,
            value = 25.0
          })
        )
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatCoolingSetpoint.coolingSetpoint({value = 25, unit = "C"})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({},{
          dst_channels={1}
        })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatOperatingState:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Setting heating setpoint should be handled",
  function()
    mock_device:set_field("_temperature_scale", 1, {persist = true})
    test.timer.__create_and_queue_test_time_advance_timer(.5, "oneshot")

    test.socket.capability:__queue_receive({ mock_device.id, {
      capability = "thermostatHeatingSetpoint",
      component = "main",
      command = "setHeatingSetpoint",
      args = { 92 }
    } })
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          ThermostatSetpoint:Set({
            setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
            scale = 1,
            precision = 0,
            value = 92
          })
      )
    )

    test.wait_for_events()
    test.mock_time.advance_time(.5)
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1})
      )
    )
    test.wait_for_events()
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        zw_test_utilities.zwave_test_build_receive_command(
          ThermostatSetpoint:Report(
          {
            setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
            scale = 1,
            value = 92
          })
        )
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 92, unit = "F"})
    ))
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        SensorMultilevel:Get({},{
          dst_channels={1}
        })
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatOperatingState:Get({})
      )
    )
  end
)

-- these next two tests are based on actual messages from a real device
test.register_coroutine_test(
  "Incorrectly-encapsulated temperature reports should be handled gracefully",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      zw_test_utilities.zwave_test_build_receive_command(
        MultiChannel:MultiInstanceCmdEncap(
          {
            instance = 1,
            command_class = 0,
            command = zw.SENSOR_MULTILEVEL,
            parameter = "\x05\x01\x2A\x02\x58"
          }
        )
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.temperatureMeasurement.temperature({value = 60.0, unit = 'F'})
    ))
  end
)

test.register_coroutine_test(
  "Incorrectly-encapsulated humidity reports should be handled gracefully",
  function()
    test.socket.zwave:__queue_receive({
      mock_device.id,
      zw_test_utilities.zwave_test_build_receive_command(
        MultiChannel:MultiInstanceCmdEncap(
          {
            instance = 1,
            command_class = 0,
            command = zw.SENSOR_MULTILEVEL,
            parameter = "\x05\x05\x01\x30"
          }
        )
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.relativeHumidityMeasurement.humidity({value = 48})
    ))
  end
)

test.run_registered_tests()
