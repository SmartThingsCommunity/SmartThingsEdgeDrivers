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
  profile = t_utils.get_profile_definition("laundry-washer.yml"),
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
        {cluster_id = clusters.LaundryWasherMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LaundryWasherControls.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.OperationalState.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0073, device_type_revision = 1} -- Laundry Washer
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
      clusters.LaundryWasherMode.attributes.SupportedModes,
      clusters.LaundryWasherMode.attributes.CurrentMode,
    },
    [capabilities.laundryWasherRinseMode.ID] = {
      clusters.LaundryWasherControls.attributes.NumberOfRinses,
      clusters.LaundryWasherControls.attributes.SupportedRinses,
    },
    [capabilities.laundryWasherSpinSpeed.ID] = {
      clusters.LaundryWasherControls.attributes.SpinSpeeds,
      clusters.LaundryWasherControls.attributes.SpinSpeedCurrent,
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

local mode_tag_normal = clusters.LaundryWasherMode.types.ModeTagStruct.init(clusters.LaundryWasherMode.types.ModeTagStruct, {mfg_code=1, value=0x4000})
local mode_tag_heavy = clusters.LaundryWasherMode.types.ModeTagStruct.init(clusters.LaundryWasherMode.types.ModeTagStruct, {mfg_code=1, value=0x4002})

test.register_message_test(
  "Supported dishwasher mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LaundryWasherMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Normal", mode=0, mode_tags = {mode_tag_normal}}, {label = "Heavy", mode=0, mode_tags = {mode_tag_heavy}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({value={"Normal", "Heavy"}}))
    }
  }
)

test.register_message_test(
  "Laundry washer mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LaundryWasherMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Normal", mode=0, mode_tags = {mode_tag_normal}}, {label = "Heavy", mode=0, mode_tags = {mode_tag_heavy}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({value={"Normal", "Heavy"}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LaundryWasherMode.attributes.CurrentMode:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.mode("Heavy"))
    },
  }
)

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

test.register_message_test(
  "Laundry washer rinse mode should generate correct messages",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "laundryWasherRinseMode", component = "main", command = "setRinseMode", args = {"normal"} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.LaundryWasherControls.attributes.NumberOfRinses:write(mock_device, 1, clusters.LaundryWasherControls.attributes.NumberOfRinses.NORMAL)
      }
    },
  }
)

test.register_message_test(
  "Laundry washer spin speed should generate correct messages",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
          mock_device.id,
          { capability = "laundryWasherRinseMode", component = "main", command = "setRinseMode", args = {"normal"} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
          mock_device.id,
          clusters.LaundryWasherControls.attributes.NumberOfRinses:write(mock_device, 1, clusters.LaundryWasherControls.attributes.NumberOfRinses.NORMAL)
      }
    },
  }
)

test.run_registered_tests()