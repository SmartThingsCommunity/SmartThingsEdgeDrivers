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

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local capabilities = require "st.capabilities"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local test = require "integration_test"

local OnOff = clusters.OnOff
local SimpleMetering = clusters.SimpleMetering
local ElectricalMeasurement = clusters.ElectricalMeasurement
local AnalogInput = clusters.AnalogInput
local Basic = clusters.Basic

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local MAX_POWER_ATTRIBUTE_ID = 0x020B

local POWER_METER_ENDPOINT = 0x15
local ENERGY_METER_ENDPOINT = 0x1F

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local APPLICATION_VERSION = "application_version"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("switch-power-energy-consumption-report-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.plug.maeu01",
        server_clusters = { OnOff.ID, AnalogInput.ID }
      }
    }
  }
)

local mock_standard = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("switch-power-energy-consumption-report-aqara.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.plug.maeu01",
        server_clusters = { OnOff.ID, SimpleMetering.ID, ElectricalMeasurement.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_standard)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.switch.switch.off())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Basic.attributes.ApplicationVersion:read(mock_device)
    })
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID
          , MFG_CODE, data_types.Uint8, 1)
      }
    )
  end
)

test.register_coroutine_test(
  "Refresh on device should read all necessary attributes",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(ENERGY_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Power meter handled",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      AnalogInput.attributes.PresentValue:build_test_attr_report(mock_device,
        SinglePrecisionFloat(0, 9, 0.953125)):from_endpoint(POWER_METER_ENDPOINT)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerMeter.power({ value = 1000.0, unit = "W" }))
    )
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(ENERGY_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Energy meter handled",
  function()
    local current_time = os.time() - 60 * 20
    mock_device:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      AnalogInput.attributes.PresentValue:build_test_attr_report(mock_device,
        SinglePrecisionFloat(0, 9, 0.953125)):from_endpoint(ENERGY_METER_ENDPOINT)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.energyMeter.energy({ value = 1000000.0, unit = "Wh" }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 1000000.0 }))
    )
  end
)

test.register_coroutine_test(
  "Handle restorePowerState in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.restorePowerState"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        RESTORE_POWER_STATE_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, true) })
  end
)

test.register_coroutine_test(
  "Handle maxPower in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.maxPower"] = "1" }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, MAX_POWER_ATTRIBUTE_ID,
        MFG_CODE, data_types.SinglePrecisionFloat, SinglePrecisionFloat(0, 6, 0.5625)) })
  end
)

-- with standard cluster

test.register_coroutine_test(
  "Handle power meter with standard cluster",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_standard.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_standard, 41)
      }
    )
    mock_standard:set_field(APPLICATION_VERSION, 41, { persist = true })
    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_standard.id,
      ElectricalMeasurement.attributes.ActivePower:build_test_attr_report(mock_standard, 100)
    })
    test.socket.capability:__expect_send(
      mock_standard:generate_test_message("main", capabilities.powerMeter.power({ value = 10.0, unit = "W" }))
    )
  end
)

test.register_coroutine_test(
  "Handle energy meter with standard cluster",
  function()
    test.socket.zigbee:__queue_receive(
      {
        mock_standard.id,
        Basic.attributes.ApplicationVersion:build_test_attr_report(mock_standard, 41)
      }
    )
    mock_standard:set_field(APPLICATION_VERSION, 41, { persist = true })
    test.wait_for_events()

    local current_time = os.time() - 60 * 20
    mock_standard:set_field(LAST_REPORT_TIME, current_time)

    test.socket.zigbee:__queue_receive({
      mock_standard.id,
      SimpleMetering.attributes.CurrentSummationDelivered:build_test_attr_report(mock_standard, 10)
    })
    test.socket.capability:__expect_send(
      mock_standard:generate_test_message("main", capabilities.energyMeter.energy({ value = 10, unit = "Wh" }))
    )
    test.socket.capability:__expect_send(
      mock_standard:generate_test_message("main",
        capabilities.powerConsumptionReport.powerConsumption({ deltaEnergy = 0.0, energy = 10 }))
    )
  end
)

test.run_registered_tests()
