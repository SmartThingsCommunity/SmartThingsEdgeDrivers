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

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("rvc.yml"),
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
        {cluster_id = clusters.RvcRunMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RvcCleanMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RvcOperationalState.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0074, device_type_revision = 1} -- Robot Vacuum Cleaner
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [capabilities.mode.ID] = {
        clusters.RvcRunMode.attributes.SupportedModes,
        clusters.RvcRunMode.attributes.CurrentMode,
        clusters.RvcCleanMode.attributes.SupportedModes,
        clusters.RvcCleanMode.attributes.CurrentMode,
    },
    [capabilities.robotCleanerOperatingState.ID] = {
        clusters.RvcOperationalState.attributes.OperationalState,
        clusters.RvcOperationalState.attributes.OperationalError,
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

test.register_message_test(
  "Operational state should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcOperationalState.server.attributes.OperationalState:build_test_report_data(mock_device, 1, clusters.OperationalState.types.OperationalStateEnum.STOPPED)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.robotCleanerOperatingState.operatingState.stopped())
    }
  }
)

local mode_tag_idle = clusters.RvcRunMode.types.ModeTagStruct.init(clusters.RvcRunMode.types.ModeTagStruct, {mfg_code=1, value=0x4000})
local mode_tag_cleaning = clusters.RvcRunMode.types.ModeTagStruct.init(clusters.RvcRunMode.types.ModeTagStruct, {mfg_code=1, value=0x4001})

test.register_message_test(
  "Supported run mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcRunMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Quick", mode=0, mode_tags = {mode_tag_cleaning}}, {label = "Idle", mode=0, mode_tags = {mode_tag_idle}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("runMode", capabilities.mode.supportedModes({value={"Quick", "Idle"}}))
    }
  }
)

test.register_message_test(
  "Run mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcRunMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Quick", mode=0, mode_tags = {mode_tag_cleaning}}, {label = "Idle", mode=1, mode_tags = {mode_tag_idle}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("runMode", capabilities.mode.supportedModes({value={"Quick", "Idle"}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcRunMode.attributes.CurrentMode:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("runMode", capabilities.mode.mode("Idle"))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("runMode", capabilities.mode.supportedModes({value={"Quick", "Idle"}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cleanMode", capabilities.mode.supportedModes({value={}}))
    },
  }
)

local mode_tag_deep_clean = clusters.RvcRunMode.types.ModeTagStruct.init(clusters.RvcRunMode.types.ModeTagStruct, {mfg_code=1, value=0x4000})
local mode_tag_vacuum = clusters.RvcRunMode.types.ModeTagStruct.init(clusters.RvcRunMode.types.ModeTagStruct, {mfg_code=1, value=0x4001})
test.register_message_test(
  "Supported clean mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcCleanMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Deep Clean", mode=0, mode_tags = {mode_tag_deep_clean}}, {label = "Vacuum", mode=0, mode_tags = {mode_tag_vacuum}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cleanMode", capabilities.mode.supportedModes({value={"Deep Clean", "Vacuum"}}))
    }
  }
)

test.register_message_test(
  "Clean mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcCleanMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Deep Clean", mode=0, mode_tags = {mode_tag_deep_clean}}, {label = "Vacuum", mode=0, mode_tags = {mode_tag_vacuum}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cleanMode", capabilities.mode.supportedModes({value={"Deep Clean", "Vacuum"}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcCleanMode.attributes.CurrentMode:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cleanMode", capabilities.mode.mode("Vacuum"))
    }
  }
)


local operational_state_error = clusters.OperationalState.types.ErrorStateStruct.init(
  clusters.OperationalState.types.ErrorStateStruct, {error_state_id=clusters.OperationalState.types.ErrorStateEnum.UNABLE_TO_START_OR_RESUME, error_state_label="", error_state_details=""}
)

test.register_message_test(
  "Operational error should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RvcOperationalState.attributes.OperationalError:build_test_report_data(mock_device, 1, operational_state_error )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.robotCleanerOperatingState.operatingState.unableToStartOrResume())
    },
  }
)


test.run_registered_tests()