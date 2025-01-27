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
local button_attr = capabilities.button.button

local DEFERRED_CONFIGURE = "__DEFERRED_CONFIGURE"

local aqara_parent_ep = 4
local aqara_child1_ep = 1
local aqara_child2_ep = 2

local aqara_mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("4-button.yml"),
  manufacturer_info = {vendor_id = 0x115F, product_id = 0x1009, product_name = "Aqara Light Switch H2"},
  label = "Aqara Light Switch",
  device_id = "00000000-1111-2222-3333-000000000001",
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 2 },
        {cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 5 }
      },
      device_types = {
        {device_type_id = 0x0016, device_type_revision = 1}, -- RootNode
        {device_type_id = 0x0510, device_type_revision = 1} -- Electrical Sensor
      }
    },
    {
      endpoint_id = aqara_child1_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1}, -- On/Off Light
      }
    },
    {
      endpoint_id = aqara_child2_ep,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0100, device_type_revision = 1}, -- On/Off Light
      }
    },
    {
      endpoint_id = aqara_parent_ep,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH}
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    },
    {
      endpoint_id = 5,
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
      endpoint_id = 7,
      clusters = {
        {cluster_id = clusters.Switch.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = clusters.Switch.types.Feature.MOMENTARY_SWITCH}
      },
      device_types = {
        {device_type_id = 0x000F, device_type_revision = 1} -- Generic Switch
      }
    }
  }
})

local aqara_child_profiles = {
  [aqara_child1_ep] = t_utils.get_profile_definition("light-power-energy-powerConsumption.yml"),
  [aqara_child2_ep] = t_utils.get_profile_definition("light-binary.yml"),
}

local aqara_mock_children = {}
for i, endpoint in ipairs(aqara_mock_device.endpoints) do
  if endpoint.endpoint_id == aqara_child1_ep or endpoint.endpoint_id == aqara_child2_ep then
    local child_data = {
      profile = aqara_child_profiles[endpoint.endpoint_id],
      device_network_id = string.format("%s:%d", aqara_mock_device.id, endpoint.endpoint_id),
      parent_device_id = aqara_mock_device.id,
      parent_assigned_child_key = string.format("%d", endpoint.endpoint_id)
    }
    aqara_mock_children[endpoint.endpoint_id] = test.mock_device.build_test_child_device(child_data)
  end
end

