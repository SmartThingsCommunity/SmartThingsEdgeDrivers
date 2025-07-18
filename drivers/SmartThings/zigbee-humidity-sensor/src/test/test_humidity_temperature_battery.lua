-- Copyright 2025 SmartThings
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
local base64 = require "st.base64"
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local PowerConfiguration = clusters.PowerConfiguration


local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("humidity-temp-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "",
          model = "",
          server_clusters = { 0x0001, 0x0402, 0x0405 }
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Temperature report should be handled (C)",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C"}))
    }
  }
)

test.register_message_test(
  "Minimum & Maximum Temperature report should be handled (C)",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MinMeasuredValue:build_test_attr_report(mock_device, 2000)
      }
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MaxMeasuredValue:build_test_attr_report(mock_device, 3000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = 20.00, maximum = 30.00 }, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Humidity report should be handled",
  {
     {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 7900)
        }
     },
     {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 79 }))
     }
  }
)

test.register_coroutine_test(
    "Configure should configure all necessary attributes",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure"})
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         RelativeHumidity.attributes.MeasuredValue:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         RelativeHumidity.attributes.MeasuredValue:configure_reporting(mock_device, 30, 3600, 100)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, RelativeHumidity.ID)
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
                                         zigbee_test_utils.build_bind_request(mock_device,  zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device, 30, 21600, 1)
                                       })
                                       test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device) })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Handle tempOffset/humidityOffset preference infochanged",
    function()
      local updates = {
        preferences = {  --offsets doesn't effect to the output value in this TC
          tempOffset = -5,
          humidityOffset = -5
        }
      }
      test.socket.environment_update:__queue_receive({ "zigbee", { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500)
        }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" })))
      test.wait_for_events()
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 7900)
        }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 79 })))
    end
)

test.run_registered_tests()
