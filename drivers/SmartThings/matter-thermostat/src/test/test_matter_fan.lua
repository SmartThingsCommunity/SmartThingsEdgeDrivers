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
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("fan-rock-wind.yml"),
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
          {device_type_id = 0x0016, device_type_revision = 1,} -- RootNode
        }
      },
      {
        endpoint_id = 1,
        clusters = {
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 15},
        },
        device_types = {
          {device_type_id = 0x002B, device_type_revision = 1,} -- Fan
        }
      }
    }
})

local mock_device_generic = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("fan-generic.yml"),
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
          {device_type_id = 0x0016, device_type_revision = 1,} -- RootNode
        }
      },
      {
        endpoint_id = 1,
        clusters = {
          {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 0},
        },
        device_types = {
            {device_type_id = 0x002B, device_type_revision = 1,} -- Fan
        }
      }
    }
})

local cluster_subscribe_list = {
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.PercentCurrent,
    clusters.FanControl.attributes.WindSupport,
    clusters.FanControl.attributes.WindSetting,
    clusters.FanControl.attributes.RockSupport,
    clusters.FanControl.attributes.RockSetting,
}

local cluster_subscribe_list_generic = {
    clusters.FanControl.attributes.FanMode,
    clusters.FanControl.attributes.PercentCurrent,
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
end
test.set_test_init_function(test_init)

local function test_init_generic()
  local subscribe_request = cluster_subscribe_list_generic[1]:subscribe(mock_device_generic)
  for i, cluster in ipairs(cluster_subscribe_list_generic) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_generic))
    end
  end
  test.socket.matter:__expect_send({mock_device_generic.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_generic)
end

test.register_coroutine_test(
  "Test profile change on fan with rock and wind",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({ profile = "fan-rock-wind" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { test_init = test_init }
)

test.register_coroutine_test(
  "Test profile change on fan with no features",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_generic.id, "doConfigure" })
    mock_device_generic:expect_metadata_update({ profile = "fan-generic" })
    mock_device_generic:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  { test_init = test_init_generic }
)

test.run_registered_tests()
