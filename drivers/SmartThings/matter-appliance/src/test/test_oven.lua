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
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local OVEN_ENDPOINT = 1
local OVEN_TCC_ONE_ENDPOINT = 2
local OVEN_TCC_TWO_ENDPOINT = 3
local COOK_TOP_ENDPOINT = 4
local COOK_SURFACE_ONE_ENDPOINT = 5
local COOK_SURFACE_TWO_ENDPOINT = 6

clusters.OvenMode = require "OvenMode"
clusters.TemperatureControl = require "TemperatureControl"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("oven-cabinet-one-tn-cabinet-two-tl-cook-top-cook-surface-one-tl-cook-surface-two-tl.yml"),
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
      endpoint_id = OVEN_ENDPOINT,
      clusters = {},
      device_types = {
        { device_type_id = 0x007B, device_type_revision = 1 } -- Oven
      }
    },
    {
      endpoint_id = OVEN_TCC_ONE_ENDPOINT,
      clusters = {
        { cluster_id = clusters.OvenMode.ID,               cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 1 }, --Temperature Number
      },
      device_types = {
        { device_type_id = 0x0071, device_type_revision = 1 } -- Oven TCC
      }
    },
    {
      endpoint_id = OVEN_TCC_TWO_ENDPOINT,
      clusters = {
        { cluster_id = clusters.OvenMode.ID,               cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 2 }, --Temperature Level
      },
      device_types = {
        { device_type_id = 0x0071, device_type_revision = 1 } -- Oven TCC
      }
    },
    {
      endpoint_id = COOK_TOP_ENDPOINT,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", feature_map = 4 }, --OffOnly feature
      },
      device_types = {
        { device_type_id = 0x0078, device_type_revision = 1 } -- Cook Top
      }
    },
    {
      endpoint_id = COOK_SURFACE_ONE_ENDPOINT,
      clusters = {
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 2 },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0077, device_type_revision = 1 } -- Cook Surface
      }
    },
    {
      endpoint_id = COOK_SURFACE_TWO_ENDPOINT,
      clusters = {
        { cluster_id = clusters.TemperatureControl.ID,     cluster_type = "SERVER", feature_map = 2 },
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0077, device_type_revision = 1 } -- Cook Surface
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureControl.attributes.TemperatureSetpoint,
    clusters.TemperatureControl.attributes.MaxTemperature,
    clusters.TemperatureControl.attributes.MinTemperature,
    clusters.TemperatureControl.attributes.SelectedTemperatureLevel,
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels,
    clusters.OvenMode.attributes.CurrentMode,
    clusters.OvenMode.attributes.SupportedModes,
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

test.register_coroutine_test(
  "Assert component to endpoint map",
  function()
    local component_to_endpoint_map = mock_device:get_field("__component_to_endpoint_map")
    assert(component_to_endpoint_map["tccOne"] == OVEN_TCC_ONE_ENDPOINT, "Oven TCC One Endpoint must be 2")
    assert(component_to_endpoint_map["tccTwo"] == OVEN_TCC_TWO_ENDPOINT, "Oven TCC Two Endpoint must be 3")
    assert(component_to_endpoint_map["cookTop"] == COOK_TOP_ENDPOINT, "Cook Top Endpoint must be 4")
    assert(component_to_endpoint_map["cookSurfaceOne"] == COOK_SURFACE_ONE_ENDPOINT,
      "Cook Surface One Endpoint must be 5")
    assert(component_to_endpoint_map["cookSurfaceTwo"] == COOK_SURFACE_TWO_ENDPOINT,
      "Cook Surface Two Endpoint must be 6")
  end
)


test.register_message_test(
  "Oven TCC One: This test case checks for the following events:\n1. Oven supportedModes must be registered.\n2. Setting Oven mode should send appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OvenMode.attributes.SupportedModes:build_test_report_data(mock_device, OVEN_TCC_ONE_ENDPOINT,
          {
            clusters.OvenMode.types.ModeOptionStruct({
              ["label"] = "Grill",
              ["mode"] = 0,
              ["mode_tags"] = {
                clusters.OvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
              }
            }),
            clusters.OvenMode.types.ModeOptionStruct({
              ["label"] = "Pre Heat",
              ["mode"] = 1,
              ["mode_tags"] = {
                clusters.OvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
              }
            })
          }
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccOne",
        capabilities.mode.supportedModes({ "Grill", "Pre Heat" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccOne",
        capabilities.mode.supportedArguments({ "Grill", "Pre Heat" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "tccOne", command = "setMode", args = { "Grill" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OvenMode.commands.ChangeToMode(mock_device, OVEN_TCC_ONE_ENDPOINT, 0) --Index where Grill is stored)
      }
    }
  }
)

test.register_message_test(
  "First Oven TCC: MeasuredValue of TemperatureMeasurement clusters should be reported correctly.",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, OVEN_TCC_ONE_ENDPOINT, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccOne", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "First Oven TCC: Verify temperatureSetpoint command sends the appropriate commands.",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, OVEN_TCC_ONE_ENDPOINT, 12800) --128*C
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, OVEN_TCC_ONE_ENDPOINT, 20000) --200*C
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, OVEN_TCC_ONE_ENDPOINT, 13000) --130*C
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccOne", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=128.0,maximum=200.0, step = 0.1}, unit = "C"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccOne", capabilities.temperatureSetpoint.temperatureSetpoint({value = 130.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "tccOne", command = "setTemperatureSetpoint", args = {130.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, OVEN_TCC_ONE_ENDPOINT, 130 * 100, nil)
      }
    },
  }
)

