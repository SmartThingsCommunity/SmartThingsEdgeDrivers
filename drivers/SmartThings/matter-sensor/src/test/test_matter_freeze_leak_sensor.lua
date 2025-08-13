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
  profile = t_utils.get_profile_definition("freeze-leak-fault-freezeSensitivity-leakSensitivity.yml"),
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
        {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.BooleanStateConfiguration.ID, cluster_type = "SERVER", feature_map = 31},
      },
      device_types = {
        {device_type_id = 0x0043, device_type_revision = 1} -- Water Leak Detector
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.BooleanState.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.BooleanStateConfiguration.ID, cluster_type = "SERVER", feature_map = 31},
      },
      device_types = {
        {device_type_id = 0x0041, device_type_revision = 1} -- Water Freeze Detector
      }
    }
  }
})

local function test_init_freeze_leak()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_freeze_leak)
  test.socket.device_lifecycle:__queue_receive({ mock_device_freeze_leak.id, "added" })

  test.socket.device_lifecycle:__queue_receive({ mock_device_freeze_leak.id, "init" })
  test.socket.matter:__expect_send({mock_device_freeze_leak.id, clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:read(mock_device_freeze_leak, 1)})
  test.socket.matter:__expect_send({mock_device_freeze_leak.id, clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:read(mock_device_freeze_leak, 2)})
  local subscribe_request = clusters.BooleanState.attributes.StateValue:subscribe(mock_device_freeze_leak)
  subscribe_request:merge(clusters.BooleanStateConfiguration.attributes.SensorFault:subscribe(mock_device_freeze_leak))
  test.socket.matter:__expect_send({mock_device_freeze_leak.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_freeze_leak.id, "doConfigure" })
  mock_device_freeze_leak:expect_metadata_update({ profile = "freeze-leak-fault-freezeSensitivity-leakSensitivity" })
  mock_device_freeze_leak:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init_freeze_leak)

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
  "Check that preference updates to low as expected", function()
    test.socket.matter:__queue_receive({
      mock_device_freeze_leak.id,
      clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:build_test_report_data(
        mock_device_freeze_leak, 2, 4
      )
    })
    test.wait_for_events()

    test.socket.device_lifecycle():__queue_receive(mock_device_freeze_leak:generate_info_changed({ preferences = { freezeSensitivity = "0" } }))
    test.socket.matter:__expect_send({
      mock_device_freeze_leak.id,
      clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(mock_device_freeze_leak, 2, 0)
    })
  end
)

test.register_coroutine_test(
  "Check that preference updates to high as expected", function()
    test.socket.matter:__queue_receive({
      mock_device_freeze_leak.id,
      clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:build_test_report_data(
        mock_device_freeze_leak, 2, 4
      )
    })
    test.wait_for_events()
    test.socket.device_lifecycle():__queue_receive(mock_device_freeze_leak:generate_info_changed({ preferences = { freezeSensitivity = "2" } }))
    test.socket.matter:__expect_send({
      mock_device_freeze_leak.id,
      clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(mock_device_freeze_leak, 2, mock_device_freeze_leak:get_field("freezeMax") - 1)
    })
  end
)

test.register_coroutine_test(
  "Check that preference updates to high after being set on-device as expected", function()
    test.socket.matter:__queue_receive({
      mock_device_freeze_leak.id,
      clusters.BooleanStateConfiguration.attributes.SupportedSensitivityLevels:build_test_report_data(
        mock_device_freeze_leak, 2, 4
      )
    })
    test.wait_for_events()
    test.socket.device_lifecycle():__queue_receive(mock_device_freeze_leak:generate_info_changed({ preferences = { freezeSensitivity = "2" } }))
    test.socket.matter:__expect_send({
      mock_device_freeze_leak.id,
      clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(mock_device_freeze_leak, 2, mock_device_freeze_leak:get_field("freezeMax") - 1)
    })
    test.socket["matter"]:__queue_receive(
      {
        mock_device_freeze_leak.id,
        clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:build_test_report_data(
          mock_device_freeze_leak, 2, 2 -- put on level two
        )
      }
    )
    test.socket.device_lifecycle():__queue_receive(mock_device_freeze_leak:generate_info_changed({ preferences = { freezeSensitivity = "0" } }))
    test.socket.matter:__expect_send({
      mock_device_freeze_leak.id,
      clusters.BooleanStateConfiguration.attributes.CurrentSensitivityLevel:write(mock_device_freeze_leak, 2, 0)
    })
  end
)

test.run_registered_tests()
