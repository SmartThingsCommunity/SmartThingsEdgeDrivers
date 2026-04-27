-- Copyright © 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

test.disable_startup_messages()

local parent_ep_id = 10
local dimmable_ep_id = 30
local extended_color_ep_id = 50

-- this parent device would fingerprint as light-color-level, since the most feature-rich endpoint is the extended color one,
-- but it should re-configure to light-binary in doConfigure
local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("light-color-level.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  matter_version = {
    hardware = 1,
    software = 1
   },
  endpoints = {
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
      endpoint_id = parent_ep_id,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 2} -- On/Off Light
      }
    },
    {
      endpoint_id = extended_color_ep_id,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 30},
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    },
    {
      endpoint_id = dimmable_ep_id,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 2}, -- On/Off Light
        {device_type_id = 0x0101, device_type_revision = 2} -- Dimmable Light
      }
    },
  }
})

local child_profiles = {
  [dimmable_ep_id] = t_utils.get_profile_definition("light-level.yml"),
  [extended_color_ep_id] = t_utils.get_profile_definition("light-color-level.yml"),
}

local mock_children = {}
for i, endpoint in ipairs(mock_device.endpoints) do
  if endpoint.endpoint_id ~= parent_ep_id and endpoint.endpoint_id ~= 0 then
    local child_data = {
      profile = child_profiles[endpoint.endpoint_id],
      device_network_id = string.format("%s:%d", mock_device.id, endpoint.endpoint_id),
      parent_device_id = mock_device.id,
      parent_assigned_child_key = string.format("%d", endpoint.endpoint_id)
    }
    mock_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data)
  end
end

local function handle_init_event(mock_device)
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.LevelControl.attributes.CurrentLevel,
    clusters.LevelControl.attributes.MaxLevel,
    clusters.LevelControl.attributes.MinLevel,
    clusters.ColorControl.attributes.ColorTemperatureMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
    clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    clusters.ColorControl.attributes.CurrentHue,
    clusters.ColorControl.attributes.CurrentSaturation,
    clusters.ColorControl.attributes.CurrentX,
    clusters.ColorControl.attributes.CurrentY,
    clusters.ColorControl.attributes.ColorMode,
  }
  local expected_subscriptions = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      expected_subscriptions:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({mock_device.id, expected_subscriptions})
end

local function handle_do_configure_event(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  test.socket.matter:__expect_send({mock_device.id, clusters.LevelControl.attributes.Options:write(mock_device, extended_color_ep_id, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
  test.socket.matter:__expect_send({mock_device.id, clusters.ColorControl.attributes.Options:write(mock_device, extended_color_ep_id, clusters.ColorControl.types.OptionsBitmap.EXECUTE_IF_OFF)})
  test.socket.matter:__expect_send({mock_device.id, clusters.LevelControl.attributes.Options:write(mock_device, dimmable_ep_id, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF)})

  mock_device:expect_metadata_update({ profile = "light-binary" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", dimmable_ep_id)
  })

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 3",
    profile = "light-color-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", extended_color_ep_id)
  })
end

local function test_init_for_lifecycle_tests()
  test.mock_device.add_test_device(mock_device)
  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end
end

-- due to device copy logic in the integration tests, we need to handle init and doConfigure before generating an infoChanged event
local function test_init_for_generate_info_changed_tests()
  test.mock_device.add_test_device(mock_device)
  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end
  handle_init_event(mock_device)
  handle_do_configure_event(mock_device)
end

local function test_init_for_post_configure_tests()
  test.mock_device.add_test_device(mock_device)
  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end
  local FIND_CHILD_KEY = "__find_child_fn"
  mock_device:set_field(FIND_CHILD_KEY, switch_utils.find_child, { persist = false })
  mock_device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, { persist = false })
end

test.set_test_init_function(test_init_for_post_configure_tests)

