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

-- Three mock devices are used to test the functionality of three different endpoint configurations:
-- (1) single switch endpoint and multiple button endpoints,
-- (2) multiple switch endpoints and multiple button endpoints (with the button enpoints lower than the switch endpoints), and
-- (3) multiple switch endpoints and multiple button endpoints (with the switch enpoints lower than the button endpoints)

-- Configuration 1: Single switch endpoint and multiple button endpoints

local configuration_1_button1_ep = 10
local configuration_1_button2_ep = 20
local configuration_1_light_ep = 30

local mock_device_configuration_1 = test.mock_device.build_test_matter_device({
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
      endpoint_id = configuration_1_button1_ep,
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
      endpoint_id = configuration_1_button2_ep,
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
      endpoint_id = configuration_1_light_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 31}
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    }
  }
})

local child_profile = t_utils.get_profile_definition("light-color-level.yml")

local child_data = {
  profile = child_profile,
  device_network_id = string.format("%s:%d", mock_device_configuration_1.id, configuration_1_light_ep),
  parent_device_id = mock_device_configuration_1.id,
  parent_assigned_child_key = string.format("%d", configuration_1_light_ep)
}
local mock_device_configuration_1_child = test.mock_device.build_test_child_device(child_data)

-- Configuration 2: Multiple switch endpoints and multiple button endpoints; button endpoints lower than the switch endpoints

local configuration_2_button1_ep = 10
local configuration_2_button2_ep = 20
local configuration_2_light1_ep = 30
local configuration_2_light2_ep = 40

local mock_device_configuration_2 = test.mock_device.build_test_matter_device({
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
      endpoint_id = configuration_2_button1_ep,
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
      endpoint_id = configuration_2_button2_ep,
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
      endpoint_id = configuration_2_light1_ep,
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
      endpoint_id = configuration_2_light2_ep,
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

local child_profiles_configuration_2 = {
  [configuration_2_light1_ep] = t_utils.get_profile_definition("light-color-level.yml"),
  [configuration_2_light2_ep] = t_utils.get_profile_definition("light-level.yml")
}

local mock_device_configuration_2_children = {}
for i, endpoint in ipairs(mock_device_configuration_2.endpoints) do
  if endpoint.endpoint_id ~= configuration_2_button1_ep and endpoint.endpoint_id ~= configuration_2_button2_ep and endpoint.endpoint_id ~= 0 then
    local child_data_configuration2 = {
      profile = child_profiles_configuration_2[endpoint.endpoint_id],
      device_network_id = string.format("%s:%d", mock_device_configuration_2.id, endpoint.endpoint_id),
      parent_device_id = mock_device_configuration_2.id,
      parent_assigned_child_key = string.format("%d", endpoint.endpoint_id)
    }
    mock_device_configuration_2_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data_configuration2)
  end
end

-- Configuration 3: Multiple switch endpoints and multiple button endpoints; switch endpoints lower than the button endpoints

local configuration_3_light1_ep = 10
local configuration_3_light2_ep = 20
local configuration_3_button1_ep = 30
local configuration_3_button2_ep = 40

local mock_device_configuration_3 = test.mock_device.build_test_matter_device({
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
      endpoint_id = configuration_3_light1_ep,
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
      endpoint_id = configuration_3_light2_ep,
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
      endpoint_id = configuration_3_button1_ep,
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
      endpoint_id = configuration_3_button2_ep,
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
    }
  }
})

local child_profiles_configuration_3 = {
  [configuration_3_light1_ep] = t_utils.get_profile_definition("light-color-level.yml"),
  [configuration_3_light2_ep] = t_utils.get_profile_definition("light-level.yml")
}

local mock_device_configuration_3_children = {}
for i, endpoint in ipairs(mock_device_configuration_3.endpoints) do
  if endpoint.endpoint_id ~= configuration_3_button1_ep and endpoint.endpoint_id ~= configuration_3_button2_ep and endpoint.endpoint_id ~= 0 then
    local child_data_configuration3 = {
      profile = child_profiles_configuration_3[endpoint.endpoint_id],
      device_network_id = string.format("%s:%d", mock_device_configuration_3.id, endpoint.endpoint_id),
      parent_device_id = mock_device_configuration_3.id,
      parent_assigned_child_key = string.format("%d", endpoint.endpoint_id)
    }
    mock_device_configuration_3_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data_configuration3)
  end
