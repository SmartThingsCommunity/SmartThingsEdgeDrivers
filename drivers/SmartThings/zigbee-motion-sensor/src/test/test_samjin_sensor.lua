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
local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion-temp-battery.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Samjin",
          model = "motion",
          server_clusters = {0x0001, 0x0020, 0x0402, 0x0500}
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
  function()
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 600, 100)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 600, 100)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, TemperatureMeasurement.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.IASCIEAddress:write(mock_device, zigbee_test_utils.mock_hub_eui)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.server.commands.ZoneEnrollResponse(mock_device, IasEnrollResponseCode.SUCCESS, 0x00)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:read(mock_device)
    })
    -- test.socket.zigbee:__expect_send({
    --   mock_device.id,
    --   IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 30, 300, 0)
    -- })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 0xFFFF, 0x0000, 0)
    })
    -- test.socket.zigbee:__expect_send({
    --   mock_device.id,
    --   zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
    -- })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Battery reports test cases",
  function()
    local battery_test_map = {
      ["Samjin"] = {
        [200] = 100,
        [162] = 72,
        [133] = 50,
        [90] = 18,
        [67] = 0,
        [23] = 0
      }
    }

    for raw_report, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, raw_report) })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.run_registered_tests()
