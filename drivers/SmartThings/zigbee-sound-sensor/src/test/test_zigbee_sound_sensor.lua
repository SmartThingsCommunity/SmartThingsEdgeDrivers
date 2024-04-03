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
local data_types = require "st.zigbee.data_types"

local PollControl = clusters.PollControl

local IASZone = clusters.IASZone
local PowerConfiguration = clusters.PowerConfiguration
local TemperatureMeasurement = clusters.TemperatureMeasurement

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("battery-sound-temperature.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Ecolink",
        model = "FFZB1-SM-ECO",
        server_clusters = {0x0000, 0x0001, 0x0003, 0x0020, 0x0402, 0x0500, 0x0B05}
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
  "doConifigure lifecycle should configure device",
  function ()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
        mock_device.id,
      IASZone.attributes.IASCIEAddress:write(mock_device, zigbee_test_utils.mock_hub_eui)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      IASZone.server.commands.ZoneEnrollResponse(mock_device, 0x00, 0x00)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PowerConfiguration.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
                                        PowerConfiguration.attributes.BatteryVoltage:configure_reporting(mock_device, 30, 21600, 1)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, IASZone.ID)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        IASZone.attributes.ZoneStatus:configure_reporting(mock_device, 30, 300, 1)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
                                        zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, TemperatureMeasurement.ID)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
      TemperatureMeasurement.attributes.MeasuredValue:configure_reporting(mock_device, 30, 600, 100)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, PollControl.ID)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
      PollControl.attributes.CheckInInterval:configure_reporting(mock_device, 0, 3600,0)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
        PowerConfiguration.attributes.BatteryVoltage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
                                        mock_device.id,
      IASZone.attributes.ZoneStatus:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
          TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        PollControl.server.commands.SetLongPollInterval(mock_device, data_types.Uint32(1200))
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        PollControl.server.commands.SetShortPollInterval(mock_device, data_types.Uint16(2))
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        PollControl.attributes.FastPollTimeout:write(mock_device, data_types.Uint16(40))
    })
    test.socket.zigbee:__expect_send({
        mock_device.id,
        PollControl.attributes.CheckInInterval:write(mock_device, data_types.Uint32(6480))
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_message_test(
  "Refresh should read all necessary attributes",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = {mock_device.id, "added"}
    },
    {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.soundSensor.sound.not_detected())
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "refresh", component = "main", command = "refresh", args = {} }
      }
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
        IASZone.attributes.ZoneStatus:read(mock_device)
      }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = {
        mock_device.id,
        TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
      }
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Reported ZoneStatus should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.attributes.ZoneStatus:build_test_attr_report(mock_device, 0x0001) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.soundSensor.sound.detected())
    }
  }
)

test.register_message_test(
  "ZoneStatusChangeNotification should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0021, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.soundSensor.sound.detected())
    }
  }
)

test.register_message_test(
  "ZoneStatusChangeNotification should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, IASZone.client.commands.ZoneStatusChangeNotification.build_test_rx(mock_device, 0x0020, 0x00) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.soundSensor.sound.not_detected())
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

test.run_registered_tests()
