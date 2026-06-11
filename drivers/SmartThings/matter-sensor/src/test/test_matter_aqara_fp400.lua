-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"

local matter_endpoints = {
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
      {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
      {cluster_id = clusters.IlluminanceMeasurement.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0107, device_type_revision = 1} -- Occupancy Sensor
    }
  }
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("aqara-fp400.yml"),
  manufacturer_info = {
    vendor_id = 0x115F,
    product_id = 0x2009,
  },
  endpoints = matter_endpoints
})

local function subscribe_on_init(dev)
  local subscribe_request = clusters.OccupancySensing.attributes.Occupancy:subscribe(dev)
  subscribe_request:merge(clusters.IlluminanceMeasurement.attributes.MeasuredValue:subscribe(dev))
  return subscribe_request
end

local function test_init()
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = subscribe_on_init(mock_device)
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test no profile change on doConfigure for FP400",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    -- The FP400 sub-driver overrides doConfigure to be a no-op
    -- When doConfigure completes successfully, the framework automatically provisions the device
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test no profile change on driverSwitched for FP400",
  function()
    local current_profile = mock_device.profile.id
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
    -- The FP400 sub-driver overrides driverSwitched to only update provisioning state
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    -- Ensure profile has not changed
    test.wait_for_events()
    assert(mock_device.profile.id == current_profile, "Profile should not change on driverSwitched")
  end,
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Occupancy reports should generate correct motion messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 1, 1)
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
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 1, 0)
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

test.register_message_test(
  "Illuminance reports should generate correct messages",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 1, 21370)
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

test.run_registered_tests()
