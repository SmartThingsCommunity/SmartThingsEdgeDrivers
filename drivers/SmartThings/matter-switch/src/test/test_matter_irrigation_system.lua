-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"
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
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
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
      profile = t_utils.get_profile_definition("irrigation-system.yml"),
      device_network_id = string.format("%s:%d", mock_irrigation_system.id, endpoint.endpoint_id),
      parent_device_id = mock_irrigation_system.id,
      parent_assigned_child_key = string.format("%d", endpoint.endpoint_id)
    }
    mock_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data)
  end
end

local function test_init()
  test.mock_device.add_test_device(mock_irrigation_system)
  local cluster_subscribe_list = {
    clusters.ValveConfigurationAndControl.attributes.CurrentState,
    clusters.ValveConfigurationAndControl.attributes.CurrentLevel
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_irrigation_system)
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
      label = string.format("Matter Irrigation System Valve %d", i - 2),
      profile = "water-valve-level",
      parent_device_id = mock_irrigation_system.id,
      parent_assigned_child_key = string.format("%d", i)
    })
  end
  test.socket.matter:__expect_send({mock_irrigation_system.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_irrigation_system.id, "doConfigure" })
  mock_irrigation_system:expect_metadata_update({ profile = "irrigation-system" })
  mock_irrigation_system:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init)

test.register_message_test(
  "Parent device: Open command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_irrigation_system.id,
        { capability = "valve", component = "main", command = "open", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_1_EP)
      }
    }
  }
)

test.register_message_test(
  "Parent device: Close command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_irrigation_system.id,
        { capability = "valve", component = "main", command = "close", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.commands.Close(mock_irrigation_system, endpoints.VALVE_1_EP)
      }
    }
  }
)

test.register_message_test(
  "Parent device: Set level command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_irrigation_system.id,
        { capability = "level", component = "main", command = "setLevel", args = { 75 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_1_EP, nil, 75)
      }
    }
  }
)

test.register_message_test(
  "Parent device: Current state closed should generate closed event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.attributes.CurrentState:build_test_report_data(mock_irrigation_system, endpoints.VALVE_1_EP, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_irrigation_system:generate_test_message("main", capabilities.valve.valve.closed())
    },
  }
)

test.register_message_test(
  "Parent device: Current level reports should generate appropriate events",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.attributes.CurrentLevel:build_test_report_data(mock_irrigation_system, endpoints.VALVE_1_EP, 60)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_irrigation_system:generate_test_message("main", capabilities.level.level(60))
    },
  }
)

test.register_message_test(
  "Child device valve 2: Open command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[endpoints.VALVE_2_EP].id,
        { capability = "valve", component = "main", command = "open", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_2_EP)
      }
    }
  }
)

test.register_message_test(
  "Child device valve 2: Set level command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[endpoints.VALVE_2_EP].id,
        { capability = "level", component = "main", command = "setLevel", args = { 40 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.commands.Open(mock_irrigation_system, endpoints.VALVE_2_EP, nil, 40)
      }
    }
  }
)

test.register_message_test(
  "Child device valve 2: Current state closed should generate closed event",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.attributes.CurrentState:build_test_report_data(mock_irrigation_system, endpoints.VALVE_2_EP, 0)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[endpoints.VALVE_2_EP]:generate_test_message("main", capabilities.valve.valve.closed())
    },
  }
)

test.register_message_test(
  "Child device valve 3: Close command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[endpoints.VALVE_3_EP].id,
        { capability = "valve", component = "main", command = "close", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.commands.Close(mock_irrigation_system, endpoints.VALVE_3_EP)
      }
    }
  }
)

test.register_message_test(
  "Child device valve 3: Current level reports should generate appropriate events",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_irrigation_system.id,
        clusters.ValveConfigurationAndControl.server.attributes.CurrentLevel:build_test_report_data(mock_irrigation_system, endpoints.VALVE_3_EP, 100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[endpoints.VALVE_3_EP]:generate_test_message("main", capabilities.level.level(100))
    },
  }
)

test.run_registered_tests()