local cumulative_report_val_19 = {
  energy = 19000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local cumulative_report_val_29 = {
  energy = 29000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local cumulative_report_val_39 = {
  energy = 39000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local function test_init()
  local opts = { persist = true }
  local cluster_subscribe_list = {
    clusters.OnOff.attributes.OnOff,
    clusters.Switch.server.events.InitialPress,
    clusters.Switch.server.events.LongPress,
    clusters.Switch.server.events.ShortRelease,
    clusters.Switch.server.events.MultiPressComplete,
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(aqara_mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(aqara_mock_device))
    end
  end
  test.socket.matter:__expect_send({aqara_mock_device.id, subscribe_request})
  test.mock_device.add_test_device(aqara_mock_device)
  -- to test powerConsumptionReport
  test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "create_poll_report_schedule")

  for _, child in pairs(aqara_mock_children) do
    test.mock_device.add_test_device(child)
  end

  aqara_mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Aqara Light Switch 1",
    profile = "light-power-energy-powerConsumption",
    parent_device_id = aqara_mock_device.id,
    parent_assigned_child_key = string.format("%d", aqara_child1_ep)
  })

  aqara_mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Aqara Light Switch 2",
    profile = "light-binary",
    parent_device_id = aqara_mock_device.id,
    parent_assigned_child_key = string.format("%d", aqara_child2_ep)
  })

  test.socket.device_lifecycle:__queue_receive({ aqara_mock_device.id, "added" })
  test.socket.matter:__expect_send({aqara_mock_device.id, subscribe_request})
  test.mock_devices_api._expected_device_updates[aqara_mock_device.device_id] = "00000000-1111-2222-3333-000000000001"
  test.mock_devices_api._expected_device_updates[1] = {device_id = "00000000-1111-2222-3333-000000000001"}
  test.mock_devices_api._expected_device_updates[1].metadata = {deviceId="00000000-1111-2222-3333-000000000001", profileReference="4-button"}

  aqara_mock_device:set_field(DEFERRED_CONFIGURE, true, opts)
  local device_info_copy = utils.deep_copy(aqara_mock_device.raw_st_data)
  device_info_copy.profile.id = "4-button"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ aqara_mock_device.id, "infoChanged", device_info_json })
  test.socket.matter:__expect_send({aqara_mock_device.id, subscribe_request})

  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("main", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("main", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button2", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button2", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button3", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button3", button_attr.pushed({state_change = false})))

  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button4", capabilities.button.supportedButtonValues({"pushed"}, {visibility = {displayed = false}})))
  test.socket.capability:__expect_send(aqara_mock_device:generate_test_message("button4", button_attr.pushed({state_change = false})))
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Button/Switch device : button/switch capability should send the appropriate commands",
    function()
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 4, {new_position = 1})
        }
      )

      test.socket.capability:__expect_send(
        aqara_mock_device:generate_test_message("main", capabilities.button.button.pushed({state_change = true}))
      )

      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.Switch.events.InitialPress:build_test_event_report(aqara_mock_device, 5, {new_position = 1})
        }
      )

      test.socket.capability:__expect_send(
        aqara_mock_device:generate_test_message("button2", capabilities.button.button.pushed({state_change = true}))
      )

      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.OnOff.attributes.OnOff:build_test_report_data(aqara_mock_device, aqara_child1_ep, true)
        }
      )

      test.socket.capability:__expect_send(
        aqara_mock_children[aqara_child1_ep]:generate_test_message("main", capabilities.switch.switch.on())
      )

      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.OnOff.attributes.OnOff:build_test_report_data(aqara_mock_device, aqara_child2_ep, true)
        }
      )

      test.socket.capability:__expect_send(
        aqara_mock_children[aqara_child2_ep]:generate_test_message("main", capabilities.switch.switch.on())
      )
    end
)

test.register_coroutine_test(
  "Check Energy/Power Management and powerConsumptionReport",
    function()
      test.socket.matter:__queue_receive(
        {
          -- don't use "aqara_mock_children[aqara_child1_ep].id,"
          -- because energy management is at the root endpoint.
          aqara_mock_device.id,
          clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(aqara_mock_device, 1, 17000)
        }
      )

      test.socket.capability:__expect_send(
        -- when energy management is in the root endpoint, the event is sent to the first switch endpoint in CHILD_EDGE.
        aqara_mock_children[aqara_child1_ep]:generate_test_message("main", capabilities.powerMeter.power({value = 17.0, unit="W"}))
      )

      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(aqara_mock_device, 1, cumulative_report_val_19)
        }
      )

      test.socket.capability:__expect_send(
        aqara_mock_children[aqara_child1_ep]:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
      )

      -- in order to do powerConsumptionReport, CumulativeEnergyImported must be called twice.
      -- This is because related variable settings are required in set_poll_report_timer_and_schedule().
      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(aqara_mock_device, 1, cumulative_report_val_29)
        }
      )

      test.socket.capability:__expect_send(
        aqara_mock_children[aqara_child1_ep]:generate_test_message("main", capabilities.energyMeter.energy({ value = 29.0, unit = "Wh" }))
      )

      test.socket.matter:__queue_receive(
        {
          aqara_mock_device.id,
          clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:build_test_report_data(
            aqara_mock_device, 1, cumulative_report_val_39
          )
        }
      )

      test.socket.capability:__expect_send(
        aqara_mock_children[aqara_child1_ep]:generate_test_message("main", capabilities.energyMeter.energy({ value = 39.0, unit = "Wh" }))
      )

      -- to test powerConsumptionReport
      test.mock_time.advance_time(2000)
      test.socket.capability:__expect_send(
        aqara_mock_children[aqara_child1_ep]:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:33:19Z",
          deltaEnergy = 0.0,
          energy = 39.0
        }))
      )
    end
)

test.run_registered_tests()

