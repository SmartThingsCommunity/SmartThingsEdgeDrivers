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

local subscribed_attributes = {
  clusters.BooleanState.attributes.StateValue,
  clusters.BooleanStateConfiguration.attributes.SensorFault,
}

local function test_init_freeze_leak()
  local subscribe_request = subscribed_attributes[1]:subscribe(mock_device_freeze_leak)
  for i, cluster in ipairs(subscribed_attributes) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_freeze_leak))
    end
  end
  test.socket.matter:__expect_send({mock_device_freeze_leak.id, subscribe_request})
  test.mock_device.add_test_device(mock_device_freeze_leak)
  mock_device_freeze_leak:set_field("__battery_checked", 1, {persist = true})
  test.set_rpc_version(4)
end
test.set_test_init_function(test_init_freeze_leak)

local mock_device_freeze_leak_cf = mock_device_freeze_leak

local function test_init_cf()
  local subscribe_request = subscribed_attributes[1]:subscribe(mock_device_freeze_leak_cf)
  for i, cluster in ipairs(subscribed_attributes) do
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

test.register_message_test(
  "Boolean state freeze detection reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_freeze_leak.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device_freeze_leak, 2, false)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_freeze_leak:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_freeze_leak.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device_freeze_leak, 2, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_freeze_leak:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.freeze())
    }
  }
)


test.register_message_test(
  "Boolean state leak detection reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_freeze_leak.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device_freeze_leak, 1, false)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_freeze_leak:generate_test_message("main", capabilities.waterSensor.water.dry())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_freeze_leak.id,
        clusters.BooleanState.server.attributes.StateValue:build_test_report_data(mock_device_freeze_leak, 1, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_freeze_leak:generate_test_message("main", capabilities.waterSensor.water.wet())
    }
  }
)

test.register_message_test(
  "Test hardware fault alert handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_freeze_leak.id,
        clusters.BooleanStateConfiguration.attributes.SensorFault:build_test_report_data(mock_device_freeze_leak, 1, 0x1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_freeze_leak:generate_test_message("main", capabilities.hardwareFault.hardwareFault.detected())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_freeze_leak.id,
        clusters.BooleanStateConfiguration.attributes.SensorFault:build_test_report_data(mock_device_freeze_leak, 1, 0x0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_freeze_leak:generate_test_message("main", capabilities.hardwareFault.hardwareFault.clear())
    }
  }
)

test.register_coroutine_test(
  "Check that preference udpates as expected", function()
    test.socket.device_lifecycle():__queue_receive(mock_device_freeze_leak:generate_info_changed({ preferences = { booleanConfigSensitivity = 1 } }))
    test.socket.matter:__expect_send(mock_device_freeze_leak.id, 1, 2)
  end
)


test.run_registered_tests()
