local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.generated.zap_clusters"
local button_attr = capabilities.button.button

local child_profile = t_utils.get_profile_definition("button.yml")

--mock the actual device
local mock_device = test.mock_device.build_test_matter_device(
  {
    label = "Matter Button",
    profile = t_utils.get_profile_definition("button-battery.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    endpoints = {
    {
      endpoint_id = 2,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        },
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
      },
    },
    {
      endpoint_id = 3,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE,
          cluster_type = "SERVER"
        },
      },
    },
    {
      endpoint_id = 4,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        },
      },
    },
    {
      endpoint_id = 5,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
          cluster_type = "SERVER"
        },
      },
    },
    {
      endpoint_id = 6,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH | clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
          cluster_type = "SERVER"
        },
      },
    },
  },
}
)

local mock_children = {}
for _, endpoint in ipairs(mock_device.endpoints) do
  if endpoint.endpoint_id ~= 2 then
    local child_data = {
      profile = child_profile,
      device_network_id = string.format("%s:%02X", mock_device.id, endpoint.endpoint_id),
      parent_device_id = mock_device.id,
      parent_assigned_child_key = string.format("%02X", endpoint.endpoint_id)
    }
    mock_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data)
  end
end

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.PowerSource.server.attributes.BatPercentRemaining,
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
  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", button_attr.pushed({state_change = false})))

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Button 2",
    profile = "button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = "03"
  })
  test.socket.capability:__expect_send(mock_children[3]:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_children[3]:generate_test_message("main", button_attr.pushed({state_change = false})))

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Button 3",
    profile = "button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = "04"
  })
  test.socket.capability:__expect_send(mock_children[4]:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed", "held"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_children[4]:generate_test_message("main", button_attr.pushed({state_change = false})))

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Button 4",
    profile = "button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = "05"
  })
  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, 5)})
  test.socket.capability:__expect_send(mock_children[5]:generate_test_message("main", button_attr.pushed({state_change = false})))

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Button 5",
    profile = "button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = "06"
  })
  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, 6)})
  test.socket.capability:__expect_send(mock_children[6]:generate_test_message("main", button_attr.pushed({state_change = false})))

end

test.set_test_init_function(test_init)

test.register_message_test(
  "Handle single press sequence, no hold", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 2, {new_position = 1}  --move to position 1?
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_device:generate_test_message("main", button_attr.pushed({state_change = true})) --should send initial press
  }
}
)

test.register_message_test(
  "Handle release after short press", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 3, {new_position = 1}
      )
    }
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, 3, {previous_position = 1}
      )
    }
  },
  { -- this is a double event because the test device in this test shouldn't support the above event
    -- but we handle it anyway
    channel = "capability",
    direction = "send",
    message = mock_children[3]:generate_test_message("main", button_attr.pushed({state_change = true}))
  },
  }
)

test.register_message_test(
  "Handle release after long press", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 4, {new_position = 1}
      )
    }
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.LongPress:build_test_event_report(
        mock_device, 4, {new_position = 1}
      ),
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_children[4]:generate_test_message("main", button_attr.held({state_change = true}))
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.LongRelease:build_test_event_report(
        mock_device, 4, {previous_position = 1}
      )
    }
  },
  }
)

test.register_message_test(
  "Receiving a max press attribute of 2 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 6, 2
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[6]:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "double"}, {visibility = {displayed = false}}))
    },
  }
)

test.register_message_test(
  "Receiving a max press attribute of 3 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 5, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[5]:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "double", "pushed_3x"}, {visibility = {displayed = false}}))
    },
  }
)

test.register_message_test(
  "Receiving a max press attribute of greater than 6 should only emit up to pushed_6x", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, 2, 7
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "double", "pushed_3x", "pushed_4x", "pushed_5x", "pushed_6x"}, {visibility = {displayed = false}}))
    },
  }
)

test.register_message_test(
  "Handle double press", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 5, {new_position = 1}
      )
    }
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, 5, {new_position = 1, total_number_of_presses_counted = 2, previous_position = 0}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_children[5]:generate_test_message("main", button_attr.double({state_change = true}))
  },

}
)

test.register_message_test(
  "Handle multi press for 4 times", {
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, 6, {new_position = 1}
      )
    }
  },
  {
    channel = "matter",
    direction = "receive",
    message = {
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, 6, {new_position = 1, total_number_of_presses_counted = 4, previous_position = 0}
      )
    }
  },
  {
    channel = "capability",
    direction = "send",
    message = mock_children[6]:generate_test_message("main", button_attr.pushed_4x({state_change = true}))
  },

}
)

test.register_message_test(
  "Handle received BatPercentRemaining from device.", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 2, 150
        ),
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
      ),
    },
  }
)
-- run the tests
test.run_registered_tests()
