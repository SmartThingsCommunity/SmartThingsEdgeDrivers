-- Copyright 2022 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

local mock_3switch = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-binary.yml"),
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
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
    {
      endpoint_id = 3,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
  }
})

local mock_2switch = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-binary.yml"),
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
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
  }
})

local mock_3switch_non_sequential = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-binary.yml"),
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
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 10,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
    {
      endpoint_id = 14,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
    {
      endpoint_id = 15,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0100, device_type_revision = 2, -- On/Off Light
      }
    },
  }
})


local function test_init()
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_3switch)
  test.socket.matter:__expect_send({mock_3switch.id, subscribe_request})
  test.mock_device.add_test_device(mock_3switch)
  test.socket.device_lifecycle:__queue_receive({ mock_3switch.id, "added" })
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_2switch)
  test.socket.matter:__expect_send({mock_2switch.id, subscribe_request})
  test.mock_device.add_test_device(mock_2switch)
  test.socket.device_lifecycle:__queue_receive({ mock_2switch.id, "added" })
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_3switch_non_sequential)
  test.socket.matter:__expect_send({mock_3switch_non_sequential.id, subscribe_request})
  test.mock_device.add_test_device(mock_3switch_non_sequential)
  test.socket.device_lifecycle:__queue_receive({ mock_3switch_non_sequential.id, "added" })
end
test.set_test_init_function(test_init)


test.register_coroutine_test(
  "Profile change for 3 switch device", function()
    test.socket.device_lifecycle:__queue_receive({ mock_3switch.id, "doConfigure" })
    mock_3switch:expect_metadata_update({ profile = "switch-3" })
    mock_3switch:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end)

test.register_coroutine_test(
  "Profile change for 2 switch device", function()
    test.socket.device_lifecycle:__queue_receive({ mock_2switch.id, "doConfigure" })
    mock_2switch:expect_metadata_update({ profile = "switch-2" })
    mock_2switch:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end)

test.register_coroutine_test(
  "Profile change for 3 switch device with non sequential endpoints", function()
    test.socket.device_lifecycle:__queue_receive({ mock_3switch_non_sequential.id, "doConfigure" })
    mock_3switch_non_sequential:expect_metadata_update({ profile = "switch-3" })
    mock_3switch_non_sequential:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end)

test.register_message_test(
  "On command to component switch should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_3switch.id,
        { capability = "switch", component = "switch2", command = "on", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_3switch.id,
        clusters.OnOff.server.commands.On(mock_3switch, 2)
      }
    }
  }
)

test.register_message_test(
  "On command to component switch should send the appropriate commands for devices with non-sequential endpoints",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_3switch_non_sequential.id,
        { capability = "switch", component = "switch3", command = "on", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_3switch_non_sequential.id,
        clusters.OnOff.server.commands.On(mock_3switch_non_sequential, 15) -- switch 3 is on endpoint 15
      }
    }
  }
)

test.run_registered_tests()
