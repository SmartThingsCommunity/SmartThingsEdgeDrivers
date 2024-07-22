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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local cluster_base = require "st.zigbee.cluster_base"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local t_utils = require "integration_test.utils"
local capabilities = require "st.capabilities"
local test = require "integration_test"

local Thermostat = clusters.Thermostat
local valveCalibration = capabilities["stse.valveCalibration"]
local invisibleCapabilities = capabilities["stse.invisibleCapabilities"]
local valveCalibrationCommandName = "startCalibration"
local thermostatModeId = "thermostatMode"
test.add_package_capability("valveCalibration.yaml")
test.add_package_capability("invisibleCapabilities.yaml")
local PRIVATE_CLUSTER_ID = 0xFCC0
local MFG_CODE = 0x115F
local PRIVATE_VALVE_CALIBRATION_ID = 0x0270
local PRIVATE_VALVE_SWITCH_ATTRIBUTE_ID = 0x0271
local PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID = 0x0272
local PRIVATE_THERM0STAT_VALVE_DETECTION_SWITCH_ID = 0x0274
local PRIVATE_THERMOSTAT_ALARM_INFORMATION_ID = 0x0275
local PRIVATE_CHILD_LOCK_ID = 0x0277
local PRIVATE_ANTIFREEZE_MODE_TEMPERATURE_SETTING_ID = 0x0279
local PRIVATE_VALVE_RESULT_CALIBRATION_ID = 0x027B
local PRIVATE_BATTERY_ENERGY_ID = 0x040A

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("thermostat-aqara.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "LUMI",
        model = "lumi.airrtc.agl001",
        server_clusters = {  PRIVATE_CLUSTER_ID, Thermostat.ID, 0x0001, 0x0402}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
  test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device)
    })
  test.socket.zigbee:__expect_send({
        mock_device.id,
        cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
          PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID, MFG_CODE)
    })
  test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_VALVE_RESULT_CALIBRATION_ID, MFG_CODE)
  })
end

test.set_test_init_function(test_init)

-- test.register_coroutine_test(
--   "Handle added lifecycle",
--   function()
--     test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main",
--       capabilities.thermostatMode.supportedThermostatModes({
--         capabilities.thermostatMode.thermostatMode.manual.NAME,
--         capabilities.thermostatMode.thermostatMode.antifreezing.NAME
--       }, { visibility = { displayed = false } }))
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({value = 21.0, unit = "C"}))
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 27.0, unit = "C"}))
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", capabilities.thermostatMode.thermostatMode.manual())
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", capabilities.valve.valve.open())
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("ChildLock", capabilities.lock.lock.unlocked())
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", capabilities.hardwareFault.hardwareFault.clear())
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", valveCalibration.calibrationState.calibrationPending())
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", invisibleCapabilities.invisibleCapabilities({""}))
--     )
--     test.socket.capability:__expect_send(
--       mock_device:generate_test_message("main", capabilities.battery.battery(100))
--     )
--   end
-- )


test.register_coroutine_test(
  "Handle notificationOfValveTest in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.notificationOfValveTest"] = true }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_THERM0STAT_VALVE_DETECTION_SWITCH_ID, MFG_CODE, data_types.Uint8, 0x01) })
  end
)

test.register_coroutine_test(
  "Handle antifreezeModeSetting in infochanged",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { ["stse.antifreezeModeSetting"] = "1" }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_ANTIFREEZE_MODE_TEMPERATURE_SETTING_ID, MFG_CODE, data_types.Uint32, 500) })
  end
)

test.register_coroutine_test(
  "hardwareFault report should be handled, detected",
  function()
    local attr_report_data = {
      { PRIVATE_THERMOSTAT_ALARM_INFORMATION_ID, data_types.Uint32.ID, 0x00000001 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.hardwareFault.hardwareFault.detected()))
  end
)

test.register_coroutine_test(
  "valve result report should be handled, successful",
  function()
    local attr_report_data = {
      { PRIVATE_VALVE_RESULT_CALIBRATION_ID, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      valveCalibration.calibrationState.calibrationSuccess()))
  end
)

test.register_coroutine_test(
  "thermostat mode report should be handled, manual",
  function()
    local attr_report_data = {
      { PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID, data_types.Uint8.ID, 0x00 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode.manual()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      invisibleCapabilities.invisibleCapabilities({""})))
  end
)

test.register_coroutine_test(
  "valve status report should be handled, close",
  function()
    local attr_report_data = {
      { PRIVATE_VALVE_SWITCH_ATTRIBUTE_ID, data_types.Uint8.ID, 0x00 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.valve.valve.closed()))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      invisibleCapabilities.invisibleCapabilities({"thermostatHeatingSetpoint","stse.valveCalibration","thermostatMode","lock"})))
  end
)

test.register_coroutine_test(
  "child lock status report should be handled, unlocked",
  function()
    local attr_report_data = {
      { PRIVATE_CHILD_LOCK_ID, data_types.Uint8.ID, 0x00 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("ChildLock",
      capabilities.lock.lock.unlocked()))
  end
)

test.register_coroutine_test(
  "Battery voltage report should be handled, 48",
  function()
    local attr_report_data = {
      { PRIVATE_BATTERY_ENERGY_ID, data_types.Uint8.ID, 0x30 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(48))
    )
  end
)

-- test.register_coroutine_test("ControlSequenceOfOperation reporting should create the appropriate events", function()
--   test.socket.zigbee:__queue_receive({mock_device.id,
--                                       Thermostat.attributes.ControlSequenceOfOperation:build_test_attr_report(
--     mock_device, 0x02)})
--   test.socket.capability:__expect_send(mock_device:generate_test_message("main",
--     capabilities.thermostatMode.supportedThermostatModes({
--       capabilities.thermostatMode.thermostatMode.manual.NAME,
--       capabilities.thermostatMode.thermostatMode.antifreezing.NAME
--     }, { visibility = { displayed = false } })))
-- end)

test.register_coroutine_test(
  "Capability on command should be handled : thermostat mode manual",
  function()
    local attr_report_data = {
      { PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID, data_types.Uint8.ID, 0x00 }
    }
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = thermostatModeId, component = "main", command = "setThermostatMode", args = {"manual"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_THERMOSTAT_OPERATING_MODE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x00)
    })
    test.wait_for_events()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode.manual())
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      invisibleCapabilities.invisibleCapabilities({""})))
    test.wait_for_events()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = thermostatModeId, component = "main", command = "setThermostatMode", args = {"manual"}}
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode.manual())
    )
  end
)

test.register_coroutine_test(
  "Capability on command should be handled : valve open",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "valve", component = "main", command = "open", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_VALVE_SWITCH_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01) })
  end
)

test.register_coroutine_test(
  "Capability on command should be handled : valve Calibration",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "stse.valveCalibration", component = "main", command = valveCalibrationCommandName, args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_VALVE_CALIBRATION_ID, MFG_CODE, data_types.Uint8, 0x01) })
  end
)


test.register_coroutine_test(
  "Capability on command should be handled : child lock locked",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "lock", component = "ChildLock", command = "lock", args = {} } })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
      PRIVATE_CHILD_LOCK_ID, MFG_CODE, data_types.Uint8, 0x01) })
  end
)
--]]
test.run_registered_tests()
