-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"
local clusters = require "st.matter.clusters"
local version = require "version"
if version.api < 16 then
  clusters.Descriptor = require "embedded_clusters.Descriptor"
end

local matter_child = require "st.matter.child"
local matter_device = require "st.matter.device"
matter_child.MatterChildDevice.endpoint_to_component = matter_device.MatterDevice.endpoint_to_component

local WindowCovering = clusters.WindowCovering

test.disable_startup_messages()

-- A device with a single battery on its own endpoint, shared by two window coverings.
-- The battery belongs to the parent device only; the child must not get a battery.
local ROOT_EP = 0
local POWER_SOURCE_EP = 1
local PARENT_WC_EP = 2
local CHILD_WC_EP = 3

local mock_parent_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("window-covering-battery.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    matter_version = {software = 1},
    endpoints = {
      {
        endpoint_id = ROOT_EP,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          device_type_id = 0x0016, device_type_revision = 1, -- RootNode
        }
      },
      {
        endpoint_id = POWER_SOURCE_EP,
        clusters = {
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
      {
        endpoint_id = PARENT_WC_EP,
        clusters = {
          {cluster_id = WindowCovering.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 1},
        },
      },
      {
        endpoint_id = CHILD_WC_EP,
        clusters = {
          {cluster_id = WindowCovering.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 1},
        },
      },
    },
  }
)

local mock_child_device = test.mock_device.build_test_child_device({
  type = "EDGE_CHILD",
  label = "Window Covering 2",
  profile = t_utils.get_profile_definition("window-covering.yml"),
  device_network_id = string.format("%s:%02X", mock_parent_device.id, 2),
  parent_device_id = mock_parent_device.id,
  parent_assigned_child_key = string.format("%d", CHILD_WC_EP)
})

local CLUSTER_SUBSCRIBE_LIST = {
  WindowCovering.server.attributes.OperationalStatus,
  WindowCovering.server.attributes.CurrentPositionLiftPercent100ths,
  WindowCovering.server.attributes.TargetPositionLiftPercent100ths,
  clusters.PowerSource.server.attributes.BatPercentRemaining
}

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  test.mock_device.add_test_device(mock_child_device)
  test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_parent_device:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )
  test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "init" })
  test.socket.capability:__expect_send(
    mock_parent_device:generate_test_message(
      "main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}})
    )
  )
  test.socket.capability:__expect_send(
    mock_parent_device:generate_test_message(
      "main", capabilities.windowShadePreset.position(50, {visibility = {displayed = false}})
    )
  )
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_parent_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_parent_device)) end
  end
  test.socket.matter:__expect_send({mock_parent_device.id, subscribe_request})

  mock_parent_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Window Covering 2",
    profile = "window-covering",
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%d", CHILD_WC_EP)
  })
  test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "doConfigure" })
  mock_parent_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.socket.matter:__expect_send({mock_parent_device.id, clusters.PowerSource.attributes.AttributeList:read()})
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Battery percent report on the power source endpoint is emitted on the parent only",
  function()
    test.socket.matter:__queue_receive({
      mock_parent_device.id,
      clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
        mock_parent_device, POWER_SOURCE_EP, 150
      )
    })
    test.socket.capability:__expect_send(
      mock_parent_device:generate_test_message("main", capabilities.battery.battery(75))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Only the parent is re-profiled with battery percentage when BatPercentRemaining is supported",
  function()
    test.socket.matter:__queue_receive({
      mock_parent_device.id,
      clusters.PowerSource.attributes.AttributeList:build_test_report_data(
        mock_parent_device, POWER_SOURCE_EP, {uint32(12)}
      )
    })
    mock_parent_device:expect_metadata_update({ profile = "window-covering-battery" })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Only the parent is re-profiled with battery level when BatChargeLevel is supported",
  function()
    test.socket.matter:__queue_receive({
      mock_parent_device.id,
      clusters.PowerSource.attributes.AttributeList:build_test_report_data(
        mock_parent_device, POWER_SOURCE_EP, {uint32(14)}
      )
    })
    mock_parent_device:expect_metadata_update({ profile = "window-covering-batteryLevel" })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Window covering reports still route to the child and the parent with a separate battery endpoint",
  function()
    test.socket.matter:__queue_receive({
      mock_parent_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_parent_device, CHILD_WC_EP, 2000
      )
    })
    test.socket.capability:__expect_send(
      mock_child_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(80))
    )
    test.socket.matter:__queue_receive({
      mock_parent_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_parent_device, PARENT_WC_EP, 4000
      )
    })
    test.socket.capability:__expect_send(
      mock_parent_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(60))
    )
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
