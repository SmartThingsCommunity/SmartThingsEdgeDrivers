-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"

clusters.ClosureControl = require "embedded_clusters.ClosureControl"
clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"

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
          {cluster_id = clusters.Descriptor.ID, cluster_type = "SERVER", feature_map = 0},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
        device_types = {
          {device_type_id = 0x0230, device_type_revision = 1} -- Closure
        }
      },
      {
        endpoint_id = 11,
        clusters = {
          {
            cluster_id = clusters.ClosureDimension.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 0,
          },
        },
        device_types = {
          {device_type_id = 0x0231, device_type_revision = 1} -- ClosureDimension
        }
      },
      {
        endpoint_id = 12,
        clusters = {
          {
            cluster_id = clusters.ClosureDimension.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 0,
          },
        },
        device_types = {
          {device_type_id = 0x0231, device_type_revision = 1} -- ClosureDimension
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
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.matter:__expect_send({mock_device.id, clusters.Descriptor.attributes.TagList:read(mock_device, 10)})
  test.socket.matter:__expect_send({mock_device.id, clusters.PowerSource.attributes.AttributeList:read(mock_device, 10)})
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
  mock_device:expect_metadata_update({
    profile = "covering",
    optional_component_capabilities = {
      {"main", {"battery"}},
      {"windowShade1", {"windowShadeLevel"}},
      {"windowShade2", {"windowShadeLevel"}},
    }
  })
  test.wait_for_events()
  local updated_device_profile = t_utils.get_profile_definition("covering.yml", {
    enabled_optional_capabilities = {
      {"main", {"battery"}},
      {"windowShade1", {"windowShadeLevel"}},
      {"windowShade2", {"windowShadeLevel"}},
    }
  })
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = updated_device_profile }))
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  subscribe_request:merge(clusters.PowerSource.server.attributes.BatPercentRemaining:subscribe(mock_device))
  subscribe_request:merge(clusters.ClosureDimension.attributes.CurrentState:subscribe(mock_device))
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

test.register_coroutine_test(
  "windowShade closed following MainState and OverallTargetState update", function()
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

test.register_coroutine_test(
  "windowShade opening following MainState and OverallTargetState update", function()
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
          position = clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
  end
)

test.register_coroutine_test(
  "windowShade closed following OverallCurrentState FULLY_CLOSED", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
  end
)

test.register_coroutine_test(
  "windowShade open following OverallCurrentState FULLY_OPENED", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED,
          latch = true,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
  end
)

test.register_coroutine_test(
  "windowShade partially_open following OverallCurrentState PARTIALLY_OPENED", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.PARTIALLY_OPENED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
  end
)

test.register_coroutine_test(
  "windowShade state transitions from closing to closed", function()
    update_profile()
    test.wait_for_events()
    -- device starts moving toward closed
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
    test.wait_for_events()
    -- device stops and reports fully closed
    -- MainState STOPPED with no current position cached yet. no capability event emitted
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_device, 10, clusters.ClosureControl.types.MainStateEnum.STOPPED),
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
  end
)

test.register_coroutine_test(
  "windowShade close command sends ClosureControl MoveTo FULLY_CLOSED", function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShade", component = "main", command = "close", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureControl.server.commands.MoveTo(
        mock_device, 10, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED
      )
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "windowShade open command sends ClosureControl MoveTo FULLY_OPEN", function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShade", component = "main", command = "open", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureControl.server.commands.MoveTo(
        mock_device, 10, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN
      )
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "windowShade pause command sends ClosureControl Stop", function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShade", component = "main", command = "pause", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureControl.server.commands.Stop(mock_device, 10)
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Battery percentage reported correctly for closure device", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 10, 150)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5)))
    )
  end
)

test.register_coroutine_test(
  "setShadeLevel on windowShade1 sends SetTarget to endpoint 11", function()
    update_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "windowShade1", command = "setShadeLevel", args = {75}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureDimension.server.commands.SetTarget(mock_device, 11, 75 * 100)
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "setShadeLevel on windowShade2 sends SetTarget to endpoint 12", function()
    update_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "windowShade2", command = "setShadeLevel", args = {40}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureDimension.server.commands.SetTarget(mock_device, 12, 40 * 100)
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState on endpoint 11 emits shadeLevel on windowShade1", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 11,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 6000,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade1", capabilities.windowShadeLevel.shadeLevel(60))
    )
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState on endpoint 12 emits shadeLevel on windowShade2", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 12,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 2500,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade2", capabilities.windowShadeLevel.shadeLevel(25))
    )
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState with closed position emits shadeLevel 0", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 11,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 0,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade1", capabilities.windowShadeLevel.shadeLevel(0))
    )
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState with full-open position emits shadeLevel 100", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 11,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 10000,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade1", capabilities.windowShadeLevel.shadeLevel(100))
    )
  end
)

test.run_registered_tests()
