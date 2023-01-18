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
local clusters = require "st.zigbee.zcl.clusters"
local Thermostat = clusters.Thermostat
local ThermostatUserInterfaceConfiguration = clusters.ThermostatUserInterfaceConfiguration
local RelativeHumidity = clusters.RelativeHumidity
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"

local zigbee_thermostat_profile = {
  components = {
    main = {
      capabilities = {
        [capabilities.thermostatHeatingSetpoint.ID] = { id = capabilities.thermostatHeatingSetpoint.ID },
        [capabilities.thermostatOperatingState.ID] = { id = capabilities.thermostatOperatingState.ID },
        [capabilities.temperatureMeasurement.ID] = { id = capabilities.temperatureMeasurement.ID },
        [capabilities.temperatureAlarm.ID] = { id = capabilities.temperatureAlarm.ID },
        [capabilities.relativeHumidityMeasurement.ID] = { id = capabilities.relativeHumidityMeasurement.ID },
        [capabilities.refresh.ID] = { id = capabilities.refresh.ID },
      },
      id = "main"
    }
  }
}

local mock_device = test.mock_device.build_test_zigbee_device({ profile = zigbee_thermostat_profile, zigbee_endpoints ={ [1] = {id = 1, manufacturer = "Stelpro", model = "SORB", server_clusters = {0x0201, 0x0204, 0x0405}} } })
local mock_device_maestro = test.mock_device.build_test_zigbee_device({ profile = zigbee_thermostat_profile, zigbee_endpoints ={ [1] = {id = 1, manufacturer = "Stelpro", model = "MaestroStat", server_clusters = {0x0201, 0x0204, 0x0405}} } })

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_maestro)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Temperature reports using the thermostat cluster should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x073A) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 18.5, unit = "C" }))
      }
    }
)

test.register_message_test(
    "Temperature reports Freeze using thermostat should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x7FFD) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 0, unit = "C" }))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
      }
    }
)

test.register_message_test(
    "Temperature reports Heat using thermostat should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x7FFF) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 50, unit = "C" }))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
      }
    }
)

test.register_coroutine_test(
    "Emitting cleared Temperature alert",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x7FFF)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 50, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
      )
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x073A)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 18.5, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
      )
    end
)

test.register_coroutine_test(
    "Emitting cleared Temperature alert with early freeze",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x0000)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 0.0, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
      )
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x073A)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 18.5, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
      )
    end
)

test.register_coroutine_test(
    "Early freezing event should be handled",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x0000)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 0.0, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
      )
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Local Temperature negative handler",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, -1)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value =-0.01, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
      )
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "Early heat event should be handled",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")

      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 0x1388)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 50.0, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.heat())
      )
      test.wait_for_events()
    end
)

test.register_message_test(
    "PIHeatingDemand reports using the thermostat cluster should be handled - Idle",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.PIHeatingDemand:build_test_attr_report(mock_device, 8) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState("idle"))
      }
    }
)

test.register_message_test(
    "PIHeatingDemand reports using the thermostat cluster should be handled - heating",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.PIHeatingDemand:build_test_attr_report(mock_device, 12) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState("heating"))
      }
    }
)

test.register_message_test(
    "OccupiedHeatSetPoint reports using the thermostat cluster should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 0x073A) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 18.5, unit = "C" }))
      }
    }
)

test.register_message_test(
    "MeasuredValue reports using the RelativeHumidity cluster should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 0x09C4) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 25 }))
      }
    }
)

test.register_coroutine_test(
    "Refresh necessary attributes - SORB",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      -- test.socket.capability:__expect_send(
      --   mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
      -- )

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.LocalTemperature:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.PIHeatingDemand:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:read(mock_device)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        RelativeHumidity.attributes.MeasuredValue:read(mock_device)
      })
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes - SROB",
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
                                         Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 10, 60, 50)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 1, 600, 50)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.PIHeatingDemand:configure_reporting(mock_device, 1, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:configure_reporting(mock_device, 1, 0, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:configure_reporting(mock_device, 1, 0, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         RelativeHumidity.attributes.MeasuredValue:configure_reporting(mock_device, 10, 300, 1)
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Refresh necessary attributes - MaestroStat",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device_maestro.id, "added" })
      -- test.socket.capability:__expect_send(
      --   mock_device_maestro:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
      -- )
      test.socket.zigbee:__expect_send({
        mock_device_maestro.id,
        Thermostat.attributes.LocalTemperature:read(mock_device_maestro)
      })
      test.socket.zigbee:__expect_send({
        mock_device_maestro.id,
        Thermostat.attributes.PIHeatingDemand:read(mock_device_maestro)
      })
      test.socket.zigbee:__expect_send({
        mock_device_maestro.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device_maestro)
      })
      test.socket.zigbee:__expect_send({
        mock_device_maestro.id,
        ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:read(mock_device_maestro)
      })
      test.socket.zigbee:__expect_send({
        mock_device_maestro.id,
        ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:read(mock_device_maestro)
      })
      test.socket.zigbee:__expect_send({
        mock_device_maestro.id,
        RelativeHumidity.attributes.MeasuredValue:read(mock_device_maestro)
      })
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
    end
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes - MaestroStat",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_device_maestro.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device_maestro.id,
                                         zigbee_test_utils.build_bind_request(
                                             mock_device_maestro,
                                             zigbee_test_utils.mock_hub_eui,
                                             Thermostat.ID
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device_maestro.id,
                                         Thermostat.attributes.LocalTemperature:configure_reporting(mock_device_maestro, 10, 60, 50)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device_maestro.id,
                                         Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device_maestro, 1, 600, 50)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device_maestro.id,
                                         Thermostat.attributes.PIHeatingDemand:configure_reporting(mock_device_maestro, 1, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device_maestro.id,
                                         ThermostatUserInterfaceConfiguration.attributes.TemperatureDisplayMode:configure_reporting(mock_device_maestro, 1, 0, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device_maestro.id,
                                         ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:configure_reporting(mock_device_maestro, 1, 0, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device_maestro.id,
                                         RelativeHumidity.attributes.MeasuredValue:configure_reporting(mock_device_maestro, 10, 300, 1)
                                       })

      mock_device_maestro:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
  "Handle lock preference in infochanged",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = { lock = 1 } }))
    test.socket.zigbee:__expect_send({mock_device.id, ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:write(mock_device, 0x01)})
    test.wait_for_events()
    -- Event not to be handled by driver
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = { lock = 1 } }))
  end
)

test.register_coroutine_test(
  "Handle lock preference in infochanged",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({preferences = { lock = 0 } }))
    test.socket.zigbee:__expect_send({mock_device.id, ThermostatUserInterfaceConfiguration.attributes.KeypadLockout:write(mock_device, 0x00)})
    test.wait_for_events()
  end
)

test.run_registered_tests()
