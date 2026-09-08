-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"
local st_utils = require "st.utils"

--- The first button endpoint is mapped to "main", the remaining endpoints are mapped in order
--- to "button2" through "buttonN".
local function expected_optional_component_capabilities(num_button_eps)
  local optional_component_capabilities = {{"main", {}}}
  for component_num = 2, num_button_eps do
    table.insert(optional_component_capabilities, {"button" .. component_num, {"button"}})
  end
  return optional_component_capabilities
end

--- Builds a device with num_button_eps Generic Switch endpoints, all of which only support
--- the MOMENTARY_SWITCH feature. Endpoints are numbered from 1 so that the first button
--- endpoint is also the default endpoint, and is therefore mapped to the "main" component.
local function build_button_device(num_button_eps)
  local endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    }
  }
  for endpoint_id = 1, num_button_eps do
    table.insert(endpoints, {
      endpoint_id = endpoint_id,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH,
          cluster_type = "SERVER",
        }
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    })
  end
  return test.mock_device.build_test_matter_device({
    profile = t_utils.get_profile_definition(
      "button-modular.yml",
      { enabled_optional_capabilities = expected_optional_component_capabilities(num_button_eps) }
    ),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    matter_version = {hardware = 1, software = 1},
    endpoints = endpoints
  })
end

local function expected_component_to_endpoint_map(num_button_eps)
  local component_map = {main = 1}
  for component_num = 2, num_button_eps do
    component_map["button" .. component_num] = component_num
  end
  return component_map
end

local function expect_configure_buttons(device, num_button_eps)
  test.socket.capability:__expect_send(device:generate_test_message(
    "main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
  ))
  for component_num = 2, num_button_eps do
    test.socket.capability:__expect_send(device:generate_test_message(
      "button" .. component_num, capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})
    ))
  end
end

local mock_device_max_buttons = build_button_device(fields.MAX_BUTTON_EPS)
local mock_device_too_many_buttons = build_button_device(fields.MAX_BUTTON_EPS + 5)

local function build_test_init(device)
  return function()
    local cluster_subscribe_list = {
      clusters.Switch.server.events.InitialPress,
      clusters.Switch.server.events.LongPress,
      clusters.Switch.server.events.ShortRelease,
      clusters.Switch.server.events.MultiPressComplete,
    }
    local subscribe_request = cluster_subscribe_list[1]:subscribe(device)
    for i, cluster in ipairs(cluster_subscribe_list) do
      if i > 1 then subscribe_request:merge(cluster:subscribe(device)) end
    end

    test.disable_startup_messages()
    test.mock_device.add_test_device(device)
    device:set_field(fields.profiling_data.POWER_TOPOLOGY, false, {persist = true})
    test.socket.device_lifecycle:__queue_receive({device.id, "init"})
    test.socket.matter:__expect_send({device.id, subscribe_request})
  end
end

test.register_coroutine_test(
  "A device with more button endpoints than the static profiles supported is profiled modularly",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_device_max_buttons.id, "doConfigure"})
    expect_configure_buttons(mock_device_max_buttons, fields.MAX_BUTTON_EPS)
    mock_device_max_buttons:expect_metadata_update({
      profile = "button-modular",
      optional_component_capabilities = expected_optional_component_capabilities(fields.MAX_BUTTON_EPS)
    })
    mock_device_max_buttons:expect_metadata_update({provisioning_state = "PROVISIONED"})
    test.wait_for_events()
    assert(switch_utils.deep_equals(
      st_utils.deep_copy(mock_device_max_buttons:get_field(fields.COMPONENT_TO_ENDPOINT_MAP)),
      expected_component_to_endpoint_map(fields.MAX_BUTTON_EPS)
    ), "Every button endpoint should be mapped to a component")
  end,
  {
    test_init = build_test_init(mock_device_max_buttons),
    min_api_version = 15
  }
)

test.register_coroutine_test(
  "A device with more button endpoints than the modular profile supports is profiled with as many as will fit",
  function()
    test.socket.device_lifecycle:__queue_receive({mock_device_too_many_buttons.id, "doConfigure"})
    expect_configure_buttons(mock_device_too_many_buttons, fields.MAX_BUTTON_EPS)
    mock_device_too_many_buttons:expect_metadata_update({
      profile = "button-modular",
      optional_component_capabilities = expected_optional_component_capabilities(fields.MAX_BUTTON_EPS)
    })
    mock_device_too_many_buttons:expect_metadata_update({provisioning_state = "PROVISIONED"})
    test.wait_for_events()
    assert(switch_utils.deep_equals(
      st_utils.deep_copy(mock_device_too_many_buttons:get_field(fields.COMPONENT_TO_ENDPOINT_MAP)),
      expected_component_to_endpoint_map(fields.MAX_BUTTON_EPS)
    ), "Only the first MAX_BUTTON_EPS button endpoints should be mapped to a component")
  end,
  {
    test_init = build_test_init(mock_device_too_many_buttons),
    min_api_version = 15
  }
)

test.run_registered_tests()
