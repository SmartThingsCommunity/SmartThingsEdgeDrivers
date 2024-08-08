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

clusters.BooleanStateConfiguration = require "BooleanStateConfiguration"

local mock_device_freeze_leak = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("freeze-leak-fault.yml"),
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
          {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.BooleanStateConfiguration.ID, cluster_type = "SERVER"},
        },
        device_types = {
          {device_type_id = 0x0043, device_type_revision = 1} -- Water Leak Detector
        }
      },
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.BooleanStateConfiguration.ID, cluster_type = "SERVER"},
        },
        device_types = {
          {device_type_id = 0x0041, device_type_revision = 1} -- Water Freeze Detector
        }
      }
    }
})

local mock_device_freeze_leak_cf = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("freeze-leak-fault.yml"),
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
        {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.BooleanStateConfiguration.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0043, device_type_revision = 1} -- Water Leak Detector
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.BooleanStateConfiguration.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0041, device_type_revision = 1} -- Water Freeze Detector
      }
    }
  }
})

local subscribed_attributes = {
  [clusters.BooleanState.ID] =  {
    clusters.BooleanState.attributes.StateValue,
  },
  [clusters.BooleanStateConfiguration.ID] = {
    clusters.BooleanStateConfiguration.attributes.SensorFault,
  }
}

local subscribed_attributes_cf = {
  clusters.BooleanState.attributes.StateValue,
  clusters.BooleanStateConfiguration.attributes.SensorFault,
}

local function test_init_freeze_leak()
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device_freeze_leak)
      else
        subscribe_request:merge(attribute:subscribe(mock_device_freeze_leak))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device_freeze_leak.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_freeze_leak)
end
test.set_test_init_function(test_init_freeze_leak)

local function test_init_cf()
  local subscribe_request = subscribed_attributes_cf[1]:subscribe(mock_device_freeze_leak_cf)
  for i, cluster in ipairs(subscribed_attributes_cf) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_freeze_leak_cf))
    end
  end
  test.socket.matter:__expect_send({mock_device_freeze_leak_cf.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_freeze_leak_cf)
  mock_device_freeze_leak_cf:expect_metadata_update({ profile = "freeze-leak-fault" })
  mock_device_freeze_leak_cf:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "Test profile change on init for Freeze and Leak combined device type",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_freeze_leak_cf.id, "doConfigure" })
  end,
  { test_init = test_init_cf }
)

test.run_registered_tests()
