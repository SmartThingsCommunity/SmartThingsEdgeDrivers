-- Copyright © 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-color-level-illuminance-motion.yml"),
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
        {device_type_id = 0x0016, device_type_revision = 1}  -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.OnOff.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 0, --u32 bitmap
        },
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x010C, device_type_revision = 1}  -- ColorTemperatureLight
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.IlluminanceMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0106, device_type_revision = 1}  -- LightSensor
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0107, device_type_revision = 1}  -- OccupancySensor
      }
    }
  }
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local switch_fields = require "switch_utils.fields"

test.register_coroutine_test(
  "doConfigure lifecycle event should not re-configure the device profile",
  function ()
    mock_device:set_field(switch_fields.profiling_data.BATTERY_SUPPORT, false, {persist = true})
    mock_device:set_field(switch_fields.profiling_data.POWER_TOPOLOGY, false, {persist = true})
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.matter:__expect_send({mock_device.id, clusters.LevelControl.attributes.Options:write(mock_device, 1, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
    test.socket.matter:__expect_send({mock_device.id, clusters.ColorControl.attributes.Options:write(mock_device, 1, clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "init should cause device to subscribe to all appropriate clusters", function()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.CurrentHue,
    clusters.ColorControl.attributes.CurrentSaturation,
    clusters.ColorControl.attributes.CurrentX,
    clusters.ColorControl.attributes.CurrentY,
    clusters.ColorControl.attributes.ColorMode,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    clusters.IlluminanceMeasurement.attributes.MeasuredValue,
    clusters.OccupancySensing.attributes.Occupancy
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})
   end,
   {
     min_api_version = 17
   }
)

test.register_message_test(
  "Illuminance reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.IlluminanceMeasurement.server.attributes.MeasuredValue:build_test_report_data(mock_device, 2, 21370)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 137 }))
    }
  },
  {
     min_api_version = 17
  }
)

test.register_message_test(
  "Occupancy reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 3, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.active())
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 3, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    }
  },
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
