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

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local HumidityMeasurement = clusters.RelativeHumidity

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("frient-humidity-temperature-battery.yml"),
    zigbee_endpoints = {
      [26] = {
        id = 26,
        manufacturer = "frient A/S",
        model = "HMSZB-120",
        server_clusters = {0x0001, 0x0402, 0x0405}
      },
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
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
        HumidityMeasurement.attributes.MeasuredValue:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
      }
    },
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
        "Min battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 23) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
            }
        }
)

test.register_message_test(
        "Max battery voltage report should be handled",
        {
            {
                channel = "zigbee",
                direction = "receive",
                message = { mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_device:generate_test_message("main", capabilities.battery.battery(100))
            }
        }
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        HumidityMeasurement.ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        TemperatureMeasurement.ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device,
        zigbee_test_utils.mock_hub_eui,
        PowerConfiguration.ID
      )
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      HumidityMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 60, 3600, 300)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 0x001E, 0x0E10, 100)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Humidity report should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        HumidityMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 0x1950)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 65 }))
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
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
    }
  }
)

test.register_coroutine_test(
    "info_changed to check for necessary preferences settings: Temperature Sensitivity",
    function()
        local updates = {
            preferences = {
                temperatureSensitivity = 0.9,
                humiditySensitivity = 10
            }
        }
        test.socket.zigbee:__set_channel_ordering("relaxed")
        test.wait_for_events()

        test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))

        local temperatureSensitivity = math.floor(0.9 * 100 + 0.5)
        test.socket.zigbee:__expect_send({ mock_device.id,
                                           TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(
                                                   mock_device,
                                                   30,
                                                   3600,
                                                   temperatureSensitivity
                                           )
        })
        local humiditySensitivity = math.floor(10 * 100 + 0.5)
        test.socket.zigbee:__expect_send({ mock_device.id,
                                           HumidityMeasurement.attributes.MeasuredValue:configure_reporting(
                                                   mock_device,
                                                   60,
                                                   3600,
                                                   humiditySensitivity
                                           )
        })

        test.mock_time.advance_time(5)
        test.socket.zigbee:__expect_send({
            mock_device.id,
            PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
        })
        test.socket.zigbee:__expect_send({
            mock_device.id,
            HumidityMeasurement.attributes.MeasuredValue:read(mock_device)
        })
        test.socket.zigbee:__expect_send({
            mock_device.id,
            TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
        })
    end
)

test.run_registered_tests()