end

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

local function test_init_configuration_1()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_configuration_1)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_configuration_1))
    end
  end
  test.socket.matter:__expect_send({mock_device_configuration_1.id, subscribe_request})

  test.mock_device.add_test_device(mock_device_configuration_1)
  mock_device_configuration_1:expect_metadata_update({ profile = "2-button-battery" })
  test.socket.capability:__expect_send(mock_device_configuration_1:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device_configuration_1:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))

  test.mock_device.add_test_device(mock_device_configuration_1_child)

  mock_device_configuration_1:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 1",
    profile = "light-color-level",
    parent_device_id = mock_device_configuration_1.id,
    parent_assigned_child_key = string.format("%d", configuration_1_light_ep)
  })

  test.socket.matter:__expect_send({mock_device_configuration_1.id, subscribe_request})

  test.socket.matter:__expect_send({mock_device_configuration_1.id, clusters.Switch.attributes.MultiPressMax:read(mock_device_configuration_1, configuration_1_button2_ep)})
  local device_info_copy = utils.deep_copy(mock_device_configuration_1.raw_st_data)
  device_info_copy.profile.id = "2-buttons-battery-switch"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device_configuration_1.id, "infoChanged", device_info_json })
  test.socket.capability:__expect_send(mock_device_configuration_1:generate_test_message("button2", capabilities.button.button.pushed({state_change = false})))
end

local function test_init_configuration_2()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_configuration_2)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_configuration_2))
    end
  end
  test.socket.matter:__expect_send({mock_device_configuration_2.id, subscribe_request})

  test.mock_device.add_test_device(mock_device_configuration_2)
  mock_device_configuration_2:expect_metadata_update({ profile = "2-button-battery" })
  test.socket.capability:__expect_send(mock_device_configuration_2:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device_configuration_2:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))

  for _, child in pairs(mock_device_configuration_2_children) do
    test.mock_device.add_test_device(child)
  end

  mock_device_configuration_2:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 1",
    profile = "light-color-level",
    parent_device_id = mock_device_configuration_2.id,
    parent_assigned_child_key = string.format("%d", configuration_2_light1_ep)
  })

  mock_device_configuration_2:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-level",
    parent_device_id = mock_device_configuration_2.id,
    parent_assigned_child_key = string.format("%d", configuration_2_light2_ep)
  })

  test.socket.matter:__expect_send({mock_device_configuration_2.id, subscribe_request})

  test.socket.matter:__expect_send({mock_device_configuration_2.id, clusters.Switch.attributes.MultiPressMax:read(mock_device_configuration_2, configuration_2_button2_ep)})
  local device_info_copy = utils.deep_copy(mock_device_configuration_2.raw_st_data)
  device_info_copy.profile.id = "2-buttons-battery-switch"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device_configuration_2.id, "infoChanged", device_info_json })
  test.socket.capability:__expect_send(mock_device_configuration_2:generate_test_message("button2", capabilities.button.button.pushed({state_change = false})))
end

local function test_init_configuration_3()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device_configuration_3)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device_configuration_3))
    end
  end
  test.socket.matter:__expect_send({mock_device_configuration_3.id, subscribe_request})

  test.mock_device.add_test_device(mock_device_configuration_3)
  mock_device_configuration_3:expect_metadata_update({ profile = "2-button-battery" })
  test.socket.capability:__expect_send(mock_device_configuration_3:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(mock_device_configuration_3:generate_test_message("main", capabilities.button.button.pushed({state_change = false})))

  for _, child in pairs(mock_device_configuration_3_children) do
    test.mock_device.add_test_device(child)
  end

  mock_device_configuration_3:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 1",
    profile = "light-color-level",
    parent_device_id = mock_device_configuration_3.id,
    parent_assigned_child_key = string.format("%d", configuration_3_light1_ep)
  })

  mock_device_configuration_3:expect_device_create({
    type = "EDGE_CHILD",
    label = "Matter Switch 2",
    profile = "light-level",
    parent_device_id = mock_device_configuration_3.id,
    parent_assigned_child_key = string.format("%d", configuration_3_light2_ep)
  })

  test.socket.matter:__expect_send({mock_device_configuration_3.id, subscribe_request})

  test.socket.matter:__expect_send({mock_device_configuration_3.id, clusters.Switch.attributes.MultiPressMax:read(mock_device_configuration_3, configuration_3_button2_ep)})
  local device_info_copy = utils.deep_copy(mock_device_configuration_3.raw_st_data)
  device_info_copy.profile.id = "2-buttons-battery-switch"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ mock_device_configuration_3.id, "infoChanged", device_info_json })
  test.socket.capability:__expect_send(mock_device_configuration_3:generate_test_message("button2", capabilities.button.button.pushed({state_change = false})))
