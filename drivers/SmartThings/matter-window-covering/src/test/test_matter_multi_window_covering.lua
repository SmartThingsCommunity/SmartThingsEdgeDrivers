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

local CHILD_DEVICE_MAP = {
  {key = 2, ep = 6},
  {key = 3, ep = 7},
  {key = 4, ep = 8},
  {key = 5, ep = 9},
  {key = 6, ep = 10},
  {key = 7, ep = 11}
}

local mock_parent_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    matter_version = {software = 1},
    endpoints = {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          device_type_id = 0x0016, device_type_revision = 1, -- RootNode
        }
      },
      {
        endpoint_id = 5,
        clusters = {
          {
            cluster_id = WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
      {
        endpoint_id = CHILD_DEVICE_MAP[1].ep,
        clusters = {
          {
            cluster_id = WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
      {
        endpoint_id = CHILD_DEVICE_MAP[2].ep,
        clusters = {
          {
            cluster_id = WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
      {
        endpoint_id = CHILD_DEVICE_MAP[3].ep,
        clusters = {
          {
            cluster_id = WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
      {
        endpoint_id = CHILD_DEVICE_MAP[4].ep,
        clusters = {
          {
            cluster_id = WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
      {
        endpoint_id = CHILD_DEVICE_MAP[5].ep,
        clusters = {
          {
            cluster_id = WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
      {
        endpoint_id = CHILD_DEVICE_MAP[6].ep,
        clusters = {
          {
            cluster_id = WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
    },
  }
)

local mock_child_device = {
  test.mock_device.build_test_child_device({
    type = "EDGE_CHILD",
    label = string.format("%s %d", "Window Covering", CHILD_DEVICE_MAP[1].key),
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    device_network_id = string.format("%s:%02X", mock_parent_device.id, CHILD_DEVICE_MAP[1].key),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%d", CHILD_DEVICE_MAP[1].ep)
  }),
  test.mock_device.build_test_child_device({
    type = "EDGE_CHILD",
    label = string.format("%s %d", "Window Covering", CHILD_DEVICE_MAP[2].key),
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    device_network_id = string.format("%s:%02X", mock_parent_device.id, CHILD_DEVICE_MAP[2].key),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%d", CHILD_DEVICE_MAP[2].ep)
  }),
  test.mock_device.build_test_child_device({
    type = "EDGE_CHILD",
    label = string.format("%s %d", "Window Covering", CHILD_DEVICE_MAP[3].key),
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    device_network_id = string.format("%s:%02X", mock_parent_device.id, CHILD_DEVICE_MAP[3].key),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%d", CHILD_DEVICE_MAP[3].ep)
  }),
  test.mock_device.build_test_child_device({
    type = "EDGE_CHILD",
    label = string.format("%s %d", "Window Covering", CHILD_DEVICE_MAP[4].key),
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    device_network_id = string.format("%s:%02X", mock_parent_device.id, CHILD_DEVICE_MAP[4].key),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%d", CHILD_DEVICE_MAP[4].ep)
  }),
  test.mock_device.build_test_child_device({
    type = "EDGE_CHILD",
    label = string.format("%s %d", "Window Covering", CHILD_DEVICE_MAP[5].key),
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    device_network_id = string.format("%s:%02X", mock_parent_device.id, CHILD_DEVICE_MAP[5].key),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%d", CHILD_DEVICE_MAP[5].ep)
  }),
  test.mock_device.build_test_child_device({
    type = "EDGE_CHILD",
    label = string.format("%s %d", "Window Covering", CHILD_DEVICE_MAP[6].key),
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    device_network_id = string.format("%s:%02X", mock_parent_device.id, CHILD_DEVICE_MAP[6].key),
    parent_device_id = mock_parent_device.id,
    parent_assigned_child_key = string.format("%d", CHILD_DEVICE_MAP[6].ep)
  })
}

local CLUSTER_SUBSCRIBE_LIST = {
  clusters.LevelControl.server.attributes.CurrentLevel,
  WindowCovering.server.attributes.CurrentPositionLiftPercent100ths,
  WindowCovering.server.attributes.CurrentPositionTiltPercent100ths,
  WindowCovering.server.attributes.TargetPositionLiftPercent100ths,
  WindowCovering.server.attributes.TargetPositionTiltPercent100ths,
  WindowCovering.server.attributes.OperationalStatus,
  clusters.PowerSource.server.attributes.BatPercentRemaining
}

local function set_preset(device)
  test.socket.capability:__expect_send(
    device:generate_test_message(
      "main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}})
    )
  )
  test.socket.capability:__expect_send(
    device:generate_test_message(
      "main", capabilities.windowShadePreset.position(50, {visibility = {displayed = false}})
    )
  )
end

local function test_init()
  test.mock_device.add_test_device(mock_parent_device)
  for i = 1, #mock_child_device do
    test.mock_device.add_test_device(mock_child_device[i])
  end
  test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_parent_device:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )
  test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "init" })
  set_preset(mock_parent_device)
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_parent_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_parent_device)) end
  end
  test.socket.matter:__expect_send({mock_parent_device.id, subscribe_request})
  for _, child in ipairs(CHILD_DEVICE_MAP) do
    mock_parent_device:expect_device_create({
      type = "EDGE_CHILD",
      label = string.format("%s %d", "Window Covering", child.key),
      profile = "window-covering",
      parent_device_id = mock_parent_device.id,
      parent_assigned_child_key = string.format("%d", child.ep)
    })
  end

  test.socket.device_lifecycle:__queue_receive({ mock_parent_device.id, "doConfigure" })
  mock_parent_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.socket.matter:__expect_send({mock_parent_device.id, clusters.PowerSource.attributes.AttributeList:read()})
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'open' capability emission if lift position is 100",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(100)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.open()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'closed' capability emission if lift position is 0",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 10000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(0)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.closed()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'partially open' capability emission if lift position is 50",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(50)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.partially_open()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'partially open' capability emission if tilt position is between 1-100",
  function()
    for i = 1, #mock_child_device do
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, ((100 - 15) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(15)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.partially_open()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Unknown WindowCovering OperationalStatus state triggers 'unknown' capability emission",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 99),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.unknown()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Opening WindowCovering OperationalStatus state triggers 'closing' capability emission",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 2),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.closing()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Closing WindowCovering OperationalStatus state triggers 'opening' capability emission",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 1),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.opening()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering CurrentPositionLiftPercent100ths triggers appropriate capability emission",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 10000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(0)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(100)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, ((100 - 25) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(25)
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering CurrentPositionTiltPercent100ths triggers appropriate capability emission",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 10000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, ((100 - 15) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(15)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, ((100 - 65) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(65)
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering TargetPositionLiftPercent100ths sets field appropriately",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.TargetPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.wait_for_events()
      assert(mock_child_device[i]:get_field("__target_lift_percent") == 50)
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering TargetPositionTiltPercent100ths sets field appropriately",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.TargetPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.wait_for_events()
      assert(mock_child_device[i]:get_field("__target_tilt_percent") == 50)
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering TargetPositionLiftPercent100ths triggers operational status update when appropriate",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, ((100 - 65) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(65)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.partially_open()
        )
      )
    end
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering TargetPositionTiltPercent100ths triggers operational status update when appropriate",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, ((100 - 65) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(65)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.partially_open()
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Open capability command triggers appropriate Matter command",
  function()
    for i = 1, #mock_child_device do
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "windowShade", component = "main", command = "open", args = {}},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.UpOrOpen(mock_parent_device, CHILD_DEVICE_MAP[i].ep)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Close capability command triggers appropriate Matter command",
  function()
    for i = 1, #mock_child_device do
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "windowShade", component = "main", command = "close", args = {}},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.DownOrClose(mock_parent_device, CHILD_DEVICE_MAP[i].ep)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Pause capability command triggers appropriate Matter command",
  function()
    for i = 1, #mock_child_device do
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "windowShade", component = "main", command = "pause", args = {}},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.StopMotion(mock_parent_device, CHILD_DEVICE_MAP[i].ep)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Cached target lift/tilt position timeouts trigger one operational status update",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 50 * 100
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(50)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(50)
        )
      )
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "windowShade", component = "main", command = "open", args = {}},
        }
      )
      test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
      test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.UpOrOpen(mock_parent_device, CHILD_DEVICE_MAP[i].ep)}
      )

      test.wait_for_events()
      test.mock_time.advance_time(120)

      test.socket.capability:__expect_send({
          mock_child_device[i].id, { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } },
        }
      )
      test.wait_for_events()
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Cached target lift timeout triggers one operational status update if tilt target and idle state are first reached appropriately",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(50)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(50)
        )
      )
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "windowShade", component = "main", command = "open", args = {}},
        }
      )
      -- two timers are made when open is called
      test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
      test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.UpOrOpen(mock_parent_device, CHILD_DEVICE_MAP[i].ep)}
      )

      -- ensure target state is cached before queueing responses
      test.wait_for_events()
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
          ),
        }
      )

      -- advance time to trigger the single remaining timer
      test.wait_for_events()
      test.mock_time.advance_time(120)
      test.socket.capability:__expect_send({
          mock_child_device[i].id, { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } },
        }
      )
      test.wait_for_events()
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test("SetShadeLevel capability command triggers appropriate Matter command",
function()
    for i = 1, #mock_child_device do
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 20 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 8000)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test("SetShadeTiltLevel capability command triggers appropriate Matter command",
function()
    for i = 1, #mock_child_device do
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 60 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 4000)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

