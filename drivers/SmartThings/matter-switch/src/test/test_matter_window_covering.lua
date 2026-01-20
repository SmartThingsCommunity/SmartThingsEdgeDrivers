-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"

local WindowCovering = clusters.WindowCovering

local mock_device = test.mock_device.build_test_matter_device(
  {
    label = "Matter Window Covering",
    profile = t_utils.get_profile_definition("window-covering-modular.yml"),
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
            cluster_id = clusters.WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
        device_types = {
          {device_type_id = 0x0202, device_type_revision = 1} -- WindowCovering
        }
      },
      {
        endpoint_id = 20,
        clusters = {
          {
            cluster_id = clusters.WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          }
        },
        device_types = {
          {device_type_id = 0x0202, device_type_revision = 1} -- WindowCovering
        }
      },
    },
  }
)

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("window-covering-modular.yml"),
  device_network_id = string.format("%s:%d", mock_device.id, 20),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%d", 20)
})

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

local subscribe_request

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
  set_preset(mock_device)

  subscribe_request = WindowCovering.server.attributes.OperationalStatus:subscribe(mock_device)
  subscribe_request:merge(clusters.PowerSource.server.attributes.AttributeList:subscribe(mock_device))
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

  test.mock_device.add_test_device(mock_child)

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Window Covering 2",
    profile = "window-covering-modular",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", 20)
  })

  test.socket.device_lifecycle:__queue_receive({ mock_child.id, "doConfigure" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  mock_child:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

local CLUSTER_SUBSCRIBE_LIST = {
  WindowCovering.server.attributes.CurrentPositionLiftPercent100ths,
  WindowCovering.server.attributes.CurrentPositionTiltPercent100ths,
  WindowCovering.server.attributes.OperationalStatus,
  clusters.LevelControl.server.attributes.CurrentLevel,
}

local function update_profile()
  test.socket.matter:__queue_receive({mock_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(
    mock_device, 10, {uint32(clusters.PowerSource.attributes.BatPercentRemaining.ID)}
  )})
  mock_child:expect_metadata_update({ profile = "window-covering-modular", optional_component_capabilities = {{"main", {"windowShadeLevel", "windowShadeTiltLevel"}}} })
  mock_device:expect_metadata_update({ profile = "window-covering-modular", optional_component_capabilities = {{"main", {"windowShadeLevel", "windowShadeTiltLevel", "battery"}}} })
  test.wait_for_events()
  local updated_device_profile = t_utils.get_profile_definition("window-covering-modular.yml",
    {enabled_optional_capabilities = {{"main", {"windowShadeLevel", "windowShadeTiltLevel"}}}}
  )
  test.socket.device_lifecycle:__queue_receive(mock_child:generate_info_changed({ profile = updated_device_profile }))
  subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.wait_for_events()
  updated_device_profile = t_utils.get_profile_definition("window-covering-modular.yml",
    {enabled_optional_capabilities = {{"main", {"windowShadeLevel", "windowShadeTiltLevel", "battery"}}}}
  )
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = updated_device_profile }))
  subscribe_request:merge(clusters.PowerSource.server.attributes.BatPercentRemaining:subscribe(mock_device))
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed following lift position update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed following tilt position update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed before lift position 0", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed before tilt position 0", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open following lift position update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open following tilt position update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open before lift position event", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open before tilt position event", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open following lift position update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open following tilt position update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 15) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(15)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open before lift position event", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open before tilt position event", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 65) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(65)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end
)

test.register_coroutine_test("WindowCovering OperationalStatus opening", function()
  update_profile()
  test.wait_for_events()
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, ((100 - 25) *100)
      ),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 1),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.opening()
    )
  )
end)

test.register_coroutine_test("WindowCovering OperationalStatus closing", function()
  update_profile()
  test.wait_for_events()
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, ((100 - 25) *100)
      ),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 2),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.closing()
    )
  )
end)

test.register_coroutine_test("WindowCovering OperationalStatus unknown", function()
  update_profile()
  test.wait_for_events()
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, ((100 - 25) *100)
      ),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 3),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.unknown()
    )
  )
