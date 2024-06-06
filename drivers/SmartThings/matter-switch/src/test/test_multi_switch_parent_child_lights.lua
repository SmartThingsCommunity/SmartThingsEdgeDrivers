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
local TRANSITION_TIME = 0
local OPTIONS_MASK = 0x01
local OPTIONS_OVERRIDE = 0x01

local parent_ep = 10
local child1_ep = 20
local child2_ep = 30

local mock_device = test.mock_device.build_test_matter_device({
  label = "Matter Switch",
  profile = t_utils.get_profile_definition("light-level-colorTemperature.yml"),
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
      endpoint_id = child1_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 2}, -- On/Off Light
        {device_type_id = 0x0101, device_type_revision = 2} -- Dimmable Light
      }
    },
    {
      endpoint_id = child2_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 30},
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    },
  }
})

local child_profiles = {
  [child1_ep] = t_utils.get_profile_definition("light-level.yml"),
  [child2_ep] = t_utils.get_profile_definition("light-color-level.yml")
}

local mock_children = {}
for i, endpoint in ipairs(mock_device.endpoints) do
  if endpoint.endpoint_id ~= parent_ep and endpoint.endpoint_id ~= 0 then
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
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.mock_device.add_test_device(mock_device)
  for _, child in pairs(mock_children) do
    test.mock_device.add_test_device(child)
  end

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", child1_ep)
  })

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 3",
    profile = "light-color-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", child2_ep)
  })
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
  "First child device: switch capability switch should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[child1_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, child1_ep)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, child1_ep, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child1_ep]:generate_test_message("main", capabilities.switch.switch.on())
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
        mock_children[child2_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.OnOff.server.commands.On(mock_device, child2_ep)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device, child2_ep, true)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Current level reports should generate appropriate events",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.server.attributes.CurrentLevel:build_test_report_data(mock_device, child1_ep, 50)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child1_ep]:generate_test_message("main", capabilities.switchLevel.level(math.floor((50 / 254.0 * 100) + 0.5)))
    },
  }
)

test.register_message_test(
  "Set color temperature should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[child2_ep].id,
        { capability = "colorTemperature", component = "main", command = "setColorTemperature", args = {1800} }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature(mock_device, child2_ep, 556, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColorTemperature:build_test_command_response(mock_device, child2_ep)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTemperatureMireds:build_test_report_data(mock_device, child2_ep, 556)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.colorTemperature.colorTemperature(1800))
    },
  }
)

test.register_message_test(
  "X and Y color values should report hue and saturation once both have been received",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, child2_ep, 15091)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, child2_ep, 21547)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.colorControl.saturation(72))
    }
  }
)

test.register_message_test(
  "Set color command should send the appropriate commands",
  {
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_children[child2_ep].id,
        { capability = "colorControl", component = "main", command = "setColor", args = { { hue = 50, saturation = 72 } } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColor(mock_device, child2_ep, 15182, 21547, TRANSITION_TIME, OPTIONS_MASK, OPTIONS_OVERRIDE)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.server.commands.MoveToColor:build_test_command_response(mock_device, child2_ep)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentX:build_test_report_data(mock_device, child2_ep, 15091)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.CurrentY:build_test_report_data(mock_device, child2_ep, 21547)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.colorControl.hue(50))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.colorControl.saturation(72))
    }
  }
)

test.register_message_test(
  "Min and max level attributes set capability constraint for child devices",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MinLevel:build_test_report_data(mock_device, child1_ep, 1)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MaxLevel:build_test_report_data(mock_device, child1_ep, 254)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child1_ep]:generate_test_message("main", capabilities.switchLevel.levelRange({minimum = 1, maximum = 100}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MinLevel:build_test_report_data(mock_device, child2_ep, 127)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.LevelControl.attributes.MaxLevel:build_test_report_data(mock_device, child2_ep, 203)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.switchLevel.levelRange({minimum = 50, maximum = 80}))
    }
  }
)

test.register_message_test(
  "Min and max color temp attributes set capability constraint for child devices",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds:build_test_report_data(mock_device, child2_ep, 153)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds:build_test_report_data(mock_device, child2_ep, 555)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_children[child2_ep]:generate_test_message("main", capabilities.colorTemperature.colorTemperatureRange({minimum = 1800, maximum = 6500}))
    }
  }
)

test.run_registered_tests()
