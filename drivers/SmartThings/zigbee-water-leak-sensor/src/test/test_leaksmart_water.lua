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
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local ApplianceEventsAlerts = clusters.ApplianceEventsAlerts
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local IASZone = clusters.IASZone

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("water-temp-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "WAXMAN",
          model = "leakSMART Water Sensor V2",
          server_clusters = {0x0001, 0x0402, 0x0500, 0x0B02}
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
    "Reported water should be handled: wet",
    function()
      local alert_command = ApplianceEventsAlerts.client.commands.AlertsNotification.build_test_rx(mock_device, 0x01, {0x001181})
      test.socket.zigbee:__queue_receive({ mock_device.id, alert_command })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.waterSensor.water.wet()))
      end
)

test.register_coroutine_test(
    "Reported water should be handled: wet",
    function()
      local alert_command = ApplianceEventsAlerts.client.commands.AlertsNotification.build_test_rx(mock_device, 0x01, {0x000081})
      test.socket.zigbee:__queue_receive({ mock_device.id, alert_command })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.waterSensor.water.dry()))
      end
)

test.register_coroutine_test(
    "Reported water should be handled: wet",
    function()
      local alert_command = ApplianceEventsAlerts.client.commands.AlertsNotification.build_test_rx(mock_device, 0x01, {0x000581})
      test.socket.zigbee:__queue_receive({ mock_device.id, alert_command })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.waterSensor.water.dry()))
      end
)

test.register_coroutine_test(
    "Reported water should be handled: wet",
    function()
      local alert_command = ApplianceEventsAlerts.client.commands.AlertsNotification.build_test_rx(mock_device, 0x01, {0x001081})
      test.socket.zigbee:__queue_receive({ mock_device.id, alert_command })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.waterSensor.water.dry()))
      end
)

test.register_coroutine_test(
    "Reported water should be handled: wet",
    function()
      local alert_command = ApplianceEventsAlerts.client.commands.AlertsNotification.build_test_rx(mock_device, 0x01, {0x001281})
      test.socket.zigbee:__queue_receive({ mock_device.id, alert_command })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.waterSensor.water.dry()))
      end
)

test.register_coroutine_test(
    "Health check should check all relevant attributes",
    function()
      test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
      -- test.socket.capability:__expect_send(
      --   {
      --     mock_device.id,
      --     {
      --       capability_id = "waterSensor", component_id = "main",
      --       attribute_id = "water", state={value="dry"}
      --     }
      --   }
      -- )
    end,
    {
      test_init = function()
        test.mock_device.add_test_device(mock_device)
        test.timer.__create_and_queue_test_time_advance_timer(30, "interval", "health_check")
      end
    }
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
                                             ApplianceEventsAlerts.ID
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
                                         zigbee_test_utils.build_bind_request(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui,
                                             TemperatureMeasurement.ID
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                                             mock_device,
                                             30,
                                             300,
                                             16
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(
                                             mock_device,
                                             30,
                                             21600,
                                             1
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
                                      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
                                      })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.attributes.ZoneStatus:read(mock_device)
                                      })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
