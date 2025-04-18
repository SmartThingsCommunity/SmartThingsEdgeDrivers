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
  local read_req = clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, SOLAR_POWER_EP_ONE)
  read_req:merge(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, SOLAR_POWER_EP_TWO))

  test.socket.matter:__expect_send({
    mock_device.id,
    read_req
  })

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
  "Ensure timers are created for the device and terminated on removed",
  function()
    test.socket.matter:__set_channel_ordering("relaxed")
    local poll_timer = mock_device:get_field("__recurring_poll_timer")
    assert(poll_timer ~= nil, "poll_timer should not exist")

    local report_poll_timer = mock_device:get_field("__recurring_report_poll_timer")
    assert(report_poll_timer ~= nil, "report_poll_timer should exist")

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "removed" })
    test.wait_for_events()

    local poll_timer = mock_device:get_field("__recurring_poll_timer")
    assert(poll_timer == nil, "poll_timer should not exist")

    local report_poll_timer = mock_device:get_field("__recurring_report_poll_timer")
    assert(report_poll_timer == nil, "report_poll_timer should not exist")
  end
)

test.register_coroutine_test(
  "Ensure that every 60 seconds the driver reads the CumulativeEnergyExported attribute for both endpoints",
  function()
    test.mock_time.advance_time(60)
    test.socket.matter:__set_channel_ordering("relaxed")
    local read_req = clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, SOLAR_POWER_EP_ONE)
    read_req:merge(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, SOLAR_POWER_EP_TWO))
    test.socket.matter:__expect_send({
      mock_device.id,
      read_req
    })
    test.wait_for_events()
  end,
  {
    test_init = function()
      test_init()
      test.timer.__create_and_queue_test_time_advance_timer(60, "interval", "create_poll_schedule")
    end
  }
)

test.register_coroutine_test(
  "Ensure the total cumulative energy exported powerConsumption for both endpoints is reported every 15 minutes",
  function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    local read_req = clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, SOLAR_POWER_EP_ONE)
    read_req:merge(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyExported:read(mock_device, SOLAR_POWER_EP_TWO))

    test.socket.matter:__expect_send({
      mock_device.id,
      read_req
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyExported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_ONE,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) })             --100Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 100, unit = "Wh"
      }))
    )

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyExported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_TWO,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 150000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) })             --150Wh

      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main",
        capabilities.energyMeter.energy({
          value = 250, unit = "Wh"
        }))
      )
    test.wait_for_events()
    test.mock_time.advance_time(60 * 15)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("exportedEnergy",
        capabilities.powerConsumptionReport.powerConsumption({
          energy = 250,
          deltaEnergy = 250,
          start = "1970-01-01T00:00:00Z",
          ["end"] = "1970-01-01T00:14:59Z"
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

test.register_coroutine_test(
  "Ensure energyMeter is not reported incase we recieve CumulativeEnergyImported events for Solar Power device",
  function()
    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
      .CumulativeEnergyExported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_ONE,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) })             --100Wh

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
      capabilities.energyMeter.energy({
        value = 100, unit = "Wh"
      }))
    )

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
      .CumulativeEnergyImported:build_test_report_data(mock_device,
      SOLAR_POWER_EP_ONE,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) })             --100Wh
  end
)

test.run_registered_tests()
