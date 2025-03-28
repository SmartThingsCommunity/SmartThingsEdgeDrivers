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
  profile = t_utils.get_profile_definition("refrigerator-freezer-tn-tl.yml"),
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
        {cluster_id = clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RefrigeratorAlarm.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0070, device_type_revision = 1} -- Refrigerator
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0071, device_type_revision = 1} -- Temperature Controlled Cabinet
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = clusters.TemperatureControl.types.Feature.TEMPERATURE_NUMBER},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0071, device_type_revision = 1} -- Temperature Controlled Cabinet
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [capabilities.temperatureSetpoint.ID] = {
      clusters.TemperatureControl.attributes.TemperatureSetpoint,
      clusters.TemperatureControl.attributes.MinTemperature,
      clusters.TemperatureControl.attributes.MaxTemperature,
    },
    [capabilities.temperatureLevel.ID] = {
      clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
      clusters.TemperatureControl.attributes.SupportedTemperatureLevels,
    },
    [capabilities.mode.ID] = {
      clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes,
      clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode,
    },
    [capabilities.contactSensor.ID] = {
      clusters.RefrigeratorAlarm.attributes.State,
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.TemperatureMeasurement.attributes.MeasuredValue
    }
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

  local componentToEndpointMap = {
      ["refrigerator"] = 2,
      ["freezer"] = 3
    }
  local COMPONENT_TO_ENDPOINT_MAP = "__component_to_endpoint_map"
  mock_device:set_field(COMPONENT_TO_ENDPOINT_MAP, componentToEndpointMap, {persist = true})
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Refrigerator alarm should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RefrigeratorAlarm.server.attributes.State:build_test_report_data(mock_device, 1, clusters.RefrigeratorAlarm.types.AlarmMap.DOOR_OPEN)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.contactSensor.contact.open())
    }
  }
)

local mode_tag_rapid_cool = clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeTagStruct.init(clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeTagStruct, {mfg_code=1, value=0x4000})
local mode_tag_rapid_freeze = clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeTagStruct.init(clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeTagStruct, {mfg_code=1, value=0x4001})

test.register_message_test(
  "Supported temperature controlled cabinet mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Rapid Cool", mode=0, mode_tags = {mode_tag_rapid_cool}}, {label = "Rapid Freeze", mode=0, mode_tags = {mode_tag_rapid_freeze}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({value={"Rapid Cool", "Rapid Freeze"}}))
    }
  }
)

test.register_message_test(
  "Temperature controlled cabinet mode should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes:build_test_report_data(mock_device, 1, {{label = "Rapid Cool", mode=0, mode_tags = {mode_tag_rapid_cool}}, {label = "Rapid Freeze", mode=0, mode_tags = {mode_tag_rapid_freeze}}})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.supportedModes({value={"Rapid Cool", "Rapid Freeze"}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode:build_test_report_data(mock_device, 1, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.mode.mode("Rapid Freeze"))
    }
  }
)

test.register_message_test(
  "Temperature setpoint should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.server.attributes.TemperatureSetpoint:build_test_report_data(mock_device, 2, 25 * 100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpointRange({unit="C", value={maximum=100, minimum=0}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpoint({value = 25.0, unit = "C"}))
    }
  }
)

test.register_message_test(
  "Temperature reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 3, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("freezer", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    }
  }
)

test.run_registered_tests()