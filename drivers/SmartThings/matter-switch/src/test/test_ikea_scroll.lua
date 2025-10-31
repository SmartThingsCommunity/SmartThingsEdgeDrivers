local test = require "integration_test"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local mock_ikea_scroll = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("ikea-scroll.yml"),
  manufacturer_info = {vendor_id = 0xFFF1, product_id = 0x8000, product_name = "Ikea Scroll"},
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

local ENDPOINTS_PRESS = { 3, 6, 9 }

-- the ikea scroll subdriver has overriden subscribe behavior
local function ikea_scroll_subscribe()
  local CLUSTER_SUBSCRIBE_LIST ={
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.MultiPressComplete,
  }
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_ikea_scroll, ENDPOINTS_PRESS[1])
  for _, ep_press in ipairs(ENDPOINTS_PRESS) do
    for _, event in ipairs(CLUSTER_SUBSCRIBE_LIST) do
      subscribe_request:merge(event:subscribe(mock_ikea_scroll, ep_press))
    end
  end
  return subscribe_request
end

local function expect_configure_buttons()
  local button_attr = capabilities.button.button
  test.socket.matter:__expect_send({mock_ikea_scroll.id, clusters.Switch.attributes.MultiPressMax:read(mock_ikea_scroll, 3)})
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("group1", button_attr.pushed({state_change = false})))

  test.socket.matter:__expect_send({mock_ikea_scroll.id, clusters.Switch.attributes.MultiPressMax:read(mock_ikea_scroll, 6)})
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("group2", button_attr.pushed({state_change = false})))

  test.socket.matter:__expect_send({mock_ikea_scroll.id, clusters.Switch.attributes.MultiPressMax:read(mock_ikea_scroll, 9)})
  test.socket.capability:__expect_send(mock_ikea_scroll:generate_test_message("group3", button_attr.pushed({state_change = false})))
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
      message = mock_ikea_scroll:generate_test_message("group1",
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

test.run_registered_tests()