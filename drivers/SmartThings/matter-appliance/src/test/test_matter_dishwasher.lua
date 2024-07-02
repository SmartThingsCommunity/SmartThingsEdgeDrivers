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
  profile = t_utils.get_profile_definition("dishwasher-tn-tl.yml"),
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
        {cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = clusters.TemperatureControl.types.Feature.TEMPERATURE_LEVEL},
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
    [capabilities.temperatureSetpoint.ID] = {
      clusters.TemperatureControl.attributes.TemperatureSetpoint,
      clusters.TemperatureControl.attributes.MinTemperature,
      clusters.TemperatureControl.attributes.MaxTemperature,
    },
    [capabilities.temperatureLevel.ID] = {
      clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
      clusters.TemperatureControl.attributes.SupportedTemperatureLevels,
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
  "Dishwasher alarm should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DishwasherAlarm.server.attributes.State:build_test_report_data(mock_device, 1, clusters.DishwasherAlarm.types.AlarmMap.INFLOW_ERROR)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.waterFlowAlarm.rateAlarm.alarm())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureAlarm.temperatureAlarm.cleared())
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  capabilities.waterFlowAlarm.volumeAlarm.normal())
    }
  }
)

local mode_tag_normal = clusters.RvcRunMode.types.ModeTagStruct.init(clusters.RvcRunMode.types.ModeTagStruct, {mfg_code=1, value=0x4000})
local mode_tag_heavy = clusters.RvcRunMode.types.ModeTagStruct.init(clusters.RvcRunMode.types.ModeTagStruct, {mfg_code=1, value=0x4001})

test.register_message_test(
  "Supported dishwasher mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DishwasherMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Normal", mode=0, mode_tags = {mode_tag_normal}}, {label = "Heavy", mode=0, mode_tags = {mode_tag_heavy}}})
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
  "Dishwasher mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.DishwasherMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Normal", mode=0, mode_tags = {mode_tag_normal}}, {label = "Heavy", mode=0, mode_tags = {mode_tag_heavy}}})
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
        clusters.DishwasherMode.attributes.CurrentMode:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.mode("Heavy"))
    },
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
        clusters.OperationalState.attributes.OperationalError:build_test_report_data(mock_device, 1, operational_state_error )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",  capabilities.operationalState.operationalState.unableToStartOrResume())
    },
  }
)

test.run_registered_tests()