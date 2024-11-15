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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat
local FanControl = clusters.FanControl
local TemperatureMeasurement = clusters.TemperatureMeasurement
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("thermostat-battery-powerSource.yml") }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Max battery voltage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device,
                                                                                                        65) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
      }
    }
)

test.register_message_test(
    "Min battery voltage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device,
                                                                                                        50) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
      }
    }
)

test.register_message_test(
    "Battery report of 0 should report two events",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 0)
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.mains())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
      }
    }
)

test.register_message_test(
    "Temperature reports using the thermostat cluster should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device,
                                                                                                  2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
      }
    }
)

test.register_message_test(
    "Temperature report should be handled (C) for the temperature cluster",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C"}))
      }
    }
)

test.register_message_test(
  "Minimum & Maximum Temperature report should be handled (C) for the temperature cluster",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, TemperatureMeasurement.attributes.MinMeasuredValue:build_test_attr_report(mock_device, 2000) }
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, TemperatureMeasurement.attributes.MaxMeasuredValue:build_test_attr_report(mock_device, 3000) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = 20.00, maximum = 30.00 }, unit = "C" }))
    }
  }
)

test.register_message_test(
    "Heating setpoint reports are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device,
                                                                                                         2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25.0, unit = "C" }))
      }
    }
)

test.register_message_test(
    "Cooling setpoint reports are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device,
                                                                                                         2500) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 25.0, unit = "C" }))
      }
    }
)

test.register_message_test(
    "Thermostat cooling setpoint bounds are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.MinCoolSetpointLimit:build_test_attr_report(mock_device,
                                                                                                        1000)}
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.MaxCoolSetpointLimit:build_test_attr_report(mock_device,
                                                                                                        3500)}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpointRange(
          {
            unit = 'C',
            value = {minimum = 10.0, maximum = 35.0}
          }
        ))
      }
    }
)

test.register_message_test(
    "Thermostat heating setpoint bounds are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.MinHeatSetpointLimit:build_test_attr_report(mock_device,
                                                                                                        1000)}
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.MaxHeatSetpointLimit:build_test_attr_report(mock_device,
                                                                                                        3500)}
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpointRange(
          {
            unit = 'C',
            value = {minimum = 10.0, maximum = 35.0}
          }
        ))
      }
    }
)

test.register_coroutine_test(
  "Supported thermostat modes reports are handled",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(mock_device, 04)
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.thermostatMode.supportedThermostatModes(
          { "off", "heat", "auto", "cool", "emergency heat" },
          { visibility = { displayed = false }}
        )
      )
    )
  end
)

test.register_coroutine_test(
  "Supported fan modes reports are handled",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        FanControl.attributes.FanModeSequence:build_test_attr_report(mock_device, 04)
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.thermostatFanMode.supportedThermostatFanModes(
          { "on", "auto" },
          { visibility = { displayed = false }}
        )
      )
    )
  end
)

test.register_message_test(
    "Operating state reports are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.ThermostatRunningState:build_test_attr_report(mock_device,
                                                                                                        2), }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState("cooling"))
      }
    }
)

test.register_coroutine_test(
  "Fan operating state reports are handled",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        FanControl.attributes.FanModeSequence:build_test_attr_report(mock_device, 04)
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.thermostatFanMode.supportedThermostatFanModes(
          { "on", "auto" },
          { visibility = { displayed = false }}
        )
      )
    )

    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        FanControl.attributes.FanMode:build_test_attr_report(mock_device, 04)
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
          capabilities.thermostatFanMode.thermostatFanMode.on(
          { data = {supportedThermostatFanModes = {"on", "auto"}}}
        )
      )
    )
  end
)

test.register_message_test(
    "Power source reports are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryAlarmState:build_test_attr_report(mock_device,
                                                                                                           0x40000000), }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerSource.powerSource.battery())
      }
    }
)

test.register_coroutine_test(
    "Setting thermostat heating setpoint should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 27 } }
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2700)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Setting thermostat cooling setpoint should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 27 } }
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 2700)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Setting thermostat cooling setpoint with a fahrenheit value should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 62.0 } }
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 1667)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Setting thermostat mode to auto should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatMode", command = "auto", args = {}, component = "main"}
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.SystemMode:write(mock_device, 1)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.SystemMode:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Setting thermostat mode to off should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatMode", command = "setThermostatMode", args = {"off"}, component = "main" }}
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.SystemMode:write(mock_device, 0)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.SystemMode:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Setting thermostat fan mode to auto should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatFanMode", command = "fanAuto", args = {}, component = "main"}
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            FanControl.attributes.FanMode:write(mock_device, 5)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            FanControl.attributes.FanMode:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Setting thermostat fan mode to on should generate correct zigbee messages",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_device.id,
            { capability = "thermostatFanMode", command = "setThermostatFanMode", args = {"on"}, component = "main" }
          }
      )
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            FanControl.attributes.FanMode:write(mock_device, 4)
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            FanControl.attributes.FanMode:read(mock_device)
          }
      )
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui,
                                             Thermostat.ID
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui,
                                             FanControl.ID
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui,
                                             PowerConfiguration.ID
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         PowerConfiguration.attributes.BatteryVoltage:configure_reporting(
                                             mock_device,
                                             30,
                                             21600,
                                             1
                                         )
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_message_test(
    "Driver should poll device at the inclusion",
    {
      {
        channel = "device_lifecycle",
        direction = "receive",
        message = {mock_device.id, "added"}
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          TemperatureMeasurement.attributes.MinMeasuredValue:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          TemperatureMeasurement.attributes.MaxMeasuredValue:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.ControlSequenceOfOperation:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.ThermostatRunningState:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.SystemMode:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MinHeatSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MaxHeatSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MinCoolSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MaxCoolSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          FanControl.attributes.FanModeSequence:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          FanControl.attributes.FanMode:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryAlarmState:read(mock_device)
        }
      },
    }
)

test.register_message_test(
    "Refresh should read all necessary attributes",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.OccupiedCoolingSetpoint:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.ControlSequenceOfOperation:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.ThermostatRunningState:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.SystemMode:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MinHeatSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MaxHeatSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MinCoolSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          Thermostat.attributes.MaxCoolSetpointLimit:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          FanControl.attributes.FanModeSequence:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          FanControl.attributes.FanMode:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          PowerConfiguration.attributes.BatteryAlarmState:read(mock_device)
        }
      },
    }
)

test.register_message_test(
    "Thermostat running mode reports are handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.ThermostatRunningMode:build_test_attr_report(mock_device,
                                                                                                        3), }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode("cool"))
      }
    }
)

test.run_registered_tests()
