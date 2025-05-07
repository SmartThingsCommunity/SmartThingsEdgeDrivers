-- Copyright 2025 SmartThings
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

local capabilities = require "st.capabilities"
local clusters = require "st.matter.generated.zap_clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"

local TRANSITION_TIME = 0
local OPTIONS_MASK = 0x01
local OPTIONS_OVERRIDE = 0x01
local button_attr = capabilities.button.button

local mock_device_ep1 = 1
local mock_device_ep2 = 2
local mock_device_ep3 = 3
local mock_device_ep4 = 4
local mock_device_ep5 = 5
local mock_device_ep6 = 6

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("inovelli-vtm31-sn.yml"),
  manufacturer_info = {
    vendor_id = 0x1361,
    product_id = 0x0001,
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
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = 0x122FFC31, cluster_type = "SERVER"} -- Manufacturer Specific cluster
      },
      device_types = {
        {device_type_id = 0x0101, device_type_revision = 2} -- Dimmable Light
      }
    },
    {
      endpoint_id = mock_device_ep2,
      clusters = {
        {cluster_id = 0x001E, cluster_type = "SERVER"}, -- Binding cluster
        {cluster_id = clusters.ModeSelect.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0104, device_type_revision = 2} -- Dimmer Switch
      }
    },
    {
      endpoint_id = mock_device_ep3,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
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
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
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
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_RELEASE |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = mock_device_ep6,
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

local child_profile = t_utils.get_profile_definition("light-color-level.yml")
local child_data = {
  profile = child_profile,
  device_network_id = string.format("%s:%d", mock_device.id, mock_device_ep6),
  parent_device_id = mock_device.id,
  parent_assigned_child_key = string.format("%d", mock_device_ep6)
}
local mock_child = test.mock_device.build_test_child_device(child_data)

local function configure_buttons()
  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, mock_device_ep3)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("button1", button_attr.pushed({state_change = false})))

  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, mock_device_ep4)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("button2", button_attr.pushed({state_change = false})))

  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, mock_device_ep5)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("button3", button_attr.pushed({state_change = false})))
end

local function test_init()
  local cluster_subscribe_list ={
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
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, clus in ipairs(cluster_subscribe_list) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ profile = "inovelli-vtm31-sn" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  configure_buttons()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_child)
  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-color-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", mock_device_ep6)
  })
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
  "First button component: Short release does not emit event if MultiPressComplete is not received",
  {
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
    }
  }
)

test.register_coroutine_test(
  "Second button component: Handle single press sequence for a long hold on long-release-capable button",
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
      clusters.Switch.events.LongPress:build_test_event_report(
        mock_device, mock_device_ep4, {new_position = 0}
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("button2", button_attr.held({state_change = true})))
  end
)

test.register_message_test(
  "Receiving a max press attribute of 5 should emit correct event", {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Switch.attributes.MultiPressMax:build_test_report_data(
          mock_device, mock_device_ep4, 5
        )
      },
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("button2",
        capabilities.button.supportedButtonValues({"pushed", "double", "held", "pushed_3x", "pushed_4x", "pushed_5x"}, {visibility = {displayed = false}}))
    }
  }
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
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, mock_device_ep6, 556, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature:build_test_command_response(mock_device, mock_device_ep6)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, mock_device_ep6, 556)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.colorTemperature.colorTemperature(1799))
    },
  }
)

test.register_coroutine_test(
  "Test driver switched event",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
    mock_device:expect_metadata_update({ profile = "inovelli-vtm31-sn" })
    configure_buttons()
    mock_device:expect_device_create({
      type = "EDGE_CHILD",
      label = "Matter Switch 2",
      profile = "light-color-level",
      parent_device_id = mock_device.id,
      parent_assigned_child_key = string.format("%d", mock_device_ep6)
    })
  end
)

-- run the tests
test.run_registered_tests()
