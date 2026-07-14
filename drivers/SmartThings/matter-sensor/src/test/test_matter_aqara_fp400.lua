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
    },
    device_types = {
      {device_type_id = 0x0107, device_type_revision = 1} -- Occupancy Sensor
    }
  },
  {
    endpoint_id = 2,
    clusters = {
      {cluster_id = clusters.IlluminanceMeasurement.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0106, device_type_revision = 1} -- Light Sensor
    }
  },
  {
    endpoint_id = 3,
    clusters = {
      {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0107, device_type_revision = 1} -- Occupancy Sensor
    }
  },
  {
    endpoint_id = 5,
    clusters = {
      {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
    },
    device_types = {
      {device_type_id = 0x0107, device_type_revision = 1} -- Occupancy Sensor
    }
  },
}

local enabled_optional_component_capability_pairs = {
  { "sensor1", { capabilities.presenceSensor.ID } },
  { "sensor3", { capabilities.presenceSensor.ID } }
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("aqara-fp400.yml",
    { enabled_optional_capabilities = enabled_optional_component_capability_pairs }
  ),
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
  local subscribe_request = subscribe_on_init(mock_device)
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Test profile change on doConfigure for FP400",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    -- When doConfigure completes successfully, the framework automatically provisions the device
    mock_device:expect_metadata_update({ profile = "aqara-fp400", optional_component_capabilities = enabled_optional_component_capability_pairs })
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
    mock_device:expect_metadata_update({ profile = "aqara-fp400", optional_component_capabilities = enabled_optional_component_capability_pairs })
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
  "Occupancy reports should generate correct presence messages",
  {
    -- from EP1
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
      message = mock_device:generate_test_message("main", capabilities.presenceSensor.presence("present"))
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
      message = mock_device:generate_test_message("main", capabilities.presenceSensor.presence("not present"))
    },
    -- from EP3
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
      message = mock_device:generate_test_message("sensor1", capabilities.presenceSensor.presence("present"))
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
      message = mock_device:generate_test_message("sensor1", capabilities.presenceSensor.presence("not present"))
    },
    -- from EP5
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 5, 1)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("sensor3", capabilities.presenceSensor.presence("present"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OccupancySensing.attributes.Occupancy:build_test_report_data(mock_device, 5, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("sensor3", capabilities.presenceSensor.presence("not present"))
    },
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
        clusters.IlluminanceMeasurement.attributes.MeasuredValue:build_test_report_data(mock_device, 2, 21370)
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

test.register_coroutine_test(
  "Test profile change on endpoints increment in infoChanged for FP400",
  function()
    local current_profile_id = mock_device.profile.id
    local incremented_matter_endpoints = matter_endpoints
    table.insert(incremented_matter_endpoints, {
      endpoint_id = 4,
      clusters = {
        {cluster_id = clusters.OccupancySensing.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0107, device_type_revision = 1} -- Occupancy Sensor
      }
    })
    local incremented_enabled_optional_component_capability_pairs = {
      { "sensor1", { capabilities.presenceSensor.ID } },
      { "sensor3", { capabilities.presenceSensor.ID } },
      { "sensor2", { capabilities.presenceSensor.ID } },
    }
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ endpoints = incremented_matter_endpoints }))
    mock_device:expect_metadata_update({ profile = "aqara-fp400", optional_component_capabilities = incremented_enabled_optional_component_capability_pairs })
    -- Ensure profile has not changed
    test.wait_for_events()
    assert(mock_device.profile.id == current_profile_id, "Profile should not change on infoChanged")
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test profile change on endpoints decrement in infoChanged for FP400",
  function()
    local current_profile_id = mock_device.profile.id
    local decremented_matter_endpoints = matter_endpoints
    table.remove(decremented_matter_endpoints, 4) -- remove EP3
    local decremented_enabled_optional_component_capability_pairs = {
      { "sensor3", { capabilities.presenceSensor.ID } },
      { "sensor2", { capabilities.presenceSensor.ID } },
    }
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ endpoints = decremented_matter_endpoints }))
    mock_device:expect_metadata_update({ profile = "aqara-fp400", optional_component_capabilities = decremented_enabled_optional_component_capability_pairs })
    -- Ensure profile has not changed
    test.wait_for_events()
    assert(mock_device.profile.id == current_profile_id, "Profile should not change on infoChanged")
  end,
  {
    min_api_version = 17
  }
)

test.run_registered_tests()