--test battery
test.register_coroutine_test(
  "Battery percent reports should generate correct messages",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 150
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.battery.battery(math.floor(150/2.0+0.5))
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle preset commands",
  function()
    for i = 1, #mock_child_device do
      local PRESET_LEVEL = 30
      test.socket.capability:__queue_receive({
        mock_child_device[i].id,
        {capability = "windowShadePreset", component = "main", command = "setPresetPosition", args = { PRESET_LEVEL }},
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadePreset.position(PRESET_LEVEL)
        )
      )
      test.socket.capability:__queue_receive({
        mock_child_device[i].id,
        {capability = "windowShadePreset", component = "main", command = "presetPosition", args = {}},
      })
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, (100 - PRESET_LEVEL) * 100)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test profile change to window-covering-battery when battery percent remaining attribute (attribute ID 12) is available",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, {uint32(12)})
        }
      )
      mock_child_device[i]:expect_metadata_update({ profile = "window-covering-tilt-battery" })
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test that profile is not changed to window-covering-battery when battery percent remaining attribute (attribute ID 12) is not available",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_child_device[i], CHILD_DEVICE_MAP[i].ep, {uint32(10)})
        }
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade lift operates as expected when opening and closing",
  function()
    for i = 1, #mock_child_device do
      test.socket.device_lifecycle():__queue_receive(mock_child_device[i]:generate_info_changed({ preferences = { reverse = "true" } }))
      test.wait_for_events()
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 100 * 100
        )
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(0)
        )
      )
      test.wait_for_events()
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
        )
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.open()
        )
      )
      test.wait_for_events()
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
        )
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(100)
        )
      )
      test.wait_for_events()
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
        )
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.closed()
        )
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive({
        mock_child_device[i].id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 85 }},
      })
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 1500)}
      )
      test.socket.capability:__queue_receive({
        mock_child_device[i].id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 100 }},
      })
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 0)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade tilt operates as expected when opening and closing",
  function()
    for i = 1, #mock_child_device do
      test.socket.device_lifecycle():__queue_receive(mock_child_device[i]:generate_info_changed({ preferences = { reverse = "true" } }))
      test.wait_for_events()
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 100 * 100
        )
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
        )
      )
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
        )
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.open()
        )
      )
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
        )
      })
      test.socket.matter:__queue_receive({
        mock_child_device[i].id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(
          mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 0
        )
      })
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
        )
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.closed()
        )
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive({
        mock_child_device[i].id,
        {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 15 }},
      })
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 8500)}
      )
      test.socket.capability:__queue_receive({
        mock_child_device[i].id,
        {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 0 }},
      })
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 10000)}
      )
    end
  end,
  {
     min_api_version = 17
  }
)

-- -- stepShadeLevel tests

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - step up",
  function()
    for i = 1, #mock_child_device do
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 9000)}
      )
    end
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - step down",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(50)
        )
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 7000)}
      )
    end
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - continuous step with target tracking",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 7000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(30)
        )
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 6000)}
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 5000)}
      )
    end
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - target reached clears target marker",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 5000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(50)
        )
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 4000)}
      )
      test.wait_for_events()
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 4000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(60)
        )
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShade.windowShade.partially_open()
        )
      )
    end
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - step up to maximum (100)",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 500
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(95)
        )
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 0)}
      )
    end
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - step down to minimum (0)",
  function()
    for i = 1, #mock_child_device do
      test.socket.matter:__queue_receive(
        {
          mock_child_device[i].id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_child_device[i], CHILD_DEVICE_MAP[i].ep, 9500
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_child_device[i]:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(5)
        )
      )
      test.wait_for_events()
      test.socket.capability:__queue_receive(
        {
          mock_child_device[i].id,
          {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -10 }},
        }
      )
      test.socket.matter:__expect_send(
        {mock_parent_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_parent_device, CHILD_DEVICE_MAP[i].ep, 10000)}
      )
    end
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
