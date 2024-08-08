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
test.add_package_capability("customRainSensor.yml")
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

clusters.BooleanStateConfiguration = require "BooleanStateConfiguration"

local mock_device_rain = test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition("rain-fault.yml"),
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
          {device_type_id = 0x0044, device_type_revision = 1} -- Rain Sensor
        }
      }
    }
})

local subscribed_attributes = {
    [capabilities.BooleanState.ID] = {
        clusters.BooleanState.attributes.StateValue,
    },
    [capabilities.BooleanStateConfiguration.ID] = {
        clusters.BooleanStateConfiguration.attributes.SensorFault,
    },
}

local function test_init_rain()
    local subscribe_request = nil
    for _, attributes in pairs(subscribed_attributes) do
        for _, attribute in ipairs(attributes) do
            if subscribe_request == nil then
                subscribe_request = attribute:subscribe(mock_device_rain)
            else
                subscribe_request:merge(attribute:subscribe(mock_device_rain))
            end
        end
    end

    test.socket.matter:__expect_send({mock_device_rain.id, subscribe_request})
    test.mock_device.add_test_device(mock_device_rain)
end
test.set_test_init_function(test_init_rain)