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
local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"


local mock_simple_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("switch-power-2.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "Aurora",
          model = "DoubleSocket50AU",
          server_clusters = {0x0019}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_simple_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Reported on off status should be handled: on ep 1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                true):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: on ep 2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                true):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("switch1",  capabilities.switch.switch.on())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: off ep 1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                false):from_endpoint(0x01) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "Reported on off status should be handled: off ep 2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_simple_device.id, OnOff.attributes.OnOff:build_test_attr_report(mock_simple_device,
                                                                                                false):from_endpoint(0x02) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("switch1",  capabilities.switch.switch.off())
      }
    }
)

test.register_message_test(
    "ActivePower Report should be handled: Sensor value is in W, capability attribute value is in W, ep 1",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_simple_device,27):from_endpoint(0x01)
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("main",  capabilities.powerMeter.power({ value = 27.0, unit = "W" }))
      }
    }
)

test.register_message_test(
    "ActivePower Report should be handled: Sensor value is in W, capability attribute value is in W, ep 2",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_simple_device.id,
          ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_simple_device,27):from_endpoint(0x02)
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_simple_device:generate_test_message("switch1",  capabilities.powerMeter.power({ value = 27.0, unit = "W" }))
      }
    }
)

test.run_registered_tests()
