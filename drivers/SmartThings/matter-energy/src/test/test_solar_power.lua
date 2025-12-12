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

local SOLAR_POWER_EP_ONE = 20
local SOLAR_POWER_EP_TWO = 30

local SOLAR_POWER_DEVICE_TYPE_ID = 0x0017
local ELECTRICAL_SENSOR_DEVICE_TYPE_ID = 0x0510

if version.api < 11 then
clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
end

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("solar-power.yml"),
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
      endpoint_id = SOLAR_POWER_EP_ONE,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER" , feature_map = 6}, --CUME & PERE
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = SOLAR_POWER_DEVICE_TYPE_ID, device_type_revision = 1 }, -- SOLAR POWER
        { device_type_id = ELECTRICAL_SENSOR_DEVICE_TYPE_ID, device_type_revision = 1 } -- ELECTRICAL_SENSOR
      }
    },
    {
      endpoint_id = SOLAR_POWER_EP_TWO,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER" , feature_map = 6}, --CUME & PERE
        { cluster_id = clusters.ElectricalPowerMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = SOLAR_POWER_DEVICE_TYPE_ID, device_type_revision = 1 }, -- SOLAR POWER
        { device_type_id = ELECTRICAL_SENSOR_DEVICE_TYPE_ID, device_type_revision = 1 } -- ELECTRICAL_SENSOR
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
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported
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

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure"})
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Appropriate powerMeter capability events must be sent in 'W' on receiving ActivePower events",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(mock_device,
        SOLAR_POWER_EP_ONE,
          15000)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.powerMeter.power({ value = 15.0, unit = "W" })))

    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(mock_device,
        SOLAR_POWER_EP_TWO,
          16000)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.powerMeter.power({ value = 31.0, unit = "W" })))

    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ElectricalPowerMeasurement.attributes.ActivePower:build_test_report_data(mock_device,
        SOLAR_POWER_EP_TWO,
          20000)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.powerMeter.power({ value = 35.0, unit = "W" })))
  end
)

test.register_coroutine_test(
  "Ensure the total cumulative energy exported powerConsumption for both endpoints is reported",
  function()
    test.mock_time.advance_time(901) -- move time 15 minutes past 0 (this can be assumed to be true in practice in all cases)

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyExported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_ONE,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0, apparent_energy = 0, reactive_energy = 0 })) })             --100Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 100, unit = "Wh"
      }))
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("exportedEnergy",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 100,
          deltaEnergy = 0.0,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:15:00Z"
        })
      )
    )

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyExported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_TWO,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 150000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0, apparent_energy = 0, reactive_energy = 0 })) })             --150Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 250, unit = "Wh"
      }))
    )
  end,
  {
    test_init = function()
      test_init()
    end
  }
)

test.register_coroutine_test(
  "Ensure energyMeter is not reported incase we recieve CumulativeEnergyImported events for Solar Power device",
  function()
    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
      .CumulativeEnergyExported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_ONE,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0, apparent_energy = 0, reactive_energy = 0 })) })             --100Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 100, unit = "Wh"
      }))
    )

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
      .CumulativeEnergyImported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_ONE,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0, apparent_energy = 0, reactive_energy = 0 })) })             --100Wh
  end
)

test.run_registered_tests()
