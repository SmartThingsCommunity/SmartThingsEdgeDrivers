-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"

clusters.ClosureControl = require "embedded_clusters.ClosureControl"

local mock_device = test.mock_device.build_test_matter_device(
  {
    label = "Matter Closure",
    profile = t_utils.get_profile_definition("covering.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    matter_version = {hardware = 1, software = 1},
    endpoints = {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
        }
      },
      {
        endpoint_id = 10,
        clusters = {
          {
            cluster_id = clusters.ClosureControl.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
        device_types = {
          {device_type_id = 0x0230, device_type_revision = 1} -- Closure
        }
      },
    },
  }
)

local CLUSTER_SUBSCRIBE_LIST = {
  clusters.ClosureControl.attributes.MainState,
  clusters.ClosureControl.attributes.OverallCurrentState,
  clusters.ClosureControl.attributes.OverallTargetState,
}

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })

  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  subscribe_request:merge(clusters.Descriptor.attributes.TagList:subscribe(mock_device))
  subscribe_request:merge(clusters.PowerSource.attributes.AttributeList:subscribe(mock_device))
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

local function update_profile()
  test.socket.matter:__queue_receive({mock_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(
    mock_device, 10, {uint32(clusters.PowerSource.attributes.BatPercentRemaining.ID)}
  )})
  test.socket.matter:__queue_receive({mock_device.id, clusters.Descriptor.attributes.TagList:build_test_report_data(
    mock_device, 10, {clusters.Global.types.SemanticTagStruct({mfg_code = 0x00, namespace_id = 0x44, tag = 0x00, name = "Covering"})  }
  )})
  mock_device:expect_metadata_update({ profile = "covering", optional_component_capabilities = {{"main", {"battery"}}} })
  test.wait_for_events()
  local updated_device_profile = t_utils.get_profile_definition("covering.yml", {enabled_optional_capabilities = {{"main", {"battery"}}}}
  )
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = updated_device_profile }))
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  subscribe_request:merge(clusters.PowerSource.server.attributes.BatPercentRemaining:subscribe(mock_device))
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed following lift position update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_device, 10, clusters.ClosureControl.types.MainStateEnum.MOVING),
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallTargetState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallTargetStateStruct({
          position = clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
  end
)

test.run_registered_tests()
