-- Copyright 2022 SmartThings, Inc.
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

local WindowCovering = clusters.WindowCovering

test.disable_startup_messages()

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
        endpoint_id = 10,
        clusters = {
          {
            cluster_id = clusters.WindowCovering.ID,
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

local mock_device_mains_powered = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("window-covering.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
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
        endpoint_id = 10,
        clusters = {
          {
            cluster_id = clusters.WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 1,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0001}
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

local CLUSTER_SUBSCRIBE_LIST_NO_BATTERY = {
  clusters.LevelControl.server.attributes.CurrentLevel,
  WindowCovering.server.attributes.CurrentPositionLiftPercent100ths,
  WindowCovering.server.attributes.OperationalStatus,
  WindowCovering.server.attributes.TargetPositionLiftPercent100ths,
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

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device.id, read_attribute_list})
end

local function test_init_mains_powered()
  test.mock_device.add_test_device(mock_device_mains_powered)
  test.socket.device_lifecycle:__queue_receive({ mock_device_mains_powered.id, "added" })
  test.socket.capability:__expect_send(
    mock_device_mains_powered:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )

  test.socket.device_lifecycle:__queue_receive({ mock_device_mains_powered.id, "init" })
  set_preset(mock_device_mains_powered)
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST_NO_BATTERY[1]:subscribe(mock_device_mains_powered)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST_NO_BATTERY) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device_mains_powered)) end
  end
  test.socket.matter:__expect_send({mock_device_mains_powered.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_mains_powered.id, "doConfigure" })
  mock_device_mains_powered:expect_metadata_update({ profile = "window-covering" })
  mock_device_mains_powered:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'open' capability emission if lift position is 100", function()
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
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'closed' capability emission if lift position is 0", function()
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
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'partially open' capability emission if lift position is 50", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
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
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Idle WindowCovering OperationalStatus state triggers 'partially open' capability emission if tilt position is between 1-100", function()
    test.socket.capability:__set_channel_ordering("relaxed")
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
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Unknown WindowCovering OperationalStatus state triggers 'unknown' capability emission", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 99),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.unknown()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Opening WindowCovering OperationalStatus state triggers 'closing' capability emission", function()
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
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Closing WindowCovering OperationalStatus state triggers 'opening' capability emission", function()
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
  end,
  {
     min_api_version = 17
  }
)


test.register_coroutine_test(
  "WindowCovering CurrentPositionLiftPercent100ths triggers appropriate capability emission", function()
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
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering CurrentPositionTiltPercent100ths triggers appropriate capability emission", function()
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
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering TargetPositionLiftPercent100ths sets field appropriately",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.TargetPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.wait_for_events()
    assert(mock_device:get_field("__target_lift_percent") == 50)
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering TargetPositionTiltPercent100ths sets field appropriately",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.TargetPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.wait_for_events()
    assert(mock_device:get_field("__target_tilt_percent") == 50)
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering TargetPositionLiftPercent100ths triggers operational status update when appropriate",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 65) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(65)
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end
)

test.register_coroutine_test(
  "WindowCovering TargetPositionTiltPercent100ths triggers operational status update when appropriate",
  function()
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
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Open capability command triggers appropriate Matter command", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "open", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.UpOrOpen(mock_device, 10)}
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Close capability command triggers appropriate Matter command", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "close", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.DownOrClose(mock_device, 10)}
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Pause capability command triggers appropriate Matter command", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "pause", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.StopMotion(mock_device, 10)}
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Cached target lift/tilt position timeouts trigger one operational status update",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 50 * 100
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(50)
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "open", args = {}},
      }
    )
    test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.UpOrOpen(mock_device, 10)}
    )

    test.wait_for_events()
    test.mock_time.advance_time(120)

    test.socket.capability:__expect_send({
        mock_device.id, { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } },
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Cached target lift timeout triggers one operational status update if tilt target and idle state are first reached appropriately",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(50)
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "open", args = {}},
      }
    )
    -- two timers are made when open is called
    test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(120, "oneshot")
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.UpOrOpen(mock_device, 10)}
    )

    -- ensure target state is cached before queueing responses
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
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )

    -- advance time to trigger the single remaining timer
    test.wait_for_events()
    test.mock_time.advance_time(120)
    test.socket.capability:__expect_send({
        mock_device.id, { capability_id = "windowShade", component_id = "main", attribute_id = "windowShade", state = { value = "partially open" } },
      }
    )

  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Refresh necessary attributes", function()
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
    test.socket.matter:__expect_send({mock_device.id, read_request})
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test("SetShadeLevel capability command triggers appropriate Matter command", function()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 20 }},
    }
  )
  test.socket.matter:__expect_send(
    {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 8000)}
  )
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test("SetShadeTiltLevel capability command triggers appropriate Matter command", function()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 60 }},
    }
  )
  test.socket.matter:__expect_send(
    {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 4000)}
  )
end,
{
   min_api_version = 17
}
)

--test battery
test.register_coroutine_test(
  "Battery percent reports should generate correct messages", function()
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
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle preset commands",
  function()
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
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test profile change to window-covering-battery when battery percent remaining attribute (attribute ID 12) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(12)})
      }
    )
    mock_device:expect_metadata_update({ profile = "window-covering-tilt-battery" })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test that profile is not changed to window-covering-battery when battery percent remaining attribute (attribute ID 12) is not available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(10)})
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test mains powered device does not switch to battery profile",
  function()
  end,
  {
    test_init = test_init_mains_powered,
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "InfoChanged event updates new profile if sw updated has occurred",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ matter_version = {software = 2} }))
    local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
    test.socket.matter:__expect_send({mock_device.id, read_attribute_list})
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(0x0C)})})
    mock_device:expect_metadata_update({profile = "window-covering-tilt-battery"})
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade lift operates as expected when opening and closing", function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { reverse = "true" } }))
    test.wait_for_events()
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
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(
        mock_device, 10, 0
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.wait_for_events()
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
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(
        mock_device, 10, 0
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.wait_for_events()
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
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade tilt operates as expected when opening and closing", function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { reverse = "true" } }))
    test.wait_for_events()
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
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(
        mock_device, 10, 0
      )
    })
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
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(
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
    test.wait_for_events()
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
  end,
  {
     min_api_version = 17
  }
)

-- stepShadeLevel tests

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - step up", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 9000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - step down", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 7000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - continuous step with target tracking", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 7000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(30)
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 6000)}
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 5000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - target reached clears target marker", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 4000)}
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 4000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(60)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - step up to maximum (100)", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 500
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(95)
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 0)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - step down to minimum (0)", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 9500
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(5)
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 10000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