end

test.register_coroutine_test(
  "Configuration 1: Parent device: handle single press sequence",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_1.id,
        clusters.Switch.events.InitialPress:build_test_event_report(mock_device_configuration_1, configuration_1_button1_ep, {new_position = 1}),
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_1:generate_test_message(
        "main", capabilities.button.button.pushed({state_change = true})
      )
    )
  end,
  { test_init = test_init_configuration_1 }
)

test.register_coroutine_test(
  "Configuration 1: Parent device: handle single press sequence for a multi press on multi button",
  function ()
    test.socket.matter:__queue_receive({
      mock_device_configuration_1.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device_configuration_1, configuration_1_button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_1.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device_configuration_1, configuration_1_button2_ep, {previous_position = 0}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_1.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device_configuration_1, configuration_1_button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_1.id,
      clusters.Switch.events.MultiPressOngoing:build_test_event_report(
        mock_device_configuration_1, configuration_1_button2_ep, {new_position = 1, current_number_of_presses_counted = 2}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_1.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device_configuration_1, configuration_1_button2_ep, {new_position = 0, total_number_of_presses_counted = 2, previous_position = 1}
      )
    })
    test.socket.capability:__expect_send(mock_device_configuration_1:generate_test_message("button2", capabilities.button.button.double({state_change = true})))
  end,
  { test_init = test_init_configuration_1 }
)

test.register_coroutine_test(
  "Configuration 2: First child device: switch capability should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_configuration_2_children[configuration_2_light1_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } },
      }
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device_configuration_2_children[configuration_2_light1_ep].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device_configuration_2.id, clusters.OnOff.server.commands.On(mock_device_configuration_2, configuration_2_light1_ep)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_2.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device_configuration_2, configuration_2_light1_ep, false)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_2_children[configuration_2_light1_ep]:generate_test_message(
        "main", capabilities.switch.switch.off()
      )
    )
  end,
  { test_init = test_init_configuration_2 }
)

test.register_coroutine_test(
  "Configuration 2: Parent device: handle single press sequence",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_2.id,
        clusters.Switch.events.InitialPress:build_test_event_report(mock_device_configuration_2, configuration_2_button1_ep, {new_position = 1}),
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_2:generate_test_message(
        "main", capabilities.button.button.pushed({state_change = true})
      )
    )
  end,
  { test_init = test_init_configuration_2 }
)

test.register_coroutine_test(
  "Configuration 2: Parent device: handle single press sequence for a multi press on multi button",
  function ()
    test.socket.matter:__queue_receive({
      mock_device_configuration_2.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device_configuration_2, configuration_2_button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_2.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device_configuration_2, configuration_2_button2_ep, {previous_position = 0}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_2.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device_configuration_2, configuration_2_button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_2.id,
      clusters.Switch.events.MultiPressOngoing:build_test_event_report(
        mock_device_configuration_2, configuration_2_button2_ep, {new_position = 1, current_number_of_presses_counted = 2}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_2.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device_configuration_2, configuration_2_button2_ep, {new_position = 0, total_number_of_presses_counted = 2, previous_position = 1}
      )
    })
    test.socket.capability:__expect_send(mock_device_configuration_2:generate_test_message("button2", capabilities.button.button.double({state_change = true})))
  end,
  { test_init = test_init_configuration_2 }
)

