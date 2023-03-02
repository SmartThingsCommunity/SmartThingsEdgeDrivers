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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("base-thermostat.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Fidure",
          model = "A1732R3",
          server_clusters = {0x0201, 0x0402}
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
                                         Thermostat.attributes.LocalTemperature:configure_reporting(mock_device, 20, 300, 20)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.OccupiedCoolingSetpoint:configure_reporting(mock_device, 10, 320, 50)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.OccupiedHeatingSetpoint:configure_reporting(mock_device, 10, 320, 50)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.SystemMode:configure_reporting(mock_device, 10, 305)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         Thermostat.attributes.ThermostatRunningState:configure_reporting(mock_device, 10, 325)
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
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
