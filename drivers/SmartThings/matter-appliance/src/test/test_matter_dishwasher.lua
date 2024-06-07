-- Copyright 2023 SmartThings
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

clusters.DishwasherAlarm = require "DishwasherAlarm"
clusters.DishwasherMode = require "DishwasherMode"
clusters.OperationalState = require "OperationalState"
clusters.TemperatureControl = require "TemperatureControl"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("dishwasher.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
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
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.DishwasherMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.DishwasherAlarm.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.OperationalState.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0075, device_type_revision = 1} -- Dishwasher
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.operationalState.ID] = {
      clusters.OperationalState.attributes.AcceptedCommandList,
      clusters.OperationalState.attributes.OperationalState,
      clusters.OperationalState.attributes.OperationalError,
    },
    [capabilities.mode.ID] = {
      clusters.DishwasherMode.attributes.SupportedModes,
      clusters.DishwasherMode.attributes.CurrentMode,
    },
    [capabilities.contactSensor.ID] = {
      clusters.DishwasherAlarm.attributes.State,
    },
    [capabilities.waterFlowAlarm.ID] = {
      clusters.DishwasherAlarm.attributes.State
    },
    [capabilities.temperatureAlarm.ID] = {
      clusters.DishwasherAlarm.attributes.State
    },
  }
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device)
      else
        subscribe_request:merge(attribute:subscribe(mock_device))
      end
    end
  end

  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

-- This test requires an updated capability definition that does not exist in older lua libs
-- Therefore, we will skip this test in CI until newer lua libs are used in the CI
test.register_message_test(
  "Operational state should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OperationalState.server.attributes.OperationalState:build_test_report_data(mock_device, 1, clusters.OperationalState.types.OperationalStateEnum.STOPPED)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.operationalState.operationalState.stopped())
    }
  }
)

test.run_registered_tests()