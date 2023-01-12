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
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 1 })
local ThermostatOperatingState = (require "st.zwave.CommandClass.ThermostatOperatingState")({ version = 1 })
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({ version = 3 })
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
    zwave_endpoints = thermostat_endpoints
  }
)
local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local refresh_commands = {
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
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.TEMPERATURE})
    )
  },
  {
    channel = "zwave",
    direction = "send",
    message = zw_test_utilities.zwave_test_build_send_command(
      mock_device,
      SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY})
    )
  },
  {
    channel = "zwave",
    direction = "send",
    message = zw_test_utilities.zwave_test_build_send_command(
      mock_device,
      ThermostatSetpoint:Get({setpoint_type = 1})
    )
  },
  {
    channel = "zwave",
    direction = "send",
    message = zw_test_utilities.zwave_test_build_send_command(
      mock_device,
      ThermostatSetpoint:Get({setpoint_type = 2})
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
}

test.register_message_test(
  "Added lifecycle event should be handled",
  {
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
        ThermostatMode:SupportedGet({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatFanMode:SupportedGet({})
      )
    },
    table.unpack(refresh_commands)
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Refresh Capability Command should refresh Thermostat device",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "refresh", command = "refresh", args = {} }
      }
    },
    table.unpack(refresh_commands)
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Battery report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(99))
    }
  }
)

test.register_message_test(
  "Low battery report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utilities.zwave_test_build_receive_command(Battery:Report({ battery_level = 0xFF })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(1))
    }
  }
)

test.register_message_test(
  "Supported thermostat mode reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:SupportedReport({
                                                                                                      off = true,
                                                                                                      heat = true,
                                                                                                      cool = true,
                                                                                                      auto = true
                                                                                                    })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({ "off", "heat", "cool", "auto" }, {visibility={displayed=false}}))
    }
  }
)

test.register_message_test(
  "Supported thermostat fan mode reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatFanMode:SupportedReport({
                                                                                                          auto = true,
                                                                                                          low = true,
                                                                                                          circulation = true
                                                                                                        })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.supportedThermostatFanModes({ "on", "auto", "circulate" }, {visibility={displayed=false}}))
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
                  zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
                                                                                                sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                                                                                                scale = 0,
                                                                                                sensor_value = 21.5 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Humidity reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(SensorMultilevel:Report({
                                                                                                sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
                                                                                                scale = 0,
                                                                                                sensor_value = 21.5 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 22 }))
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
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatMode:Report({ mode = ThermostatMode.mode.HEAT })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode({ value = "heat" }))
    }
  }
)

test.register_message_test(
  "Thermostat fan mode reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatFanMode:Report({ fan_mode = ThermostatFanMode.fan_mode.CIRCULATION })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatFanMode.thermostatFanMode({ value = "circulate" }))
    }
  }
)

test.register_message_test(
  "Heating setpoint reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
                                                                                                  setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
                                                                                                  scale = 0,
                                                                                                  value = 21.5 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 21.5, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Cooling setpoint reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  zw_test_utilities.zwave_test_build_receive_command(ThermostatSetpoint:Report({
                                                                                                  setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
                                                                                                  scale = 1,
                                                                                                  value = 68 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 68, unit = 'F' }))
    }
  }
)

test.register_message_test(
  "Thermostat operating state reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        zw_test_utilities.zwave_test_build_receive_command(
            ThermostatOperatingState:Report(
                {
                  operating_state = ThermostatOperatingState.operating_state.HEATING
                }
            )
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState.heating())
    }
  }
)

test.register_coroutine_test(
  "Setting the thermostat fan mode should generate the appropriate commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatFanMode", command = "setThermostatFanMode", args = { "auto" } } })
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatFanMode:Set({
                                    fan_mode = ThermostatFanMode.fan_mode.AUTO_LOW
                                  })
        )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatFanMode:Get({})
        )
    )
  end
)

test.register_coroutine_test(
  "Setting the thermostat fan mode to circulate should generate the appropriate commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatFanMode", command = "setThermostatFanMode", args = { "circulate" } } })
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatFanMode:Set({
                                    fan_mode = ThermostatFanMode.fan_mode.CIRCULATION
                                  })
        )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatFanMode:Get({})
        )
    )
  end
)

test.register_coroutine_test(
  "Setting the thermostat fan mode to auto should generate the appropriate commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatFanMode", command = "fanAuto", args = {} } })
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatFanMode:Set({
                                    fan_mode = ThermostatFanMode.fan_mode.AUTO
                                  })
        )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatFanMode:Get({})
        )
    )
  end
)

test.register_coroutine_test(
  "Setting the thermostat mode should generate the appropriate commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatMode", command = "setThermostatMode", args = { "heat" } } })
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatMode:Set({
                                  mode = ThermostatMode.mode.HEAT
                                })
        )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
        zw_test_utilities.zwave_test_build_send_command(
            mock_device,
            ThermostatMode:Get({})
        )
    )
  end
)

test.register_coroutine_test(
  "Setting the thermostat mode to auto should generate the appropriate commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatMode", command = "auto", args = {} } })
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatMode:Set({
                            mode = ThermostatMode.mode.AUTO
                          })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatMode:Get({})
      )
    )
  end
)

test.register_coroutine_test(
  "Setting the heating setpoint should generate the appropriate commands",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { 21.5 } } })
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Set({
                                setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
                                value = 21.5
                              })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({
                                setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1
                              })
      )
    )
  end
)

test.register_coroutine_test(
  "Setting the cooling setpoint should generate the appropriate commands if the device has reported Fahrenheit previously",
  function()
    -- receiving a report in fahrenheit should make subsequent sets also be sent in fahrenheit
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        zw_test_utilities.zwave_test_build_receive_command(
          ThermostatSetpoint:Report(
            {
              setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
              scale = 1,
              value = 68
            })
        )

      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 68, unit = "F" })
      )
    )
    test.wait_for_events()

    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatCoolingSetpoint", command = "setCoolingSetpoint", args = { 20 } } })
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          ThermostatSetpoint:Set({
                                  setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
                                  scale = 1,
                                  value = 68
                                })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
          mock_device,
          ThermostatSetpoint:Get({
                                  setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1
                                })
      )
    )
  end
)

test.register_coroutine_test(
  "Setting the cooling setpoint should generate the appropriate commands if the device has reported Fahrenheit previously",
  function()
    -- receiving a report in fahrenheit should make subsequent sets also be sent in fahrenheit
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        zw_test_utilities.zwave_test_build_receive_command(
          ThermostatSetpoint:Report(
            {
              setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
              scale = 1,
              value = 68
            })
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 68, unit = "F" })
      )
    )
    test.wait_for_events()

    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "thermostatCoolingSetpoint", command = "setCoolingSetpoint", args = { 78 } } })
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Set({
                                setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
                                scale = 1,
                                value = 78
                              })
      )
    )
    test.wait_for_events()

    test.mock_time.advance_time(1)
    test.socket.zwave:__expect_send(
      zw_test_utilities.zwave_test_build_send_command(
        mock_device,
        ThermostatSetpoint:Get({
                                  setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1
                                })
      )
    )
  end
)

test.run_registered_tests()
