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
local AnalogInput = clusters.AnalogInput

local MFG_CODE = 0x115F
local PRIVATE_CLUSTER_ID = 0xFCC0
local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID = 0x000A

local POWER_METER_ENDPOINT = 0x15
local ENERGY_METER_ENDPOINT = 0x1F

local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local PRIVATE_MODE = "PRIVATE_MODE"

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-switch-module.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.switch.n0agl1",
        server_clusters = { OnOff.ID, AnalogInput.ID }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Handle added lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.powerMeter.power({ value = 0.0, unit = "W" }))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.energyMeter.energy({ value = 0.0, unit = "Wh" }))
    )
  end
)

test.register_coroutine_test(
  "Reported on status should be handled",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, true):from_endpoint(0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.on()))
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Reported off status should be handled",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__queue_receive({ mock_device.id,
      OnOff.attributes.OnOff:build_test_attr_report(mock_device, false):from_endpoint(0x01) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.switch.switch.off()))
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id,
      AnalogInput.attributes.PresentValue:read(mock_device):to_endpoint(POWER_METER_ENDPOINT) })
  end
)

test.register_coroutine_test(
  "Capability on command should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "on", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.On(mock_device) })
  end
)

test.register_coroutine_test(
  "Capability off command should be handled",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "switch", component = "main", command = "off", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.server.commands.Off(mock_device) })
  end
)

test.register_coroutine_test(
  "Power meter handled",
  function()
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })

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
    mock_device:set_field(PRIVATE_MODE, 1, { persist = true })

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
  "Handle electricSwitchType in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.electricSwitchType"] = 'rocker' }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 1) })
  end
)

test.run_registered_tests()
