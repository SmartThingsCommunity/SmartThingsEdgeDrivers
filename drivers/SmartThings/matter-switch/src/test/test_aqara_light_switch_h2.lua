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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"

local parent_ep = 1
local child1_ep = 2
local child2_ep = 5
local child3_ep = 7

-- used in unit testing, since device.profile.id and args.old_st_store.profile.id are always the same
-- and this is to avoid the crash of the test case that occurs when try_update_metadata is performed in the device_init stage.
local TEST_CONFIGURE = "__test_configure"
local DEFERRED_CONFIGURE = "__DEFERRED_CONFIGURE"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("light-button-electricalMeasurement.yml"),
  manufacturer_info = {vendor_id = 0x115F, product_id = 0x1009, product_name = "Aqara Light Switch H2"},
  label = "Aqara Light Switch",
  device_id = "00000000-1111-2222-3333-000000000001",
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
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
        {cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 2 },
        {cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 5 }
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1}, -- On/Off Light
        {device_type_id = 0x0510, device_type_revision = 1}, -- Electrical Sensor
      }
    },
    {
      endpoint_id = child1_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1}, -- On/Off Light
      }
    },
    {
      endpoint_id = 4,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH}
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = child2_ep,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH}
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 6,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH}
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = child3_ep,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH}
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    }
  }
})

-- add device for each mock device
local CLUSTER_SUBSCRIBE_LIST ={
  clusters.OnOff.attributes.OnOff,
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.MultiPressComplete,
  clusters.ElectricalPowerMeasurement.attributes.ActivePower,
  clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
  clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported,
  clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported,
}

local child_profiles = {
  [child1_ep] = t_utils.get_profile_definition("light-button.yml"),
  [child2_ep] = t_utils.get_profile_definition("button.yml"),
  [child3_ep] = t_utils.get_profile_definition("button.yml")
}

local cumulative_report_val_19 = {
  energy = 19000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local mock_children = {}
for i, endpoint in ipairs(mock_device.endpoints) do
  if endpoint.endpoint_id == child1_ep or endpoint.endpoint_id == child2_ep or endpoint.endpoint_id == child3_ep then
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
  local opts = { persist = true }
  mock_device:set_field(TEST_CONFIGURE, true, opts)

  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, cluster in ipairs(CLUSTER_SUBSCRIBE_LIST) do
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
    label = "Aqara Light Switch 2",
    profile = "light-button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", child1_ep)
  })

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Aqara Light Switch 3",
    profile = "button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", child2_ep)
  })

  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Aqara Light Switch 4",
    profile = "button",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", child3_ep)
  })
end

test.set_test_init_function(test_init)

test.register_message_test(
  "First Switch device : switch capability should send the appropriate commands",
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
      channel = "devices",
      direction = "send",
      message = {
        "register_native_capability_cmd_handler",
        { device_uuid = mock_device.id, capability_id = "switch", capability_cmd_id = "on" }
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

test.register_coroutine_test(
  "First Switch device : switch/button capability should send the appropriate commands",
    function()
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
      mock_device:set_field(DEFERRED_CONFIGURE, true)
      test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({value = 0.0}))
      mock_device:expect_metadata_update({ profile = "light-button-electricalMeasurement" })

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("button", capabilities.button.supportedButtonValues({"pushed"}, {state_change = false}))
      )

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
      )

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.energyMeter.energy({value = 0.0, unit = "Wh"}))
      )

      test.wait_for_events()

      test.socket.matter:__queue_receive(
        {
          mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(mock_device, 4, {new_position = 1})
        }
      )

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("button", capabilities.button.button.pushed({state_change = true}))
      )
    end
)

test.register_coroutine_test(
  "Check Energy/Power Management", function()

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(mock_device, 1, cumulative_report_val_19)
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )

    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(mock_device, 1, 17000)
      }
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({value = 17.0, unit="W"}))
    )
    end
)

test.run_registered_tests()

