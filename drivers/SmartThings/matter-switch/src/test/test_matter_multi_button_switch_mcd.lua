local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require "dkjson"

local clusters = require "st.matter.generated.zap_clusters"

local TRANSITION_TIME = 0
local OPTIONS_MASK = 0x01
local OPTIONS_OVERRIDE = 0x01
local button_attr = capabilities.button.button


local mock_device_ep1 = 1
local mock_device_ep2 = 2
local mock_device_ep3 = 3
local mock_device_ep4 = 4
local mock_device_ep5 = 5

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("light-level-3-button.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
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
      endpoint_id = mock_device_ep1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0101, device_type_revision = 2} -- Dimmable Light
      }
    },
    {
      endpoint_id = mock_device_ep2,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = mock_device_ep3,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = mock_device_ep4,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = mock_device_ep5,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31}
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    },
  }
})

local mock_device_mcd_unsupported_switch_device_type = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("matter-thing.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0103, device_type_revision = 1} -- OnOff Switch
      }
    },
    {
      endpoint_id = 20,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 30,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
  }
})

local child_profile = t_utils.get_profile_definition("light-color-level.yml")
local child_data = {
  profile = child_profile,
  device_network_id = string.format("%s:%d", mock_device.id, mock_device_ep5),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%d", mock_device_ep5)
}
local mock_child = test.mock_device.build_test_child_device(child_data)

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
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
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.MultiPressComplete,
}

local function test_init()
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_child)
  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-color-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", mock_device_ep5)
  })
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  mock_device:expect_metadata_update({ profile = "light-level-3-button" })
  local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
  device_info_copy.profile.id = "3-button"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.capability:__expect_send(mock_device:generate_test_message("button1", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button1", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(mock_device:generate_test_message("button3", capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("button3", button_attr.pushed({state_change = false})))
end

local function test_init_mcd_unsupported_switch_device_type()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete,
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_mcd_unsupported_switch_device_type)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_mcd_unsupported_switch_device_type))
    end
  end
  mock_device_mcd_unsupported_switch_device_type:expect_metadata_update({ profile = "2-button" })
  mock_device_mcd_unsupported_switch_device_type:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 1",
    profile = "switch-binary",
    parent_device_id = mock_device_mcd_unsupported_switch_device_type.id,
    parent_assigned_child_key = string.format("%d", 7)
  })
  test.mock_device.add_test_device(mock_device_mcd_unsupported_switch_device_type)
  test.socket.matter:__expect_send({mock_device_mcd_unsupported_switch_device_type.id, subscribe_request})
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Main switch component: switch capability should send the appropriate commands",
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
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, mock_device_ep1)
      },
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, mock_device_ep1, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "First button component: Handle single press sequence, no hold", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, mock_device_ep2, {new_position = 1}
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("button1", button_attr.pushed({state_change = true})) --should send initial press
  }
}
)

test.register_message_test(
  "Second button component: Handle single press sequence for short release-supported button", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, mock_device_ep3, {new_position = 1}
      ),
    }
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, mock_device_ep3, {previous_position = 0}
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("button2", button_attr.pushed({state_change = true}))
  }
}
)

test.register_coroutine_test(
  "Third button component: Handle single press sequence for a long hold on long-release-capable button", -- only a long press event should generate a held event
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, mock_device_ep4, {new_position = 1}
      )
    })
    test.wait_for_events()
    test.mock_time.advance_time(2)
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, mock_device_ep4, {previous_position = 0}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button3", button_attr.pushed({state_change = true})))
  end
)

test.register_message_test(
  "Switch child device: Set color temperature should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_child.id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {1800} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, mock_device_ep5, 556, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature:build_test_command_response(mock_device, mock_device_ep5)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, mock_device_ep5, 556)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.colorTemperature.colorTemperature(1800))
    },
  }
)

test.register_coroutine_test(
  "Test MCD configuration not including switch for unsupported switch device type, create child device instead",
  function()
  end,
  { test_init = test_init_mcd_unsupported_switch_device_type }
)

-- run the tests
test.run_registered_tests()
