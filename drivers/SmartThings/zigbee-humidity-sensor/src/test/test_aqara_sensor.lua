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

local base64 = require "st.base64"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"

local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement
local RelativeHumidity = clusters.RelativeHumidity

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("humidity-temp-battery-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.sensor_ht.agl02",
        server_clusters = { 0x0001, 0x0402, 0x0405, 0x0403 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.batteryLevel.battery.normal()))
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Configure should configure all necessary attributes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, TemperatureMeasurement.attributes.MeasuredValue:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, RelativeHumidity.attributes.MeasuredValue:read(mock_device) })
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
        RelativeHumidity.ID
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
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 3600, 7200, 50)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      RelativeHumidity.attributes.MeasuredValue:configure_reporting(mock_device, 3600, 7200, 200)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 3600, 1)
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
        RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 7900)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.relativeHumidityMeasurement.humidity({ value = 79 }))
    }
  }
)

test.register_message_test(
  "Humidity report should be handled for 0 value",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.relativeHumidityMeasurement.humidity({ value = 0 }))
    }
  }
)

test.register_message_test(
  "Humidity report should be handled for 100 value",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 10000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.relativeHumidityMeasurement.humidity({ value = 100 }))
    }
  }
)

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
      message = mock_device:generate_test_message("main",
        capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" }))
    }
  }
)

test.register_coroutine_test(
  "Handle tempOffset preference in infochanged",
  function()
    test.socket.environment_update:__queue_receive({ "zigbee",
      { hub_zigbee_id = base64.encode(zigbee_test_utils.mock_hub_eui) } })
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = { tempOffset = -5 } }))
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500)
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C" })))
    test.wait_for_events()
  end
)

test.register_message_test(
  "BatteryVoltage report should be handled(normal)",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 30)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.normal())
    }
  }
)

test.register_message_test(
  "BatteryVoltage report should be handled(critical)",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 10)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.critical())
    }
  }
)

test.register_message_test(
  "BatteryVoltage report should be handled(warning)",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, 26)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.warning())
    }
  }
)

test.run_registered_tests()
