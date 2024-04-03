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
local OccupancyAttribute = clusters.OccupancySensing.attributes.Occupancy
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion-temp-battery.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "frient A/S",
          model = "MOSZB-140",
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
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
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
      IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 30, 300, 0)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 300, 100):to_endpoint(0x26)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1):to_endpoint(0x23)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Added should refresh all necessary attributes",
  function()
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.attributes.ZoneStatus:read(mock_device)
    })
  end
)

test.register_coroutine_test(
  "Battery Voltage test cases",
  function()
    local battery_test_map = {
      ["frient A/S"] = {
        [32] = 100,
        [31] = 100,
        [29] = 86,
        [26] = 43,
        [24] = 14,
        [23] = 0,
        [15] = 0
      }
    }

    for voltage, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.register_message_test(
  "Reported motion should be handled: active",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OccupancyAttribute:build_test_attr_report(mock_device, 0x01) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    }
  }
)

test.register_message_test(
  "Reported motion should be handled: inactive",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, OccupancyAttribute:build_test_attr_report(mock_device, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    }
  }
)

test.run_registered_tests()
