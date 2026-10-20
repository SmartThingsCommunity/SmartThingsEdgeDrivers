-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local version = require "version"
if version.api < 16 then
  clusters.Descriptor = require "embedded_clusters.Descriptor"
end

local WindowCovering = clusters.WindowCovering

test.disable_startup_messages()

local ENDPOINT_MAP = {5, 6, 7, 8, 9, 10, 11}
local mock_device = test.mock_device.build_test_matter_device(
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
        endpoint_id = ENDPOINT_MAP[1],
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
        endpoint_id = ENDPOINT_MAP[2],
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
        endpoint_id = ENDPOINT_MAP[3],
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
        endpoint_id = ENDPOINT_MAP[4],
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
        endpoint_id = ENDPOINT_MAP[5],
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
        endpoint_id = ENDPOINT_MAP[6],
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
        endpoint_id = ENDPOINT_MAP[7],
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
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  set_preset(mock_device)
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  for i, ep in ipairs(ENDPOINT_MAP) do
    mock_device:expect_device_create({
      type = "EDGE_CHILD",
      label = string.format("%s %d", "Window Covering", i),
      profile = "window-covering",
      parent_device_id = mock_device.id,
      parent_assigned_child_key = string.format("%d", ENDPOINT_MAP[i])
    })
    if i == 1 then
      test.socket.matter:__expect_send({mock_device.id, clusters.PowerSource.attributes.AttributeList:read()})
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'open' capability emission if lift position is 100", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_device, ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(100)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "Idle WindowCovering OperationalStatus state triggers 'closed' capability emission if lift position is 0", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_device, ep, 10000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(0)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "Idle WindowCovering OperationalStatus state triggers 'partially open' capability emission if lift position is 50", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_device, ep, 5000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(50)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "Idle WindowCovering OperationalStatus state triggers 'partially open' capability emission if tilt position is between 1-100", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_device, ep, ((100 - 15) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(15)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, ep, 0),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "Unknown WindowCovering OperationalStatus state triggers 'unknown' capability emission", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, ep, 99),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "Opening WindowCovering OperationalStatus state triggers 'closing' capability emission", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, ep, 2),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "Closing WindowCovering OperationalStatus state triggers 'opening' capability emission", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, ep, 1),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "WindowCovering CurrentPositionLiftPercent100ths triggers appropriate capability emission", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_device, ep, 10000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(0)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_device, ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(100)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
            mock_device, ep, ((100 - 25) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
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
  "WindowCovering CurrentPositionTiltPercent100ths triggers appropriate capability emission", function()
    for _, ep in ipairs(ENDPOINT_MAP) do
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_device, ep, 10000
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_device, ep, 0
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_device, ep, ((100 - 15) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(15)
        )
      )
      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
            mock_device, ep, ((100 - 65) *100)
          ),
        }
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(
          "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(65)
        )
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
