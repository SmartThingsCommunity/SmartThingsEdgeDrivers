-- Copyright 2024 SmartThings
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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"
clusters.SmokeCoAlarm = require "SmokeCoAlarm"
local version = require "version"
if version.api < 10 then
  clusters.SmokeCoAlarm = require "SmokeCoAlarm"
  clusters.CarbonMonoxideConcentrationMeasurement = require "CarbonMonoxideConcentrationMeasurement"
end

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("tuya-gas.yml"),
  manufacturer_info = {
    vendor_id = 0x125D,
    product_id = 0x0031,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.SmokeCoAlarm.ID, cluster_type = "SERVER", feature_map = clusters.SmokeCoAlarm.types.Feature.CO_ALARM | clusters.SmokeCoAlarm.types.Feature.SMOKE_ALARM},
      },
      device_types = {
        {device_type_id = 0x0076, device_type_revision = 1} -- Smoke CO Alarm
      }
    }
  }
})

local cluster_subscribe_list = {
  clusters.SmokeCoAlarm.attributes.COState,
}

local function test_init()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  mock_device:expect_metadata_update({ profile = "tuya-gas.yml" })
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Test CO state handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.COState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.COState.NORMAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.gasDetector.gas.clear())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.COState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.COState.WARNING)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.gasDetector.gas.detected())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.SmokeCoAlarm.attributes.COState:build_test_report_data(mock_device, 1, clusters.SmokeCoAlarm.attributes.COState.CRITICAL)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.gasDetector.gas.detected())
    }
  }
)

test.run_registered_tests()
