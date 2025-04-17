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

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local clusters = require "st.matter.clusters"
local version = require "version"

-- set api version < 11 to test embedded clusters and EnergyMeasurementStruct type augmentation
version.api = 10

clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("plug-level-power-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 14, },
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER", feature_map = 0, },
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 }, -- Electrical Sensor
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        { cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", cluster_revision = 1, feature_map = 0, },
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2}
      },
      device_types = {
        { device_type_id = 0x010A, device_type_revision = 1 } -- OnOff Plug
      }
    },
  },
})

local mock_device_periodic = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("plug-energy-powerConsumption.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 10, },
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 } -- Electrical Sensor
      }
    },
  },
})

local subscribed_attributes = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.ElectricalPowerMeasurement.attributes.ActivePower,
  clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
  clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
}

local subscribed_attributes_periodic = {
  clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
  clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported,
}

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

local periodic_report_val_23 = {
  energy = 23000,
  start_timestamp = 0,
  end_timestamp = 0,
  start_systime = 0,
  end_systime = 0,
}

local function test_init()
  local subscribe_request = subscribed_attributes[1]:subscribe(mock_device)
  for i, cluster in ipairs(subscribed_attributes) do
      if i > 1 then
          subscribe_request:merge(cluster:subscribe(mock_device))
      end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.mock_device.add_test_device(mock_device)
  -- to test powerConsumptionReport
  test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "create_poll_report_schedule")
end
test.set_test_init_function(test_init)

local function test_init_periodic()
  local subscribe_request = subscribed_attributes_periodic[1]:subscribe(mock_device_periodic)
  for i, cluster in ipairs(subscribed_attributes_periodic) do
    if i > 1 then
        subscribe_request:merge(cluster:subscribe(mock_device_periodic))
    end
  end
  test.socket.matter:__expect_send({ mock_device_periodic.id, subscribe_request })
  test.mock_device.add_test_device(mock_device_periodic)
  -- to test powerConsumptionReport
  test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "create_poll_report_schedule")
end

test.register_coroutine_test(
  "Cumulative Energy measurement should generate correct messages for lua libs api < 11",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_19
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 19.0, unit = "Wh" }))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_29
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 29.0, unit = "Wh" }))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.CumulativeEnergyImported:build_test_report_data(
          mock_device, 1, cumulative_report_val_39
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 39.0, unit = "Wh" }))
    )
    test.mock_time.advance_time(2000)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        start = "1970-01-01T00:00:00Z",
        ["end"] = "1970-01-01T00:33:19Z",
        deltaEnergy = 0.0,
        energy = 39.0
      }))
    )
    test.wait_for_events()
    test.mock_time.advance_time(1500)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        start = "1970-01-01T00:33:20Z",
        ["end"] = "1970-01-01T00:58:19Z",
        deltaEnergy = 0.0,
        energy = 39.0
      }))
    )
  end
)

test.register_coroutine_test(
  "Periodic Energy measurement should generate correct messages for lua libs api < 11",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 23.0, unit="Wh"}))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 46.0, unit="Wh"}))
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_periodic.id,
        clusters.ElectricalEnergyMeasurement.server.attributes.PeriodicEnergyImported:build_test_report_data(
          mock_device_periodic, 1, periodic_report_val_23
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.energyMeter.energy({value = 69.0, unit="Wh"}))
    )
    test.mock_time.advance_time(2000)
    test.socket.capability:__expect_send(
      mock_device_periodic:generate_test_message("main", capabilities.powerConsumptionReport.powerConsumption({
        start = "1970-01-01T00:00:00Z",
        ["end"] = "1970-01-01T00:33:19Z",
        deltaEnergy = 0.0,
        energy = 69.0
      }))
    )
  end,
  { test_init = test_init_periodic }
)

test.run_registered_tests()
