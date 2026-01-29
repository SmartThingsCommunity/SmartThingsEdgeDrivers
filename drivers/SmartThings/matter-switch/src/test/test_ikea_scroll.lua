local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local mock_ikea_scroll = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("ikea-scroll.yml"),
  manufacturer_info = {vendor_id = 0x117C, product_id = 0x8000, product_name = "Ikea Scroll"},
  label = "Ikea Scroll",
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.Feature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
        cluster_type = "SERVER"
      },},
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 2,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.Feature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
        cluster_type = "SERVER"
      },},
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 3,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
        cluster_type = "SERVER"},
      },
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 4,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.Feature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
        cluster_type = "SERVER"
      },},
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 5,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.Feature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
        cluster_type = "SERVER"
      },},
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 6,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
        cluster_type = "SERVER"},
      },
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 7,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.Feature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
        cluster_type = "SERVER"
      },},
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 8,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.Feature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
        cluster_type = "SERVER"
      },},
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
    {
      endpoint_id = 9,
      clusters = {{
        cluster_id = clusters.Switch.ID,
        feature_map =
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
          clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
        cluster_type = "SERVER"},
      },
      device_types = {{device_type_id = 0x000F, device_type_revision = 1}} -- GENERIC SWITCH
    },
  }
})

local ENDPOINTS_PUSH = { 3, 6, 9 }
local ENDPOINTS_SCROLL = {1, 2, 4, 5, 7, 8}

-- the ikea scroll subdriver has overriden subscribe behavior
local function ikea_scroll_subscribe()
  local CLUSTER_SUBSCRIBE_LIST_PUSH ={
    clusters.Switch.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.MultiPressComplete,
  }
  local CLUSTER_SUBSCRIBE_LIST_SCROLL = {
    clusters.Switch.server.events.MultiPressOngoing,
    clusters.Switch.server.events.MultiPressComplete,
  }
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST_PUSH[1]:subscribe(mock_ikea_scroll, ENDPOINTS_PUSH[1])
  for _, ep_press in ipairs(ENDPOINTS_PUSH) do
    for _, event in ipairs(CLUSTER_SUBSCRIBE_LIST_PUSH) do
      subscribe_request:merge(event:subscribe(mock_ikea_scroll, ep_press))
    end
  end
  for _, ep_press in ipairs(ENDPOINTS_SCROLL) do
    for _, event in ipairs(CLUSTER_SUBSCRIBE_LIST_SCROLL) do
      subscribe_request:merge(event:subscribe(mock_ikea_scroll, ep_press))
    end
  end
  subscribe_request:merge(clusters.PowerSource.attributes.BatPercentRemaining:subscribe(mock_ikea_scroll, 0))
  return subscribe_request
end

local function expect_configure_buttons()
  local button_attr = capabilities.button.button
  test.socket.matter:__expect_send({mock_ikea_scroll.id, clusters.Switch.attributes.MultiPressMax:read(mock_ikea_scroll, 3)})
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("main", button_attr.pushed({state_change = false})))
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("main", capabilities.knob.supportedAttributes({"rotateAmount"}, {visibility = {displayed = false}})))
  test.socket.matter:__expect_send({mock_ikea_scroll.id, clusters.Switch.attributes.MultiPressMax:read(mock_ikea_scroll, 6)})
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("group2", button_attr.pushed({state_change = false})))
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("group2", capabilities.knob.supportedAttributes({"rotateAmount"}, {visibility = {displayed = false}})))
  test.socket.matter:__expect_send({mock_ikea_scroll.id, clusters.Switch.attributes.MultiPressMax:read(mock_ikea_scroll, 9)})
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("group3", button_attr.pushed({state_change = false})))
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("group3", capabilities.knob.supportedAttributes({"rotateAmount"}, {visibility = {displayed = false}})))
end

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_ikea_scroll)
  local subscribe_request = ikea_scroll_subscribe()

  test.socket.device_lifecycle:__queue_receive({ mock_ikea_scroll.id, "added" })

  test.socket.device_lifecycle:__queue_receive({ mock_ikea_scroll.id, "init" })
  test.socket.matter:__expect_send({mock_ikea_scroll.id, subscribe_request})

  mock_ikea_scroll:expect_metadata_update({ profile = "ikea-scroll" })
  mock_ikea_scroll:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  expect_configure_buttons()
  test.socket.device_lifecycle:__queue_receive({ mock_ikea_scroll.id, "doConfigure" })
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Ensure Ikea Scroll Button initialization works as expected", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_ikea_scroll, 3, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x"}, {visibility = {displayed = false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_ikea_scroll, 6, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group2",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x"}, {visibility = {displayed = false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_ikea_scroll, 9, 3
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group3",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x"}, {visibility = {displayed = false}}))
    },
  }
)

test.register_message_test(
  "Ikea Scroll Positive rotateAmount events on main are emitted correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[1], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[1], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(18, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[1], {new_position = 5, total_number_of_presses_counted = 5, previous_position = 0}
        )
      },
    },
   {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[1], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[1], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(18, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[1], {new_position = 5, total_number_of_presses_counted = 5, previous_position = 0}
        )
      },
    }
  }
)

test.register_message_test(
  "Ikea Scroll Negative rotateAmount events on main are emitted correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[2], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(-12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[2], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(-18, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[2], {new_position = 5, total_number_of_presses_counted = 5, previous_position = 0}
        )
      },
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[2], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(-12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[2], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.knob.rotateAmount(-18, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[2], {new_position = 5, total_number_of_presses_counted = 5, previous_position = 0}
        )
      },
    }
  }
)

test.register_message_test(
  "Ikea Scroll Positive rotateAmount events on group2 are emitted correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[3], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group2",
        capabilities.knob.rotateAmount(12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[3], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group2",
        capabilities.knob.rotateAmount(18, {state_change = true}))
    }
  }
)

test.register_message_test(
  "Ikea Scroll Negative rotateAmount events on group2 are emitted correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[4], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group2",
        capabilities.knob.rotateAmount(-12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[4], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group2",
        capabilities.knob.rotateAmount(-18, {state_change = true}))
    }
  }
)

test.register_message_test(
  "Ikea Scroll Positive rotateAmount events on group3 are emitted correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[5], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group3",
        capabilities.knob.rotateAmount(12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[5], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group3",
        capabilities.knob.rotateAmount(18, {state_change = true}))
    }
  }
)

test.register_message_test(
  "Ikea Scroll Negative rotateAmount events on group3 are emitted correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[6], {current_number_of_presses_counted = 2, new_position = 2}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group3",
        capabilities.knob.rotateAmount(-12, {state_change = true}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressOngoing:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_SCROLL[6], {current_number_of_presses_counted = 5, new_position = 5}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group3",
        capabilities.knob.rotateAmount(-18, {state_change = true}))
    }
  }
)

test.register_message_test(
  "Ikea Scroll Long Press Push events on main are handled correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_PUSH[1], {new_position = 1}
        )
      },
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.LongPress:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_PUSH[1], {new_position = 1}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("main",
        capabilities.button.button.held({state_change = true}))
    },
  }
)

test.register_message_test(
  "Ikea Scroll MultiPressComplete Push events on group2 are handled correctly", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_PUSH[2], {new_position = 1}
        )
      },
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_ikea_scroll.id,
        clusters.Switch.events.MultiPressComplete:build_test_event_report(
          mock_ikea_scroll, ENDPOINTS_PUSH[2], {total_number_of_presses_counted = 1, previous_position = 0}
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_ikea_scroll:generate_test_message("group2",
        capabilities.button.button.pushed({state_change = true}))
    },
  }
)

test.run_registered_tests()
