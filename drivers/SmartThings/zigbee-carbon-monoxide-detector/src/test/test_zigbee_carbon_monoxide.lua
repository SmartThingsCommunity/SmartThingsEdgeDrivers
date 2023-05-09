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
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local IasEnrollResponseCode = require "st.zigbee.generated.zcl_clusters.IASZone.types.EnrollResponseCode"
local t_utils = require "integration_test.utils"


local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("carbonMonoxide-battery.yml") }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end
test.set_test_init_function(test_init)

test.register_message_test(
    "Reported carbonMonoxideDetector status should be handled: detected",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0001) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
      }
    }
)

test.register_message_test(
    "Reported carbonMonoxideDetector should be handled: clear",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0000) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification should be handled: detected",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0001, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.detected())
      }
    }
)

test.register_message_test(
    "ZoneStatusChangeNotification should be handled: clear",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0000, 0x00) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.carbonMonoxideDetector.carbonMonoxide.clear())
      }
    }
)

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device, 55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added"})
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.attributes.ZoneStatus:read(mock_device)
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
                                         zigbee_test_utils.build_bind_request(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui,
                                             PowerConfiguration.ID
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.attributes.IASCIEAddress:write(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.server.commands.ZoneEnrollResponse(
                                             mock_device,
                                             IasEnrollResponseCode.SUCCESS,
                                             0x00
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         IASZone.attributes.ZoneStatus:configure_reporting(
                                             mock_device,
                                             0,
                                             180,
                                             0
                                         )
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(
                                             mock_device,
                                             zigbee_test_utils.mock_hub_eui,
                                             IASZone.ID
                                         )
                                       })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)



test.run_registered_tests()
