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
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat
local FanControl = clusters.FanControl
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local base64 = require "st.base64"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("thermostat-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Zen Within",
          model = "Zen-01",
          server_clusters = {0x0001, 0x0201, 0x0402}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Battery Voltage test cases",
    function()
      local battery_test_map = {
          [63] = 100,
          [60] = 100,
          [50] = 62,
          [38] = 15,
          [34] = 0,
          [15] = 0
      }
      for voltage, batt_perc in pairs(battery_test_map) do
        test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
        test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
        test.wait_for_events()
      end
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

test.register_coroutine_test(
  "fan mode reports are handled with supported thermostat mode",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        FanControl.attributes.FanModeSequence:build_test_attr_report(mock_device, 4)
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
        FanControl.attributes.FanMode:build_test_attr_report(mock_device, 4)
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

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              Thermostat.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              FanControl.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              PowerConfiguration.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 5, 300, 50)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(mock_device, 5, 300, 50)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 5, 300, 50)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:configure_reporting(mock_device, 5, 300)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.ThermostatRunningState:configure_reporting(mock_device, 5, 300)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        FanControl.attributes.FanMode:configure_reporting(mock_device, 5, 300)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({ "off", "heat", "cool" }, { visibility = { displayed = false } }))
      )
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Combination test of mode and cooling(heating) setpoint",
    function()
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              Thermostat.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              FanControl.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        zigbee_test_utils.build_bind_request(mock_device,
                                              zigbee_test_utils.mock_hub_eui,
                                              PowerConfiguration.ID)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 5, 300, 50)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(mock_device, 5, 300, 50)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 5, 300, 50)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.SystemMode:configure_reporting(mock_device, 5, 300)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        Thermostat.attributes.ThermostatRunningState:configure_reporting(mock_device, 5, 300)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        FanControl.attributes.FanMode:configure_reporting(mock_device, 5, 300)
      })
      test.socket.zigbee:__expect_send({
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({ "off", "heat", "cool" }, { visibility = { displayed = false }}))
      )
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 3000)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 30.0, unit = "C" }))
      )
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device, 2500)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 25.0, unit = "C" }))
      )
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Check systemModes preference via infoChanged and other combination test",
    function()
      local updates = {
        preferences = {
          systemModes = 4 -- { "off", "auto", "heat", "cool" }
        }
      }
      test.timer.__create_and_queue_test_time_advance_timer(20, "oneshot")
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatMode.supportedThermostatModes({ "off", "auto", "heat", "cool" },{ visibility = { displayed = false }}))
      )
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, 0x03) -- SystemMode.COOL = 0x03
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.cool(
          {data={supportedThermostatModes={ "off", "auto", "heat", "cool" }},
          {visibility = { displayed = false }}}))
      )
      test.wait_for_events()
      test.mock_time.advance_time(10)
      test.wait_for_events()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2800)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 28.0, unit = "C" }))
      )
      test.wait_for_events()
      test.mock_time.advance_time(5)
      test.wait_for_events()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device, 2300)
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 23.0, unit = "C" }))
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "thermostatMode", command = "auto", args = {} , component = "main"}
        }
      )
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Thermostat.attributes.SystemMode:write(mock_device, 0x01) -- SystemMode.AUTO = 0x01
        }
      )
      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            Thermostat.attributes.SystemMode:read(mock_device)
          }
      )
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 27 } }
        }
      )
      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Thermostat.attributes.OccupiedCoolingSetpoint:write(mock_device, 2700)
        }
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 27 } }
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 28.0, unit = "C" }))
      )
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, 0x04) -- SystemMode.HEAT = 0x04
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.heat(
          {data={supportedThermostatModes={ "off", "auto", "heat", "cool" }}},
          {visibility = { displayed = false }}))
      )
      test.wait_for_events()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.capability:__queue_receive(
        {
          mock_device.id,
          { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 29 } }
        }
      )
      test.socket.zigbee:__expect_send(
        {
          mock_device.id,
          Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2900)
        }
      )
      test.mock_time.advance_time(2)
      test.wait_for_events()
    end
)

test.register_coroutine_test(
  "Setting a setpoint in Fahrenheit should be handled",
  function()
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        Thermostat.attributes.SystemMode:build_test_attr_report(mock_device, 0x04) -- SystemMode.HEAT = 0x04
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.heat())
    )
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 74 } }
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2333)
      }
    )
    test.mock_time.advance_time(2)
    test.wait_for_events()
  end
)

test.register_message_test(
    "Thermostat running mode reports are NOT handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, Thermostat.attributes.ThermostatRunningMode:build_test_attr_report(mock_device,
                                                                                                        3), }
      }
    }
)

test.run_registered_tests()
