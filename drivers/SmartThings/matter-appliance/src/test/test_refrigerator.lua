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
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local refrigerator_ep = 1
local freezer_ep = 2

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("refrigerator-freezer-tn.yml"),
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
      endpoint_id = refrigerator_ep,
      clusters = {
        { cluster_id = clusters.RefrigeratorAlarm.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0070, device_type_revision = 1 }, -- Refrigerator
        { device_type_id = 0x0071, device_type_revision = 1 } -- Temperature Controlled Cabinet
      }
    },
    {
      endpoint_id = freezer_ep,
      clusters = {
        { cluster_id = clusters.RefrigeratorAlarm.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.RefrigeratorAndTemperatureControlledCabinetMode.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 3},
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER", feature_map = 3},
      },
      device_types = {
        { device_type_id = 0x0070, device_type_revision = 1 }, -- Refrigerator
        { device_type_id = 0x0071, device_type_revision = 1 } -- Temperature Controlled Cabinet
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.RefrigeratorAlarm.attributes.State,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.CurrentMode,
    clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureMeasurement.attributes.MeasuredValue
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.set_rpc_version(5)
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Refrigerator Supported Modes must be registered and Refrigerator Mode command should send appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RefrigeratorAndTemperatureControlledCabinetMode.attributes.SupportedModes:build_test_report_data(mock_device, refrigerator_ep,
          {
            clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeOptionStruct({ ["label"] = "Normal", ["mode"] = 0, ["mode_tags"] = {} }),
            clusters.RefrigeratorAndTemperatureControlledCabinetMode.types.ModeOptionStruct({ ["label"] = "Energy Save", ["mode"] = 1, ["mode_tags"] = {} })
          }
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.mode.supportedModes({"Normal", "Energy Save"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.mode.supportedArguments({"Normal", "Energy Save"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "refrigerator", command = "setMode", args = {"Normal"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.RefrigeratorAndTemperatureControlledCabinetMode.server.commands.ChangeToMode(mock_device, refrigerator_ep, 0) --0 is the index where Quick is stored.
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "refrigerator", command = "setMode", args = {"Energy Save"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.RefrigeratorAndTemperatureControlledCabinetMode.server.commands.ChangeToMode(mock_device, refrigerator_ep, 1) --1 is the index where Super Dry is stored.
      }
    }
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for refrigerator endpoint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, refrigerator_ep, 0)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, refrigerator_ep, 1500)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, refrigerator_ep, 700)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=0.0,maximum=15.0, step = 0.1}, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpoint({value = 7.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "refrigerator", command = "setTemperatureSetpoint", args = {4.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, refrigerator_ep, 4 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for refrigerator endpoint, temp bounds out of range and temp setpoint converted from F to C",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, refrigerator_ep, -1000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, refrigerator_ep, 2500)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, refrigerator_ep, 700)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=-6.0,maximum=20.0, step = 0.1}, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("refrigerator", capabilities.temperatureSetpoint.temperatureSetpoint({value = 7.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "refrigerator", command = "setTemperatureSetpoint", args = {50.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, refrigerator_ep, 10 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for freezer endpoint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, freezer_ep, -2200)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, freezer_ep, -1400)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, freezer_ep, -1700)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=-22.0,maximum=-14.0, step = 0.1}, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpoint({value = -17.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "freezer", command = "setTemperatureSetpoint", args = {-15.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, freezer_ep, -15 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "temperatureSetpoint command should send appropriate commands for freezer endpoint, temp bounds out of range and temp setpoint converted from F to C",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, freezer_ep, -2700)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, freezer_ep, -500)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, freezer_ep, -1500)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=-24.0,maximum=-12.0, step = 0.1}, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("freezer", capabilities.temperatureSetpoint.temperatureSetpoint({value = -15.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "freezer", command = "setTemperatureSetpoint", args = {-4.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, freezer_ep, -20 * 100, nil)
      }
    },
  }
)

test.run_registered_tests()
