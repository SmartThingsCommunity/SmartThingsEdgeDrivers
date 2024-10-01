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
test.add_package_capability("lockAlarm.yml")
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_device_record = {
  profile = t_utils.get_profile_definition("base-lock-nobattery.yml"),
  manufacturer_info = {vendor_id = 0, product_id = 0},
  endpoints = {
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {cluster_id = clusters.DoorLock.ID, cluster_type = "SERVER", feature_map = 0x0000},
      },
    },
  },
}
local mock_device = test.mock_device.build_test_matter_device(mock_device_record)

local mock_device_record_aqara = {
    profile = t_utils.get_profile_definition("base-lock-nobattery.yml"),
    manufacturer_info = {vendor_id = 0x115F, product_id = 0x2801}, -- Aqara Smart Lock U300
    endpoints = {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          device_type_id = 0x0016, device_type_revision = 1, -- RootNode
        }
      },
      {
        endpoint_id = 10,
        clusters = {
          {cluster_id = clusters.DoorLock.ID, cluster_type = "SERVER", feature_map = 0x0000},
        },
      },
    },
}

local mock_device_aqara = test.mock_device.build_test_matter_device(mock_device_record_aqara)

local function test_init()
    local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_device)
    subscribe_request:merge(clusters.DoorLock.events.DoorLockAlarm:subscribe(mock_device))
    subscribe_request:merge(clusters.DoorLock.events.LockOperation:subscribe(mock_device))
    subscribe_request:merge(clusters.DoorLock.events.LockUserChange:subscribe(mock_device))
    test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
    test.mock_device.add_test_device(mock_device)

    local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_device_aqara)
    subscribe_request:merge(clusters.DoorLock.events.DoorLockAlarm:subscribe(mock_device_aqara))
    subscribe_request:merge(clusters.DoorLock.events.LockOperation:subscribe(mock_device_aqara))
    subscribe_request:merge(clusters.DoorLock.events.LockUserChange:subscribe(mock_device_aqara))
    test.socket["matter"]:__expect_send({mock_device_aqara.id, subscribe_request})
    test.mock_device.add_test_device(mock_device_aqara)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
    "doConfigure lifecycle event for base-lock-nobattery",
    function()
        test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
        mock_device:expect_metadata_update({ profile = "base-lock-nobattery" })
        mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "doConfigure lifecycle event for aqara lock",
    function()
        test.socket.device_lifecycle:__queue_receive({ mock_device_aqara.id, "doConfigure" })
        mock_device_aqara:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.run_registered_tests()
