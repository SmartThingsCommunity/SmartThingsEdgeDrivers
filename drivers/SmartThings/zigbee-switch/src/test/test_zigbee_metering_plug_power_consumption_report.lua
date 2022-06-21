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
local SimpleMetering = clusters.SimpleMetering
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("switch-power-energy-consumption-report.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "DAWON_DNS",
          model = "PM-B430-ZB",
          server_clusters = {}
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

test.register_message_test(
  "SimpleMetering event should be handled by powerConsumptionReport capability",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 27) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 27, deltaEnergy = 0.0 }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 0.027, unit = "kWh"}))
    },
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_device, 42) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({energy = 42, deltaEnergy = 15 }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 0.042, unit = "kWh"}))
    }
  }
)

test.register_message_test(
    "InstaneousDemand Report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, SimpleMetering.attributes.InstantaneousDemand:build_test_attr_report(mock_device, 32) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 32.0, unit = "W" }))
      }
    }
)

test.run_registered_tests()
