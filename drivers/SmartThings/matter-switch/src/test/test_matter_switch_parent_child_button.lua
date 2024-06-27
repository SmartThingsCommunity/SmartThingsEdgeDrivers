-- Copyright 2024 SmartThings
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
local capabilities = require "st.capabilities"

local clusters = require "st.matter.clusters"

local parent_ep = 10
local child_ep = 20

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("switch-level.yml"),
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
      endpoint_id = parent_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 2} -- On/Off Light
      }
    },
    {
      endpoint_id = child_ep,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH,
          cluster_type = "SERVER"
        },
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY}
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
  }
})

local child_profile = t_utils.get_profile_definition("button-battery.yml")

local child_data = {
  profile = child_profile,
  device_network_id = string.format("%s:%d", mock_device.id, child_ep),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%d", child_ep)
}
local mock_child = test.mock_device.build_test_child_device(child_data)

local function test_init()
  test.socket.matter:__set_channel_ordering("relaxed")
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end

  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_child)

  cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.PowerSource.server.attributes.BatPercentRemaining,
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete,
  }
  subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", child_ep)
  })
  test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_child:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Parent device: switch capability should send the appropriate commands",
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
        clusters.OnOff.server.commands.On(mock_device, parent_ep)
      },
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, parent_ep, true)
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
  "Child device: Handle single press sequence, no hold",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
            mock_device, child_ep, {new_position = 1}
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
    }
  }
)

test.run_registered_tests()
