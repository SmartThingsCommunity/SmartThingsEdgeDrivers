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
test.add_package_capability("lockAlarm.yml")
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local mock_device_record = {
  profile = t_utils.get_profile_definition("lock-nocodes-notamper-batteryLevel.yml"),
  manufacturer_info = {vendor_id = 0x101D, product_id = 0x1},
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
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002},
      },
    },
  },
}
local mock_device = test.mock_device.build_test_matter_device(mock_device_record)


local function test_init()
    local subscribe_request = clusters.DoorLock.attributes.LockState:subscribe(mock_device)
    subscribe_request:merge(clusters.PowerSource.attributes.BatChargeLevel:subscribe(mock_device))
    test.socket["matter"]:__expect_send({mock_device.id, subscribe_request})
    test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Handle BatChargeLevel capability handling with batteryLevel.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatChargeLevel:build_test_report_data(
          mock_device, 10, clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.critical()),
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatChargeLevel:build_test_report_data(
          mock_device, 10, clusters.PowerSource.types.BatChargeLevelEnum.WARNING
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.warning()),
    },
    {
        channel = "matter",
        direction = "receive",
        message = {
          mock_device.id,
          clusters.PowerSource.attributes.BatChargeLevel:build_test_report_data(
            mock_device, 10, clusters.PowerSource.types.BatChargeLevelEnum.OK
          ),
        },
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.batteryLevel.battery.normal()),
      },
  }
)

test.run_registered_tests()
