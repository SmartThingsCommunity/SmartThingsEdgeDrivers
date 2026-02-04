-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local version = require "version"

if version.api < 11 then
  clusters.ValveConfigurationAndControl = require "embedded_clusters.ValveConfigurationAndControl"
end

local endpoints = {
  ROOT_EP = 0,
  IRRIGATION_SYSTEM_EP = 1,
  VALVE_1_EP = 2,
  VALVE_2_EP = 3,
  VALVE_3_EP = 4
}

-- Mock device representing an irrigation system with 3 valve endpoints
local mock_irrigation_system = test.mock_device.build_test_matter_device({
  label = "Matter Irrigation System",
  profile = t_utils.get_profile_definition("irrigation-system.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware = 1, software = 1},
  endpoints = {
    {
      endpoint_id = endpoints.ROOT_EP,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
      }
    },
    {
      endpoint_id = endpoints.IRRIGATION_SYSTEM_EP,
      clusters = {
        {cluster_id = clusters.Descriptor.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0040, device_type_revision = 1} -- Irrigation System
      }
    },
    {
      endpoint_id = endpoints.VALVE_1_EP,
      clusters = {
        {
          cluster_id = clusters.ValveConfigurationAndControl.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 2 -- LEVEL feature
        },
      },
      device_types = {
        {device_type_id = 0x0042, device_type_revision = 1} -- Water Valve
      }
    },
    {
      endpoint_id = endpoints.VALVE_2_EP,
      clusters = {
        {
          cluster_id = clusters.ValveConfigurationAndControl.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 2 -- LEVEL feature
        },
      },
      device_types = {
        {device_type_id = 0x0042, device_type_revision = 1} -- Water Valve
      }
    },
    {
      endpoint_id = endpoints.VALVE_3_EP,
      clusters = {
        {
          cluster_id = clusters.ValveConfigurationAndControl.ID,
          cluster_type = "SERVER",
          cluster_revision = 1,
          feature_map = 2 -- LEVEL feature
        },
      },
      device_types = {
        {device_type_id = 0x0042, device_type_revision = 1} -- Water Valve
      }
    }
  }
})

local mock_children = {}
for i, endpoint in ipairs(mock_irrigation_system.endpoints) do
  if endpoint.endpoint_id == 3 or endpoint.endpoint_id == 4 then
    local child_data = {
      profile = t_utils.get_profile_definition("water-valve-level.yml"),
      device_network_id = string.format("%s:%d", mock_irrigation_system.id, endpoint.endpoint_id),
      parent_device_id = mock_irrigation_system.id,
      parent_assigned_child_key = string.format("%d", endpoint.endpoint_id)
    }
    mock_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data)
  end
end

local subscribe_request

local function test_init()
  test.mock_device.add_test_device(mock_irrigation_system)
  local cluster_subscribe_list = {
    clusters.ValveConfigurationAndControl.attributes.CurrentState,
    clusters.ValveConfigurationAndControl.attributes.CurrentLevel,
  }
  subscribe_request = cluster_subscribe_list[1]:subscribe(mock_irrigation_system)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_irrigation_system))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_irrigation_system.id, "added" })
  test.socket.matter:__expect_send({mock_irrigation_system.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_irrigation_system.id, "init" })
  test.socket.matter:__expect_send({mock_irrigation_system.id, subscribe_request})
  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end
  for i = 3,4 do
    mock_irrigation_system:expect_device_create({
      type = "EDGE_CHILD",
      label = string.format("Matter Irrigation System %d", i - 1),
      profile = "water-valve-level",
      parent_device_id = mock_irrigation_system.id,
      parent_assigned_child_key = string.format("%d", i)
    })
  end
  test.socket.matter:__expect_send({mock_irrigation_system.id, subscribe_request})
end
test.set_test_init_function(test_init)


local additional_subscribed_attributes = {
}

local expected_metadata = {
  optional_component_capabilities = {
    {
      "main",
      {
        "level",
      }
    },
  },
  profile = "irrigation-system"
}

