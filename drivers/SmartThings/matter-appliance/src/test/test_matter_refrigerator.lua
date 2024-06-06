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

clusters.RefrigeratorAlarm = require "RefrigeratorAlarm"
clusters.RefrigeratorAndTemperatureControlledCabinetMode = require "RefrigeratorAndTemperatureControlledCabinetMode"
clusters.TemperatureControl = require "TemperatureControl"
clusters.Te = require "OperationalState"

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
        {cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER"},
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
        {cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER"},
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

test.run_registered_tests()