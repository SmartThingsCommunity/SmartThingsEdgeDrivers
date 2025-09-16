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
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local version = require "version"

local BATTERY_STORAGE_EP = 20

local BATTERY_STORAGE_DEVICE_TYPE_ID = 0x0018
local POWER_SOURCE_DEVICE_TYPE_ID = 0x0011
local ELECTRICAL_SENSOR_DEVICE_TYPE_ID = 0x0510

if version.api < 11 then
  clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
  clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
end

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("battery-storage.yml"),
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
        { device_type_id = 0x0016, device_type_revision = 1 }, -- RootNode
      }
    },
    {
      endpoint_id = BATTERY_STORAGE_EP,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER", feature_map = 15 }, -- ALL
        { cluster_id = clusters.ElectricalPowerMeasurement.ID,  cluster_type = "SERVER" },
        { cluster_id = clusters.PowerSource.ID,                 cluster_type = "SERVER", feature_map = 7 },  -- WIRED, BAT & RECHG
      },
      device_types = {
        { device_type_id = BATTERY_STORAGE_DEVICE_TYPE_ID,   device_type_revision = 1 },
        { device_type_id = ELECTRICAL_SENSOR_DEVICE_TYPE_ID, device_type_revision = 1 },
        { device_type_id = POWER_SOURCE_DEVICE_TYPE_ID,      device_type_revision = 1 }
      }
    }
  }
})

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  local cluster_subscribe_list = {
    clusters.ElectricalPowerMeasurement.attributes.ActivePower,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyExported,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
    clusters.PowerSource.attributes.BatPercentRemaining,
    clusters.PowerSource.attributes.BatChargeState
  }
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })

  test.socket.matter:__expect_send({
    mock_device.id,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
  })

  test.socket.matter:__expect_send({
    mock_device.id,
    clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, BATTERY_STORAGE_EP)
  })

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure"})
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Battery percentage must reported properly",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, BATTERY_STORAGE_EP, 150
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5))
      )
    )
  end
)
test.register_coroutine_test(
  "Battery charge state  must reported properly",
  function()
    test.socket.matter:__set_channel_ordering("strict")
    test.socket.capability:__set_channel_ordering("strict")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatChargeState:build_test_report_data(
          mock_device, BATTERY_STORAGE_EP, clusters.PowerSource.types.BatChargeStateEnum.IS_CHARGING
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.chargingState.chargingState.charging())
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatChargeState:build_test_report_data(
          mock_device, BATTERY_STORAGE_EP, clusters.PowerSource.types.BatChargeStateEnum.IS_AT_FULL_CHARGE
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.chargingState.chargingState.fullyCharged())
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatChargeState:build_test_report_data(
          mock_device, BATTERY_STORAGE_EP, clusters.PowerSource.types.BatChargeStateEnum.IS_NOT_CHARGING
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.chargingState.chargingState.stopped())
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatChargeState:build_test_report_data(
          mock_device, BATTERY_STORAGE_EP, 10 -- Error scenario or any other state
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.chargingState.chargingState.error())
    )
  end
)

test.register_coroutine_test(
  "Appropriate powerMeter capability events must be sent in 'W' on receiving ActivePower events",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(mock_device,
        BATTERY_STORAGE_EP,
        30000)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.powerMeter.power({ value = 30.0, unit = "W" })))
  end
)

test.register_coroutine_test(
  "Appropriate powerMeter capability events must be sent in 'W' on receiving ActivePower events",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(mock_device,
        BATTERY_STORAGE_EP,
        30000)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.powerMeter.power({ value = 30.0, unit = "W" })))
  end
)

test.register_coroutine_test(
  "Ensure the total cumulative energy exported powerConsumption for both endpoints is reported every 15 minutes",
  function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
    })

    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, BATTERY_STORAGE_EP)
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyImported:build_test_report_data(mock_device,
      BATTERY_STORAGE_EP,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) --100Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("importedEnergy",
        capabilities.energyMeter.energy({
          value = 100, unit = "Wh"
        }))
    )

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyExported:build_test_report_data(mock_device,
      BATTERY_STORAGE_EP,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 300000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) --300Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("exportedEnergy",
        capabilities.energyMeter.energy({
          value = 300, unit = "Wh"
        }))
    )

    test.wait_for_events()
    test.mock_time.advance_time(60 * 15)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("exportedEnergy",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 300,
          deltaEnergy = 300,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:14:59Z"
        }))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("importedEnergy",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 100,
          deltaEnergy = 100,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:14:59Z"
        }))
    )

    test.wait_for_events()

    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(mock_device)
    })

    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, BATTERY_STORAGE_EP)
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyImported:build_test_report_data(mock_device,
      BATTERY_STORAGE_EP,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 200000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) --200Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("importedEnergy",
        capabilities.energyMeter.energy({
          value = 200, unit = "Wh"
        })))

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyExported:build_test_report_data(mock_device,
      BATTERY_STORAGE_EP,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 400000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) }) --400Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("exportedEnergy",
      capabilities.energyMeter.energy({
        value = 400, unit = "Wh"
      }))
    )

    test.wait_for_events()
    test.mock_time.advance_time(60 * 15)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("exportedEnergy",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 400,
          deltaEnergy = 100,
          start = "1970-01-01T00:15:00Z",
          ["end"] = "1970-01-01T00:29:59Z"
        }))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("importedEnergy",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 200,
          deltaEnergy = 100,
          start = "1970-01-01T00:15:00Z",
          ["end"] = "1970-01-01T00:29:59Z"
        }))
    )

    test.wait_for_events()
  end,
  {
    test_init = function()
      test_init()
      test.timer.__create_and_queue_test_time_advance_timer(60 * 15, "interval", "create_poll_report_schedule")
      test.timer.__create_and_queue_test_time_advance_timer(60, "interval", "create_poll_schedule")
    end
  }
)

test.run_registered_tests()