test.register_coroutine_test(
  "Configuration 2: First child device: switch capability should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_configuration_2_children[configuration_2_light1_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } },
      }
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device_configuration_2_children[configuration_2_light1_ep].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device_configuration_2.id, clusters.OnOff.server.commands.On(mock_device_configuration_2, configuration_2_light1_ep)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_2.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device_configuration_2, configuration_2_light1_ep, false)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_2_children[configuration_2_light1_ep]:generate_test_message(
        "main", capabilities.switch.switch.off()
      )
    )
  end,
  { test_init = test_init_configuration_2 }
)

test.register_coroutine_test(
  "Configuration 2: Second child device: switch capability should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_configuration_2_children[configuration_2_light2_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device_configuration_2_children[configuration_2_light2_ep].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device_configuration_2.id, clusters.OnOff.server.commands.On(mock_device_configuration_2, configuration_2_light2_ep)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_2.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device_configuration_2, configuration_2_light2_ep, false)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_2_children[configuration_2_light2_ep]:generate_test_message(
        "main", capabilities.switch.switch.off()
      )
    )
  end,
  { test_init = test_init_configuration_2 }
)

test.register_coroutine_test(
  "Configuration 3: Parent device: handle single press sequence",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_3.id,
        clusters.Switch.events.InitialPress:build_test_event_report(mock_device_configuration_3, configuration_3_button1_ep, {new_position = 1}),
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_3:generate_test_message(
        "main", capabilities.button.button.pushed({state_change = true})
      )
    )
  end,
  { test_init = test_init_configuration_3 }
)

test.register_coroutine_test(
  "Configuration 3: Parent device: handle single press sequence for a multi press on multi button",
  function ()
    test.socket.matter:__queue_receive({
      mock_device_configuration_3.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device_configuration_3, configuration_3_button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_3.id,
      clusters.Switch.events.ShortRelease:build_test_event_report(
        mock_device_configuration_3, configuration_3_button2_ep, {previous_position = 0}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_3.id,
      clusters.Switch.events.InitialPress:build_test_event_report(
        mock_device_configuration_3, configuration_3_button2_ep, {new_position = 1}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_3.id,
      clusters.Switch.events.MultiPressOngoing:build_test_event_report(
        mock_device_configuration_3, configuration_3_button2_ep, {new_position = 1, current_number_of_presses_counted = 2}
      )
    })
    test.socket.matter:__queue_receive({
      mock_device_configuration_3.id,
      clusters.Switch.events.MultiPressComplete:build_test_event_report(
        mock_device_configuration_3, configuration_3_button2_ep, {new_position = 0, total_number_of_presses_counted = 2, previous_position = 1}
      )
    })
    test.socket.capability:__expect_send(mock_device_configuration_3:generate_test_message("button2", capabilities.button.button.double({state_change = true})))
  end,
  { test_init = test_init_configuration_3 }
)

test.register_coroutine_test(
  "Configuration 3: First child device: switch capability should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_configuration_3_children[configuration_3_light1_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } },
      }
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device_configuration_3_children[configuration_3_light1_ep].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device_configuration_3.id, clusters.OnOff.server.commands.On(mock_device_configuration_3, configuration_3_light1_ep)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_3.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device_configuration_3, configuration_3_light1_ep, false)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_3_children[configuration_3_light1_ep]:generate_test_message(
        "main", capabilities.switch.switch.off()
      )
    )
  end,
  { test_init = test_init_configuration_3 }
)

test.register_coroutine_test(
  "Configuration 3: Second child device: switch capability should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device_configuration_3_children[configuration_3_light2_ep].id,
        { capability = "switch", component = "main", command = "on", args = { } }
      }
    )
    test.socket.devices:__expect_send(
      {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device_configuration_3_children[configuration_3_light2_ep].id, capability_id = "switch", capability_cmd_id = "on" }
      }
    )
    test.socket.matter:__expect_send(
      {
        mock_device_configuration_3.id, clusters.OnOff.server.commands.On(mock_device_configuration_3, configuration_3_light2_ep)
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_configuration_3.id,
        clusters.OnOff.attributes.OnOff:build_test_report_data(mock_device_configuration_3, configuration_3_light2_ep, false)
      }
    )
    test.socket.capability:__expect_send(
      mock_device_configuration_3_children[configuration_3_light2_ep]:generate_test_message(
        "main", capabilities.switch.switch.off()
      )
    )
  end,
  { test_init = test_init_configuration_3 }
)

test.run_registered_tests()