local function update_device_profile()
  test.socket.device_lifecycle:__queue_receive({ mock_irrigation_system.id, "doConfigure" })
  mock_irrigation_system:expect_metadata_update(expected_metadata)
  mock_irrigation_system:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local updated_device_profile = t_utils.get_profile_definition(
    "irrigation-system.yml", { enabled_optional_capabilities = expected_metadata.optional_component_capabilities }
  )
  test.wait_for_events()
  test.socket.device_lifecycle:__queue_receive(mock_irrigation_system:generate_info_changed({ profile = updated_device_profile }))
  for _, attr in ipairs(additional_subscribed_attributes) do
    subscribe_request:merge(attr:subscribe(mock_irrigation_system))
  end
  test.socket.matter:__expect_send({mock_irrigation_system.id, subscribe_request})
end

test.register_coroutine_test(
  "Parent device: Open command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_irrigation_system.id,
      { capability = "valve", component = "main", command = "open", args = { } }
    })

    test.socket.matter:__expect_send({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_1_EP)
    })
  end
)

test.register_coroutine_test(
  "Parent device: Close command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_irrigation_system.id,
      { capability = "valve", component = "main", command = "close", args = { } }
    })

    test.socket.matter:__expect_send({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.commands.Close(mock_irrigation_system, endpoints.VALVE_1_EP)
    })
  end
)

test.register_coroutine_test(
  "Parent device: Set level command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_irrigation_system.id,
      { capability = "level", component = "main", command = "setLevel", args = { 75 } }
    })
    test.socket.matter:__expect_send({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_1_EP, nil, 75)
    })
  end
)

test.register_coroutine_test(
  "Parent device: Current state closed should generate closed event",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.attributes.CurrentState:build_test_report_data(
        mock_irrigation_system,
        endpoints.VALVE_1_EP,
        0
      )
    })
    test.socket.capability:__expect_send(
      mock_irrigation_system:generate_test_message("main", capabilities.valve.valve.closed())
    )
  end
)

test.register_coroutine_test(
  "Parent device: Current level reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.attributes.CurrentLevel:build_test_report_data(
        mock_irrigation_system,
        endpoints.VALVE_1_EP,
        60
      )
    })
    test.socket.capability:__expect_send(
      mock_irrigation_system:generate_test_message("main", capabilities.level.level(60))
    )
  end
)

test.register_coroutine_test(
  "Child device valve 2: Open command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_children[endpoints.VALVE_2_EP].id,
      { capability = "valve", component = "main", command = "open", args = { } }
    })
    test.socket.matter:__expect_send({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_2_EP)
    })
  end
)

test.register_coroutine_test(
  "Child device valve 2: Set level command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_children[endpoints.VALVE_2_EP].id,
      { capability = "level", component = "main", command = "setLevel", args = { 40 } }
    })
    test.socket.matter:__expect_send({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_2_EP, nil, 40)
    })
  end
)

test.register_coroutine_test(
  "Child device valve 2: Current state closed should generate closed event",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.attributes.CurrentState:build_test_report_data(
        mock_irrigation_system,
        endpoints.VALVE_2_EP,
        0
      )
    })
    test.socket.capability:__expect_send(
      mock_children[endpoints.VALVE_2_EP]:generate_test_message("main", capabilities.valve.valve.closed())
    )
  end
)

test.register_coroutine_test(
  "Child device valve 3: Close command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_children[endpoints.VALVE_3_EP].id,
      { capability = "valve", component = "main", command = "close", args = { } }
    })
    test.socket.matter:__expect_send({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.commands.Close(mock_irrigation_system, endpoints.VALVE_3_EP)
    })
  end
)

test.register_coroutine_test(
  "Child device valve 3: Current level reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_irrigation_system.id,
      clusters.ValveConfigurationAndControl.server.attributes.CurrentLevel:build_test_report_data(
        mock_irrigation_system,
        endpoints.VALVE_3_EP,
        100
      )
    })
    test.socket.capability:__expect_send(
      mock_children[endpoints.VALVE_3_EP]:generate_test_message("main", capabilities.level.level(100))
    )
  end
)

test.run_registered_tests()

