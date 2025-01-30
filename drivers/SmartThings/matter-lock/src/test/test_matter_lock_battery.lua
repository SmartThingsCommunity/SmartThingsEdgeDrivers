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
local uint32 = require "st.matter.data_types.Uint32"

local mock_device_record = {
  profile = t_utils.get_profile_definition("base-lock.yml"),
  manufacturer_info = {vendor_id = 0xcccc, product_id = 0x1},
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
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 10},
      },
    },
  },
}
local mock_device = test.mock_device.build_test_matter_device(mock_device_record)

local mock_device_no_battery_record = {
  profile = t_utils.get_profile_definition("base-lock.yml"),
  manufacturer_info = {vendor_id = 0xcccc, product_id = 0x1},
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
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0},
      },
    },
  },
}
local mock_device_no_battery = test.mock_device.build_test_matter_device(mock_device_no_battery_record)

local function test_init()
  local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_device)
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.DoorLockAlarm:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.LockOperation:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.LockUserChange:subscribe(mock_device))
  test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device.id, read_attribute_list})
end
test.set_test_init_function(test_init)

local function test_init_no_battery()
  local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_device_no_battery)
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(mock_device))
  subscribe_request:merge(clusters.DoorLock.events.DoorLockAlarm:subscribe(mock_device_no_battery))
  subscribe_request:merge(clusters.DoorLock.events.LockOperation:subscribe(mock_device_no_battery))
  subscribe_request:merge(clusters.DoorLock.events.LockUserChange:subscribe(mock_device_no_battery))
  test.socket["matter"]:__expect_send({mock_device_no_battery.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_no_battery)
  test.socket.device_lifecycle:__queue_receive({ mock_device_no_battery.id, "doConfigure" })
  mock_device_no_battery:expect_metadata_update({ profile = "base-lock-nobattery" })
  mock_device_no_battery:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.register_coroutine_test(
  "Test profile changes to base-lock when battery percent remaining attribute (attribute ID 12) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 2,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(12),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device:expect_metadata_update({ profile = "base-lock" })
  end
)

test.register_coroutine_test(
  "Test that profile changes to base-lock-batteryLevel when battery level attribute (attribute ID 14) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 2,
          {
            uint32(0),
            uint32(1),
            uint32(2),
            uint32(14),
            uint32(31),
            uint32(65528),
            uint32(65529),
            uint32(65531),
            uint32(65532),
            uint32(65533),
          })
      }
    )
    mock_device:expect_metadata_update({ profile = "base-lock-batteryLevel" })
  end
)

test.register_coroutine_test(
  "Test that profile changes to base-lock-no-battery when battery feature is not available",
  function()
  end,
  { test_init = test_init_no_battery }
)
test.run_registered_tests()
