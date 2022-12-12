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
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("power-meter.yml") }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "ActivePower Report should be handled. Sensor value is in W, capability attribute value is in hectowatts",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ElectricalMeasurement.attributes.ACPowerDivisor:build_test_attr_report(mock_device, 0x0A) }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_device,
                                                                                                        27) },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 2.7, unit = "W" }))
      }
    }
)

test.register_message_test(
    "InstaneousDemand Report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, SimpleMetering.attributes.Divisor:build_test_attr_report(mock_device, 0x3E8) }
      },
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 27) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.027, unit = "kWh" }))
      }
    }
)

test.register_coroutine_test(
    "lifecycle configure event should configure device",
    function ()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.InstantaneousDemand:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.CurrentSummationDelivered:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ActivePower:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              SimpleMetering.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.InstantaneousDemand:configure_reporting(mock_device, 1, 3600, 5)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(mock_device, 5, 3600, 1)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         zigbee_test_utils.build_bind_request(mock_device,
                                                                              zigbee_test_utils.mock_hub_eui,
                                                                              ElectricalMeasurement.ID)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ActivePower:configure_reporting(mock_device, 1, 3600, 5)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ACPowerDivisor:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         ElectricalMeasurement.attributes.ACPowerMultiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.Multiplier:read(mock_device)
                                       })
      test.socket.zigbee:__expect_send({
                                         mock_device.id,
                                         SimpleMetering.attributes.Divisor:read(mock_device)
                                       })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)


test.run_registered_tests()
