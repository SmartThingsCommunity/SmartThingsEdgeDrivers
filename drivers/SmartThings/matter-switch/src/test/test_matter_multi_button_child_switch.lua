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
local utils = require "st.utils"
local dkjson = require "dkjson"

local clusters = require "st.matter.clusters"

local light1_ep = 10
local button1_ep = 20
local button2_ep = 30
local light2_ep = 40

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("2-button-battery.yml"),
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
      endpoint_id = light1_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31}
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    },
    {
      endpoint_id = button1_ep,
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
    {
      endpoint_id = button2_ep,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
              clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
              clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = light2_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 2}, -- On/Off Light
        {device_type_id = 0x0101, device_type_revision = 2} -- Dimmable Light
      }
    }
  }
})

local child_profiles = {
  [light1_ep] = t_utils.get_profile_definition("light-color-level.yml"),
  [light2_ep] = t_utils.get_profile_definition("light-level.yml")
}

local mock_children = {}
for i, endpoint in ipairs(mock_device.endpoints) do
  if endpoint.endpoint_id ~= button1_ep and endpoint.endpoint_id ~= button2_ep and endpoint.endpoint_id ~= 0 then
    local child_data = {
      profile = child_profiles[endpoint.endpoint_id],
      device_network_id = string.format("%s:%d", mock_device.id, endpoint.endpoint_id),
      parent_device_id = mock_device.id,
      parent_assigned_child_key = string.format("%d", endpoint.endpoint_id)
    }
    mock_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data)
  end
end

local function test_init()
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
    clusters.PowerSource.server.attributes.BatPercentRemaining,
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.mock_device.add_test_device(mock_device)
  mock_device:expect_metadata_update({ profile = "2-button-battery" })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))

  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 1",
    profile = "light-color-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", light1_ep)
  })

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", light2_ep)
  })

  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, button2_ep)})
  local device_info_copy = utils.deep_copy(mock_device.raw_st_data)
  device_info_copy.profile.id = "2-buttons-battery-switch"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "infoChanged", device_info_json })
  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", capabilities.button.button.pushed({state_change = false})))
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Parent MCD device: handle single press sequence, no hold", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.events.InitialPress:build_test_event_report(
          mock_device, button1_ep, {new_position = 1}  --move to position 1?
        ),
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.button.button.pushed({state_change = true})) --should send initial press
    }
  }
)

test.register_coroutine_test(
  "Parent MCD device: handle single press sequence for a multi press on multi button",
  function ()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device, button2_ep, {previous_position = 0}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device, button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.MultiPressOngoing:build_test_event_report(
        mock_device, button2_ep, {new_position = 1, current_number_of_presses_counted = 2}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device, button2_ep, {new_position = 0, total_number_of_presses_counted = 2, previous_position = 1}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button2", capabilities.button.button.double({state_change = true})))
  end
)

test.register_message_test(
  "First child device: switch capability should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[light1_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_children[light1_ep].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, light1_ep)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, light1_ep, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[light1_ep]:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)
test.register_message_test(
  "Second child device: switch capability should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[light2_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    },
    {
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_children[light2_ep].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, light2_ep)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, light2_ep, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[light2_ep]:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.run_registered_tests()
