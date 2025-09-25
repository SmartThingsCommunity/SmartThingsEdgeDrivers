-- Copyright 2025 SmartThings
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
test.set_rpc_version(6)
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local APPLICATION_ENDPOINT = 1

local mock_device_washer = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("laundry-washer-tn-tl.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
        },
        { cluster_id = clusters.LaundryWasherMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.OperationalState.ID,   cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0073, device_type_revision = 1 } -- LaundryWasher
      }
    }
  }
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device_washer)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LaundryWasherMode.attributes.CurrentMode,
    clusters.LaundryWasherMode.attributes.SupportedModes,
    clusters.OperationalState.attributes.OperationalState,
    clusters.OperationalState.attributes.OperationalError,
    clusters.OperationalState.attributes.AcceptedCommandList,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels
  }
  local subscribe_request_washer = cluster_subscribe_list[1]:subscribe(mock_device_washer)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request_washer:merge(cluster:subscribe(mock_device_washer))
    end
  end
  test.socket.matter:__expect_send({ mock_device_washer.id, subscribe_request_washer })
  test.socket.device_lifecycle:__queue_receive({ mock_device_washer.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_washer.id, "init" })
  test.socket.matter:__expect_send({ mock_device_washer.id, subscribe_request_washer })
  test.socket.device_lifecycle:__queue_receive({ mock_device_washer.id, "doConfigure"})
  local read_req = clusters.TemperatureControl.attributes.MinTemperature:read()
  read_req:merge(clusters.TemperatureControl.attributes.MaxTemperature:read())
  test.socket.matter:__expect_send({mock_device_washer.id, read_req})
  mock_device_washer:expect_metadata_update({ profile = "laundry-washer-tn-tl" })
  mock_device_washer:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for laundry washer",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 1500)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 5000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 4000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=15.0,maximum=50.0, step = 0.1}, unit = "C"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 40.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device_washer.id,
        { capability = "temperatureSetpoint", component = "main", command = "setTemperatureSetpoint", args = {25.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device_washer, APPLICATION_ENDPOINT, 25 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for laundry washer, temp bounds out of range",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, -1000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 12000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device_washer.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device_washer, APPLICATION_ENDPOINT, 3000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=0.0,maximum=100.0, step = 0.1}, unit = "C"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_washer:generate_test_message("main", capabilities.temperatureSetpoint.temperatureSetpoint({value = 30.0, unit = "C"}))
    }
  }
)

test.run_registered_tests()
