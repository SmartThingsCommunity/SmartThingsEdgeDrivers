local test = require "integration_test"
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

test.add_package_capability("cookTime.yml")
test.add_package_capability("fanMode.yml")

local COOK_TOP_ENDPOINT = 1
local COOK_SURFACE_ONE_ENDPOINT = 2
local COOK_SURFACE_TWO_ENDPOINT = 3

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("cook-surface-one-tn-cook-surface-two-tl.yml"), --on an actual device we would switch to this over doConfigure.
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
      endpoint_id = COOK_TOP_ENDPOINT,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", feature_map = 4}, --OffOnly feature
      },
      device_types = {
        { device_type_id = 0x0078, device_type_revision = 1 } -- Cook Top
      }
    },
    {
      endpoint_id = COOK_SURFACE_ONE_ENDPOINT,
      clusters = {
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 1 }, --Temperature Number
        { cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"}, --Temperature Level
      },
      device_types = {
        { device_type_id = 0x0077, device_type_revision = 1 } -- Cook Surface
      }
    },
    {
      endpoint_id = COOK_SURFACE_TWO_ENDPOINT,
      clusters = {
        { cluster_id = clusters.TemperatureControl.ID, cluster_type = "SERVER", feature_map = 2},
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
    clusters.TemperatureControl.attributes.SupportedTemperatureLevels
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
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
    "Verify device profile update",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure"})
      mock_device:expect_metadata_update({ profile = "cook-surface-one-tn-cook-surface-two-tl" })
      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Assert component to endpoint map",
    function()
      local component_to_endpoint_map = mock_device:get_field("__component_to_endpoint_map")
      assert(component_to_endpoint_map["cookSurfaceOne"] == COOK_SURFACE_ONE_ENDPOINT, "Cook Surface One Endpoint must be 2")
      assert(component_to_endpoint_map["cookSurfaceTwo"] == COOK_SURFACE_TWO_ENDPOINT, "Cook Surface Two Endpoint must be 3")
    end
)

test.register_message_test(
  "Off command should send appropriate commands",
  -- we do not test "on" command, as cook-top is supposed to have offOnly feature.
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "off", args = {} }
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
  "Cook Surface One: Veirfy temperatureSetpoint command sends the appropriate commands.",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MinTemperature:build_test_report_data(mock_device, COOK_SURFACE_ONE_ENDPOINT, 0)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.MaxTemperature:build_test_report_data(mock_device, COOK_SURFACE_ONE_ENDPOINT, 10000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.TemperatureSetpoint:build_test_report_data(mock_device, COOK_SURFACE_ONE_ENDPOINT, 9000)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceOne", capabilities.temperatureSetpoint.temperatureSetpointRange({value = {minimum=0.0,maximum=100.0}, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceOne", capabilities.temperatureSetpoint.temperatureSetpoint({value = 90.0, unit = "C"}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureSetpoint", component = "cookSurfaceOne", command = "setTemperatureSetpoint", args = {40.0}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.commands.SetTemperature(mock_device, COOK_SURFACE_ONE_ENDPOINT, 40 * 100, nil)
      }
    },
  }
)

local utf1 = require "st.matter.data_types.UTF8String1"

test.register_message_test(
  "Cook Surface Two: TemperatureControl Supported Levels must be registered and setTemperatureLevel level command should send appropriate command",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureControl.attributes.SupportedTemperatureLevels:build_test_report_data(mock_device, COOK_SURFACE_TWO_ENDPOINT, {utf1("Level 1"), utf1("Level 2"), utf1("Level 3")})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceTwo", capabilities.temperatureLevel.supportedTemperatureLevels({"Level 1", "Level 2", "Level 3"}, {visibility = {displayed = false}}))
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "temperatureLevel", component = "cookSurfaceTwo", command = "setTemperatureLevel", args = {"Level 1"}}
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.TemperatureControl.server.commands.SetTemperature(mock_device, COOK_SURFACE_TWO_ENDPOINT, nil, 0) --0 is the index where Level1 is stored.
      }
    },
  }
)

test.register_message_test(
  "MeasuredValue of TemperatureMeasurement clusters should be reported correctly.",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 2, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("cookSurfaceOne", capabilities.temperatureMeasurement.temperature({ value = 40.0, unit = "C" }))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 3, 20*100)
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