test.register_message_test(
  "Oven TCC Two: This test case checks for the following events:\n1. Oven supportedModes must be registered.\n2. Setting Oven mode should send appropriate commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OvenMode.attributes.SupportedModes:build_test_report_data(mock_device, OVEN_TCC_TWO_ENDPOINT,
          {
            clusters.OvenMode.types.ModeOptionStruct({
              ["label"] = "Grill",
              ["mode"] = 0,
              ["mode_tags"] = {
                clusters.OvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 0 })
              }
            }),
            clusters.OvenMode.types.ModeOptionStruct({
              ["label"] = "Pre Heat",
              ["mode"] = 1,
              ["mode_tags"] = {
                clusters.OvenMode.types.ModeTagStruct({ ["mfg_code"] = 256, ["value"] = 1 })
              }
            })
          }
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccTwo",
        capabilities.mode.supportedModes({ "Grill", "Pre Heat" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccTwo",
        capabilities.mode.supportedArguments({ "Grill", "Pre Heat" }, { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "mode", component = "tccTwo", command = "setMode", args = { "Pre Heat" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OvenMode.commands.ChangeToMode(mock_device, OVEN_TCC_TWO_ENDPOINT, 1) --Index where Pre Heat is stored
      }
    }
  }
)

test.register_message_test(
  "Oven TCC Two: MeasuredValue of TemperatureMeasurement clusters should be reported correctly.",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, OVEN_TCC_TWO_ENDPOINT, 50*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccTwo", capabilities.temperatureMeasurement.temperature({ value = 50.0, unit = "C" }))
    }
  }
)

local utf1 = require "st.matter.data_types.UTF8String1"

test.register_message_test(
  "Second Oven TCC: TemperatureControl Supported Levels must be registered and setTemperatureLevel level command should send appropriate command",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.SupportedTemperatureLevels:build_test_report_data(mock_device, OVEN_TCC_TWO_ENDPOINT, {utf1("Level 1"), utf1("Level 2"), utf1("Level 3")})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("tccTwo", capabilities.temperatureLevel.supportedTemperatureLevels({"Level 1", "Level 2", "Level 3"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureLevel", component = "tccTwo", command = "setTemperatureLevel", args = {"Level 1"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.server.commands.SetTemperature(mock_device, OVEN_TCC_TWO_ENDPOINT, nil, 0) --0 is the index where Level1 is stored.
      }
    },
  }
)

test.register_message_test(
  "Cook Top: Off command should send appropriate commands",
  -- we do not test "on" command, as cook-top is supposed to have offOnly feature.
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "cookTop", command = "off", args = {} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.Off(mock_device, COOK_TOP_ENDPOINT)
      }
    }
  }
)

test.register_message_test(
  "Cook Surface One: TemperatureControl Supported Levels must be registered and setTemperatureLevel level command should send appropriate command",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.SupportedTemperatureLevels:build_test_report_data(mock_device, COOK_SURFACE_ONE_ENDPOINT, {utf1("Level 2"), utf1("Level 4"), utf1("Level 5")})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceOne", capabilities.temperatureLevel.supportedTemperatureLevels({"Level 2", "Level 4", "Level 5"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureLevel", component = "cookSurfaceOne", command = "setTemperatureLevel", args = {"Level 5"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.server.commands.SetTemperature(mock_device, COOK_SURFACE_ONE_ENDPOINT, nil, 2) -- 2 is the index where Level 5 is stored.
      }
    },
  }
)

test.register_message_test(
  "Cook Surface Two: TemperatureControl Supported Levels must be registered and setTemperatureLevel level command should send appropriate command",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.SupportedTemperatureLevels:build_test_report_data(mock_device, COOK_SURFACE_TWO_ENDPOINT, {utf1("Level 3"), utf1("Level 4"), utf1("Level 5")})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceTwo", capabilities.temperatureLevel.supportedTemperatureLevels({"Level 3", "Level 4", "Level 5"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureLevel", component = "cookSurfaceTwo", command = "setTemperatureLevel", args = {"Level 4"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.server.commands.SetTemperature(mock_device, COOK_SURFACE_TWO_ENDPOINT, nil, 1) -- 1 is the index where Level 4 is stored.
      }
    },
  }
)

test.register_message_test(
  "Cook Surface One: MeasuredValue of TemperatureMeasurement clusters should be reported correctly.",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, COOK_SURFACE_ONE_ENDPOINT, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceOne", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Cook Surface Two: MeasuredValue of TemperatureMeasurement clusters should be reported correctly.",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, COOK_SURFACE_TWO_ENDPOINT, 20*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceTwo", capabilities.temperatureMeasurement.temperature({ value = 20.0, unit = "C" }))
    }
  }
)

test.run_registered_tests()
