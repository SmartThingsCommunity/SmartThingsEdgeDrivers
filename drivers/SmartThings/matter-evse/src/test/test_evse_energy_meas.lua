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
local clusters = require "st.matter.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local EVSE_EP = 1
local ELECTRICAL_SENSOR_EP_ONE = 2
local ELECTRICAL_SENSOR_EP_TWO = 3

clusters.EnergyEvse = require "EnergyEvse"
clusters.EnergyEvseMode = require "EnergyEvseMode"
clusters.ElectricalEnergyMeasurement = require "ElectricalEnergyMeasurement"
clusters.ElectricalPowerMeasurement = require "ElectricalPowerMeasurement"
clusters.DeviceEnergyManagementMode = require "DeviceEnergyManagementMode"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("evse-energy-meas.yml"),
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
      endpoint_id = EVSE_EP,
      clusters = {
        { cluster_id = clusters.EnergyEvse.ID,     cluster_type = "SERVER" },
        { cluster_id = clusters.EnergyEvseMode.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x050C, device_type_revision = 1 } -- EVSE
      }
    },
    {
      endpoint_id = ELECTRICAL_SENSOR_EP_ONE,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 } -- Electrical Sensor
      }
    },
    {
      endpoint_id = ELECTRICAL_SENSOR_EP_TWO,
      clusters = {
        { cluster_id = clusters.ElectricalEnergyMeasurement.ID, cluster_type = "SERVER" },
      },
      device_types = {
        { device_type_id = 0x0510, device_type_revision = 1 } -- Electrical Sensor
      }
    },
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.EnergyEvse.attributes.State,
    clusters.EnergyEvse.attributes.SupplyState,
    clusters.EnergyEvse.attributes.FaultState,
    clusters.EnergyEvse.attributes.ChargingEnabledUntil,
    clusters.EnergyEvse.attributes.MinimumChargeCurrent,
    clusters.EnergyEvse.attributes.MaximumChargeCurrent,
    clusters.EnergyEvse.attributes.SessionDuration,
    clusters.EnergyEvse.attributes.SessionEnergyCharged,
    clusters.EnergyEvseMode.attributes.SupportedModes,
    clusters.EnergyEvseMode.attributes.CurrentMode,
    clusters.ElectricalEnergyMeasurement.attributes.PeriodicEnergyImported,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({ mock_device.id, subscribe_request })
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
  capabilities.evseChargingSession.targetEndTime("1970-01-01T00:00:00Z")))
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Assert profile applied over doConfigure",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    mock_device:expect_metadata_update({ profile = "evse-energy-meas" })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Ensure timers are created for the device",
  function()
    local poll_timer = mock_device:get_field("__recurring_poll_timer")
    assert(poll_timer ~= nil, "poll_timer should exist")

    local report_poll_timer = mock_device:get_field("__recurring_report_poll_timer")
    assert(report_poll_timer ~= nil, "report_poll_timer should exist")
  end
)

test.register_coroutine_test(
  "Ensure timers are created for the device",
  function()
    test.socket.matter:__set_channel_ordering("relaxed")

    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "removed" })
    test.wait_for_events()

    local poll_timer = mock_device:get_field("__recurring_poll_timer")
    assert(poll_timer == nil, "poll_timer should not exist")

    local report_poll_timer = mock_device:get_field("__recurring_report_poll_timer")
    assert(report_poll_timer == nil, "report_poll_timer should not exist")
  end
)

test.register_coroutine_test(
  "Ensure that every 60 seconds the driver reads the CumulativeEnergyImported attribute for both endpoints",
  function()
    test.mock_time.advance_time(60)
    test.socket.matter:__set_channel_ordering("relaxed")
    local CumulativeEnergyImportedReadReq = clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported
        :read(mock_device, ELECTRICAL_SENSOR_EP_ONE)
    CumulativeEnergyImportedReadReq:merge(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(
      mock_device, ELECTRICAL_SENSOR_EP_TWO))
    test.socket.matter:__expect_send({
      mock_device.id,
      CumulativeEnergyImportedReadReq
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
  "Ensure the total accumulated powerConsumption for both endpoints is reported every 15 minutes",
  function()
    test.socket.matter:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    local CumulativeEnergyImportedReadReq = clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported
        :read(mock_device, ELECTRICAL_SENSOR_EP_ONE)
    CumulativeEnergyImportedReadReq:merge(clusters.ElectricalEnergyMeasurement.attributes.CumulativeEnergyImported:read(
      mock_device, ELECTRICAL_SENSOR_EP_TWO))

    test.socket.matter:__expect_send({
      mock_device.id,
      CumulativeEnergyImportedReadReq
    })

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyImported:build_test_report_data(mock_device,
      ELECTRICAL_SENSOR_EP_ONE,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 100000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) })             --100Wh

    test.socket.matter:__queue_receive({ mock_device.id, clusters.ElectricalEnergyMeasurement.attributes
        .CumulativeEnergyImported:build_test_report_data(mock_device,
      ELECTRICAL_SENSOR_EP_TWO,
      clusters.ElectricalEnergyMeasurement.types.EnergyMeasurementStruct({ energy = 150000, start_timestamp = 0, end_timestamp = 0, start_systime = 0, end_systime = 0 })) })             --150Wh

    test.wait_for_events()
    test.mock_time.advance_time(60 * 15)

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
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

test.run_registered_tests()