test.register_coroutine_test(
  "Handle initial init lifecycle event, before children are created",
  function()
    handle_init_event(mock_device)
    test.wait_for_events()
    assert(mock_device:get_field(fields.profiling_data.POWER_TOPOLOGY) == false, "Device should be marked as not needing to configure power topology")
    assert(mock_device:get_field(fields.profiling_data.BATTERY_SUPPORT) == fields.battery_support.NO_BATTERY, "Device should be marked as having no battery")
  end,
  {
    test_init = test_init_for_lifecycle_tests,
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Handle doConfigure lifecycle event",
  function()
    mock_device:set_field(fields.profiling_data.BATTERY_SUPPORT, false, { persist = true })
    mock_device:set_field(fields.profiling_data.POWER_TOPOLOGY, false, { persist = true })
    handle_do_configure_event(mock_device)
    test.wait_for_events()
    local FIND_CHILD_KEY = "__find_child_fn"
    assert(type(mock_device:get_field(FIND_CHILD_KEY)) == "function", "Child find function should be stored in doConfigure")
  end,
  {
    test_init = test_init_for_lifecycle_tests,
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test info changed event with matter_version update",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ matter_version = { hardware = 1, software = 2 } })) -- bump to 2
    mock_children[dimmable_ep_id]:expect_metadata_update({ profile = "light-level" })
    mock_children[extended_color_ep_id]:expect_metadata_update({ profile = "light-color-level" })
    mock_device:expect_metadata_update({ profile = "light-binary" })
  end,
  {
    test_init = test_init_for_generate_info_changed_tests,
    min_api_version = 17
  }
)


test.register_message_test(
  "Dimmable Child: Current level cluster reports generate switch level events appropriately",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.server.attributes.CurrentLevel:build_test_report_data(mock_device, dimmable_ep_id, 50)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[dimmable_ep_id]:generate_test_message("main", capabilities.switchLevel.level(math.floor((50 / 254.0 * 100) + 0.5)))
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switchLevel", capability_attr_id = "level" }
      }
    },
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Children: Level Control Min and max attributes set switch level constraints appropriately",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MinLevel:build_test_report_data(mock_device, dimmable_ep_id, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MaxLevel:build_test_report_data(mock_device, dimmable_ep_id, 254)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[dimmable_ep_id]:generate_test_message("main", capabilities.switchLevel.levelRange({minimum = 1, maximum = 100}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MinLevel:build_test_report_data(mock_device, extended_color_ep_id, 127)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MaxLevel:build_test_report_data(mock_device, extended_color_ep_id, 203)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[extended_color_ep_id]:generate_test_message("main", capabilities.switchLevel.levelRange({minimum = 50, maximum = 80}))
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Extended Color Child: X and Y color values should report hue and saturation once both have been received",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, extended_color_ep_id, 15091)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, extended_color_ep_id, 21547)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[extended_color_ep_id]:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[extended_color_ep_id]:generate_test_message("main", capabilities.colorControl.saturation(72))
    }
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Extended Color Child: colorTemperatureRange, setColorTemperature, stepColorTemperatureByPercent handled appropriately",
  {
    -- setColorTemperature before a color temperature range is set 
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[extended_color_ep_id].id,
        { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 72 } } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColor(mock_device, extended_color_ep_id, 15182, 21547, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.HANDLE_COMMAND_IF_OFF)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColor:build_test_command_response(mock_device, extended_color_ep_id)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, extended_color_ep_id, 15091)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, extended_color_ep_id, 21547)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[extended_color_ep_id]:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[extended_color_ep_id]:generate_test_message("main", capabilities.colorControl.saturation(72))
    },

    -- colorTemperatureRange testing
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, extended_color_ep_id, 153)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, extended_color_ep_id, 555)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[extended_color_ep_id]:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({minimum = 1800, maximum = 6500}))
    },

    -- setColorTemperature testing
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[extended_color_ep_id].id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {1800} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, extended_color_ep_id, 555, fields.TRANSITION_TIME, fields.OPTIONS_MASK, fields.HANDLE_COMMAND_IF_OFF)
      }
    }, -- 555 is expected since it is re-bounded by the given range

    -- stepColorTemperatureByPercent testing  
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[extended_color_ep_id].id,
        { capability = "statelessColorTemperatureStep", component = "main", command = "stepColorTemperatureByPercent", args = { 20 } }
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_children[extended_color_ep_id].id, capability_id = "statelessColorTemperatureStep", capability_cmd_id = "stepColorTemperatureByPercent" }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.StepColorTemperature(mock_device, extended_color_ep_id, clusters.ColorControl.types.StepModeEnum.DOWN, 80, fields.TRANSITION_TIME_FAST, 153, 555, fields.OPTIONS_MASK, fields.IGNORE_COMMAND_IF_OFF)
      },
    },
  },
  {
     min_api_version = 17
  }
)

test.register_message_test(
  "Parent: switch capability <-> On Off cluster should handle events appropriately",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, parent_ep_id)
      },
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, parent_ep_id, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
  },
  {
    min_api_version = 17
  }
)

test.register_message_test(
  "Children: switch capability <-> On Off Cluster should handle events appropriately",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[dimmable_ep_id].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_children[dimmable_ep_id].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, dimmable_ep_id)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, dimmable_ep_id, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[dimmable_ep_id]:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[extended_color_ep_id].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_children[extended_color_ep_id].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, extended_color_ep_id)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, extended_color_ep_id, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[extended_color_ep_id]:generate_test_message("main", capabilities.switch.switch.on())
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_attr_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_attr_id = "switch" }
      }
    },
  },
  {
    min_api_version = 17
  }
)

test.run_registered_tests()