end)

test.register_coroutine_test(
  "WindowShade open cmd handler", function()
    update_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "open", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.UpOrOpen(mock_device, 10)}
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade close cmd handler", function()
    update_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "close", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.DownOrClose(mock_device, 10)}
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "WindowShade pause cmd handler", function()
    update_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "pause", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.StopMotion(mock_device, 10)}
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Refresh necessary attributes", function()
    update_profile()
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
    test.socket.capability:__expect_send(
      {
        mock_device.id,
        {
          capability_id = "windowShade",
          component_id = "main",
          attribute_id = "supportedWindowShadeCommands",
          state = {value = {"open", "close", "pause"}},
          visibility = {displayed = false}
        },
      }
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    )
    local read_request = CLUSTER_SUBSCRIBE_LIST[1]:read(mock_device)
    for i, attr in ipairs(CLUSTER_SUBSCRIBE_LIST) do
      if i > 1 then read_request:merge(attr:read(mock_device)) end
    end
    read_request:merge(clusters.PowerSource.server.attributes.BatPercentRemaining:read(mock_device))
    test.socket.matter:__expect_send({mock_device.id, read_request})
    test.wait_for_events()
  end
)

test.register_coroutine_test("WindowShade setShadeLevel cmd handler", function()
  update_profile()
  test.wait_for_events()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 20 }},
    }
  )
  test.socket.matter:__expect_send(
    {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 8000)}
  )
end)

test.register_coroutine_test("WindowShade setShadeTiltLevel cmd handler", function()
  update_profile()
  test.wait_for_events()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 60 }},
    }
  )
  test.socket.matter:__expect_send(
    {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 4000)}
  )
end)

test.register_coroutine_test("LevelControl CurrentLevel handler", function()
  update_profile()
  test.wait_for_events()
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 10, 100),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(math.floor((100 / 254.0 * 100) + .5))
    )
  )
end)

--test battery
test.register_coroutine_test(
  "Battery percent reports should generate correct messages", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 10, 150
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150/2.0+0.5))
      )
    )
  end
)

test.register_coroutine_test("OperationalStatus report contains current position report", function()
  update_profile()
  test.wait_for_events()
  local report = WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
    mock_device, 10, ((100 - 25) *100)
  )
  table.insert(report.info_blocks, WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0).info_blocks[1])
  test.socket.matter:__queue_receive({ mock_device.id, report})
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
end)

test.register_coroutine_test(
  "Handle preset commands",
  function()
    update_profile()
    test.wait_for_events()
    local PRESET_LEVEL = 30
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadePreset", component = "main", command = "setPresetPosition", args = { PRESET_LEVEL }},
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadePreset.position(PRESET_LEVEL)
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadePreset", component = "main", command = "presetPosition", args = {}},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, (100 - PRESET_LEVEL) * 100)}
    )
  end
)

test.register_coroutine_test(
  "WindowCovering shade level adjusted by greater than 2%; status reflects Closing followed by Partially Open", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 19 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 8100)}
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 10),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closing()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 23) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(23)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 21) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(21)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 19) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(19)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end
)

test.register_coroutine_test(
  "WindowCovering shade level adjusted by less than or equal to 2%; status reflects Closing followed by Partially Open", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 23 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 7700)}
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 10),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closing()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 23) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(23)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade lift operates as expected when opening and closing", function()
    update_profile()
    test.wait_for_events()
    mock_device:set_field("__reverse_polarity", true)
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, 100 * 100
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, 0
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 85 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 1500)}
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 100 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 0)}
    )
  end
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade tilt operates as expected when opening and closing", function()
    update_profile()
    test.wait_for_events()
    mock_device:set_field("__reverse_polarity", true)
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
        mock_device, 10, 100 * 100
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
        mock_device, 10, 0
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 15 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 8500)}
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 0 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 10000)}
    )
  end
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed following lift position update for child device", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_child, 20, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_child:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_child:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_child, 20, 0),
      }
    )
  end
)

test.run_registered_tests()
