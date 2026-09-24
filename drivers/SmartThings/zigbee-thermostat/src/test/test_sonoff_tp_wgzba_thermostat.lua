-- Copyright 2026 SmartThings
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
local cluster_base = require "st.zigbee.cluster_base"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local generic_body = require "st.zigbee.generic_body"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local zcl_messages = require "st.zigbee.zcl"
local messages = require "st.zigbee.messages"
local zb_const = require "st.zigbee.constants"

local Basic = clusters.Basic
local Thermostat = clusters.Thermostat
local ThermostatSystemMode = Thermostat.attributes.SystemMode

local TemperatureCompensation = capabilities["samplereturn62595.temperatureCompensation"]
local ChildLock = capabilities["drumborder00833.childLockState"]
local OpenWindowDetection = capabilities["drumborder00833.openWindowDetection"]
local BtPairingBroadcastReq = capabilities["drumborder00833.bluetoothPairingBroadcastRequest"]
local FrostProofTemperature = capabilities["drumborder00833.frostProofTemperature"]
local OpenWindowState = capabilities["drumborder00833.openWindowState"]
local NtcTemperature = capabilities["drumborder00833.ntcTemperature"]
local TemporaryModeStatus = capabilities["drumborder00833.overrideStatus"]
local TemporaryModeDuration = capabilities["drumborder00833.overrideModeDuration"]
local TemporaryModeTemperature = capabilities["drumborder00833.overrideModeTemperature"]
local TemporaryModeAction = capabilities["drumborder00833.overrideAction"]
local TempCtrlThreshLow = capabilities["drumborder00833.temperatureControlThresholdLow"]
local TempCtrlThreshHigh = capabilities["drumborder00833.temperatureControlThresholdHigh"]
local RadarSensitivityLevel = capabilities["drumborder00833.radarSensitivityLevel"]
local RadarDoNotDisturbEnable = capabilities["drumborder00833.radarDoNotDisturbEnable"]
local RadarDndStartMin = capabilities["drumborder00833.radarDoNotDisturbStartMinute"]
local RadarDndEndMin = capabilities["drumborder00833.radarDoNotDisturbEndMinute"]
local ScreenWorkingBrightness = capabilities["drumborder00833.screenWorkingBrightness"]
local ScreenStandbyBrightness = capabilities["drumborder00833.screenStandbyBrightness"]
local ScreenNightStandbyBrightness = capabilities["drumborder00833.screenNightStandbyBrightness"]
local ScreenNightModeEnable = capabilities["drumborder00833.screenNightModeEnable"]
local ScreenNightStartMin = capabilities["drumborder00833.screenNightStartMinute"]
local ScreenNightEndMin = capabilities["drumborder00833.screenNightEndMinute"]
local RelayOutTypeR1 = capabilities["drumborder00833.relayHeatingContactType"]
local RelayOutTypeR2 = capabilities["drumborder00833.relayBoilerContactType"]
local OverheatProtectionTemperature = capabilities["drumborder00833.overheatProtectionTemperature"]
local OverheatProtectionEnable = capabilities["drumborder00833.overheatProtectionEnable"]
local RadarEnable = capabilities["drumborder00833.radarEnable"]

local custom_capabilities_available = pcall(function()
  OpenWindowState.openWindowState("closed")
end)

local MFG_CODE = 0x1286
local SONOFF_PRIVATE_CLUSTER = 0xFC11
local TEMPORARY_MODE_COMMAND_ID = 0x11

local CHILD_LOCK_ATTR = 0x0000
local BT_PAIRING_BROADCAST_REQ_ATTR = 0x0029
local OPEN_WINDOW_DETECTION_ATTR = 0x6000
local FROST_PROOF_TEMPERATURE_ATTR = 0x6002
local TEMPORARY_MODE_SETTINGS_ATTR = 0x6014
local TEMPERATURE_CONTROL_THRESHOLD_ATTR = 0x601F
local RADAR_SENSITIVITY_LEVEL_ATTR = 0x6020
local RADAR_DO_NOT_DISTURB_ENABLE_ATTR = 0x6021
local RADAR_DO_NOT_DISTURB_PERIOD_ATTR = 0x6022
local SCREEN_WORKING_BRIGHTNESS_ATTR = 0x6023
local SCREEN_STANDBY_BRIGHTNESS_ATTR = 0x6024
local SCREEN_NIGHT_STANDBY_BRIGHTNESS_ATTR = 0x6025
local SCREEN_NIGHT_MODE_ENABLE_ATTR = 0x6026
local SCREEN_NIGHT_MODE_PERIOD_ATTR = 0x6027
local RELAY_OUTPUT_TYPE_BITMAP_ATTR = 0x6028
local HVAC_MESSAGE_NOTIFICATION_ATTR = 0x6030
local CURRENT_NTC_TEMPERATURE_RAW_ATTR = 0x6031
local OVERHEAT_PROTECTION_TEMPERATURE_ATTR = 0x6032
local OVERHEAT_PROTECTION_ENABLE_ATTR = 0x6034
local RADAR_ENABLE_ATTR = 0x6035

-- Keep in sync with PRIVATE_REFRESH_ATTRIBUTES in sonoff/tp_wgzba/init.lua.
local PRIVATE_REFRESH_ATTRIBUTES = {
  CHILD_LOCK_ATTR,
  BT_PAIRING_BROADCAST_REQ_ATTR,
  OPEN_WINDOW_DETECTION_ATTR,
  FROST_PROOF_TEMPERATURE_ATTR,
  TEMPORARY_MODE_SETTINGS_ATTR,
  RADAR_SENSITIVITY_LEVEL_ATTR,
  RADAR_DO_NOT_DISTURB_ENABLE_ATTR,
  RADAR_DO_NOT_DISTURB_PERIOD_ATTR,
  SCREEN_WORKING_BRIGHTNESS_ATTR,
  SCREEN_STANDBY_BRIGHTNESS_ATTR,
  SCREEN_NIGHT_STANDBY_BRIGHTNESS_ATTR,
  SCREEN_NIGHT_MODE_ENABLE_ATTR,
  SCREEN_NIGHT_MODE_PERIOD_ATTR,
  RELAY_OUTPUT_TYPE_BITMAP_ATTR,
  HVAC_MESSAGE_NOTIFICATION_ATTR,
  CURRENT_NTC_TEMPERATURE_RAW_ATTR,
  OVERHEAT_PROTECTION_TEMPERATURE_ATTR,
  OVERHEAT_PROTECTION_ENABLE_ATTR,
  RADAR_ENABLE_ATTR
}

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("thermostat-sonoff.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "SONOFF",
        model = "TP-WGZBA",
        server_clusters = { 0x0001, 0x0201, 0xFC11 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function expect_main_and_temporary_defaults()
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", OpenWindowState.openWindowState("closed")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", NtcTemperature.ntcTemperature("Not Connected")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemperatureCompensation.temperatureCompensation({ value = 0.0, unit = "℃" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", ChildLock.childLockState("disabled")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", BtPairingBroadcastReq.btPairingBroadcastReq("disabled")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", OpenWindowDetection.openWindowDetection("disabled")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", FrostProofTemperature.frostProofTemperature({ value = 5.0, unit = "℃" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarSensitivityLevel.radarSensitivityLevel("high")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarDoNotDisturbEnable.radarDoNotDisturbEnable("disabled")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenWorkingBrightness.screenWorkingBrightness({ value = 5, unit = "level" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenStandbyBrightness.screenStandbyBrightness({ value = 0, unit = "level" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenNightStandbyBrightness.screenNightStandbyBrightness({ value = 0, unit = "level" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenNightModeEnable.screenNightModeEnable("disabled")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", OverheatProtectionTemperature.overheatProtectionTemperature({ value = 33.5, unit = "℃" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", OverheatProtectionEnable.overheatProtectionEnable("disabled")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarEnable.radarEnable("disabled")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", TempCtrlThreshLow.tempCtrlThreshLow({ value = -2.0, unit = "℃" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", TempCtrlThreshHigh.tempCtrlThreshHigh({ value = 2.0, unit = "℃" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarDndStartMin.radarDndStartMin({ value = 0, unit = "min" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarDndEndMin.radarDndEndMin({ value = 0, unit = "min" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenNightStartMin.screenNightStartMin({ value = 0, unit = "min" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenNightEndMin.screenNightEndMin({ value = 0, unit = "min" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", RelayOutTypeR1.relayOneOutputType("normallyOpen")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", RelayOutTypeR2.relayTwoOutputType("normallyOpen")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemporaryModeStatus.temporaryTemperatureModeSettings("None")))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemporaryModeDuration.temporaryModeTimeSet({ value = 30, unit = "min" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemporaryModeTemperature.temporaryModeTempSet({ value = 30.0, unit = "℃" })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemporaryModeAction.temporaryModeAction("exit")))
end

local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
  -- Driver startup always delivers lifecycle init, which seeds UI defaults.
  test.socket.capability:__set_channel_ordering("relaxed")
  expect_main_and_temporary_defaults()
end

test.set_test_init_function(test_init)

local function build_cluster_specific_command(cluster, command_id, payload)
  local zclh = zcl_messages.ZclHeader({
    cmd = data_types.ZCLCommandId(command_id)
  })
  zclh.frame_ctrl:set_cluster_specific()
  local addrh = messages.AddressHeader(
    zb_const.HUB.ADDR,
    zb_const.HUB.ENDPOINT,
    mock_device:get_short_address(),
    mock_device:get_endpoint(cluster),
    zb_const.HA_PROFILE_ID,
    cluster
  )
  return messages.ZigbeeMessageTx({
    address_header = addrh,
    body = zcl_messages.ZclMessageBody({
      zcl_header = zclh,
      zcl_body = generic_body.GenericBody(payload)
    })
  })
end

local function expect_refresh_reads()
  test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.LocalTemperature:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.SystemMode:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.ThermostatRunningState:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Thermostat.attributes.LocalTemperatureCalibration:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, Basic.attributes.SWBuildID:read(mock_device) })
  for _, attribute_id in ipairs(PRIVATE_REFRESH_ATTRIBUTES) do
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, attribute_id, MFG_CODE)
    })
  end
end

-- Builds a minimal device object for can_handle tests.
local function can_handle_device(manufacturer, model)
  -- The can_handle modules only depend on these two accessors.
  return {
    get_manufacturer = function()
      return manufacturer
    end,
    get_model = function()
      return model
    end
  }
end

-- Disables the global lifecycle expectations for direct can_handle tests.
local function noop_test_init()
  -- These tests do not register a mock device with the driver socket.
end

test.register_coroutine_test(
  "SONOFF can_handle modules should reject non-matching fingerprints",
  function()
    local aggregate_can_handle = require "sonoff.can_handle"
    local tp_wgzba_can_handle = require "sonoff.tp_wgzba.can_handle"

    local aggregate_rejected = aggregate_can_handle({}, nil, can_handle_device("SONOFF", "OTHER"))
    local tp_wgzba_rejected = tp_wgzba_can_handle({}, nil, can_handle_device("OTHER", "TP-WGZBA"))

    assert(not aggregate_rejected)
    assert(not tp_wgzba_rejected)
  end,
  {
    test_init = noop_test_init
  }
)

if custom_capabilities_available then

test.register_coroutine_test(
  "SONOFF can_handle modules should match TP-WGZBA",
  function()
    local aggregate_can_handle = require "sonoff.can_handle"
    local tp_wgzba_can_handle = require "sonoff.tp_wgzba.can_handle"

    local aggregate_handled, aggregate_sub_driver = aggregate_can_handle({}, nil, can_handle_device("SONOFF", "TP-WGZBA"))
    local tp_wgzba_handled, tp_wgzba_sub_driver = tp_wgzba_can_handle({}, nil, can_handle_device("SONOFF", "TP-WGZBA"))

    assert(aggregate_handled)
    assert(aggregate_sub_driver.NAME == "SONOFF Thermostat Handler")
    assert(tp_wgzba_handled)
    assert(tp_wgzba_sub_driver.NAME == "SONOFF TP-WGZBA Handler")
  end,
  {
    test_init = noop_test_init
  }
)

test.register_coroutine_test(
  "Device added should emit supported modes and refresh after init already seeded defaults",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.thermostatMode.supportedThermostatModes(
          { "off", "auto", "heat" },
          { visibility = { displayed = false } }
        )
      )
    )
    expect_refresh_reads()
  end
)

test.register_coroutine_test(
  "Driver switched should emit supported modes and refresh after init already seeded defaults",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "driverSwitched" })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main",
        capabilities.thermostatMode.supportedThermostatModes(
          { "off", "auto", "heat" },
          { visibility = { displayed = false } }
        )
      )
    )
    expect_refresh_reads()
  end
)

test.register_coroutine_test(
  "Init should not re-emit defaults when capability state is already seeded",
  function()
    -- Startup init already populated state in test_init; a second init must be a no-op.
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  end
)

test.register_message_test(
  "Temperature reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device, 2350) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 23.5, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Heating setpoint reports should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device, 2100) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 21.0, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Running state reports using the thermostat cluster should be handled",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Thermostat.attributes.ThermostatRunningState:build_test_attr_report(mock_device, 1) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatOperatingState.thermostatOperatingState("heating"))
    }
  }
)

test.register_message_test(
  "Basic SWBuildID reports should update the firmware version",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, Basic.attributes.SWBuildID:build_test_attr_report(mock_device, "1.0.4") }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.firmwareUpdate.currentVersion({ value = "1.0.4" }))
    }
  }
)

test.register_coroutine_test(
  "Local temperature calibration reports should emit temperature compensation",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      Thermostat.attributes.LocalTemperatureCalibration:build_test_attr_report(mock_device, -15)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemperatureCompensation.temperatureCompensation({ value = -1.5, unit = "℃" }))
    )
  end
)

test.register_coroutine_test(
  "Temporary mode state reports should emit none/boost/timer from vendor attr 0x6014",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { TEMPORARY_MODE_SETTINGS_ATTR, data_types.Uint8.ID, 0xFF }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeStatus.temporaryTemperatureModeSettings("None"))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { TEMPORARY_MODE_SETTINGS_ATTR, data_types.Uint8.ID, 0x00 }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeStatus.temporaryTemperatureModeSettings("Boost"))
    )

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { TEMPORARY_MODE_SETTINGS_ATTR, data_types.Uint8.ID, 0x01 }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeStatus.temporaryTemperatureModeSettings("Timer"))
    )
  end
)

test.register_coroutine_test(
  "Child lock reports and capability writes should map through private attr 0x0000",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { CHILD_LOCK_ATTR, data_types.Boolean.ID, true }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", ChildLock.childLockState("enabled")))

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = ChildLock.ID, component = "main", command = "setChildLockState", args = { "disabled" } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, CHILD_LOCK_ATTR, MFG_CODE, data_types.Boolean, false)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", ChildLock.childLockState("disabled")))
  end
)

test.register_coroutine_test(
  "Setting thermostat mode should write SystemMode without readback",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatMode", command = "auto", args = {}, component = "main" }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:write(mock_device, ThermostatSystemMode.AUTO)
    })

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatMode", command = "heat", args = {}, component = "main" }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:write(mock_device, ThermostatSystemMode.HEAT)
    })

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatMode", command = "off", args = {}, component = "main" }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.SystemMode:write(mock_device, ThermostatSystemMode.OFF)
    })
  end
)

test.register_coroutine_test(
  "Setting heating setpoint should write OccupiedHeatingSetpoint",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      -- positional for API 57; named_args for newer libs with empty reconstructed arg_lists
      { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 22 }, named_args = { setpoint = 22 } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 2200)
    })
  end
)

test.register_coroutine_test(
  "Setting heating setpoint should clamp values below the supported range",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 4 }, named_args = { setpoint = 4 } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 500)
    })
  end
)

test.register_coroutine_test(
  "Setting heating setpoint should clamp values above the supported range",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 31 }, named_args = { setpoint = 31 } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.OccupiedHeatingSetpoint:write(mock_device, 3000)
    })
  end
)

test.register_coroutine_test(
  "Temperature compensation capability should write LocalTemperatureCalibration",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {
        capability = TemperatureCompensation.ID,
        component = "main",
        command = "setTemperatureCompensation",
        args = { -1.5 }
      }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      Thermostat.attributes.LocalTemperatureCalibration:write(mock_device, -15)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemperatureCompensation.temperatureCompensation({ value = -1.5, unit = "℃" }))
    )
  end
)

test.register_message_test(
  "Refresh should read standard thermostat attrs and selected private attrs",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, Thermostat.attributes.LocalTemperature:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, Thermostat.attributes.OccupiedHeatingSetpoint:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, Thermostat.attributes.SystemMode:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, Thermostat.attributes.ThermostatRunningState:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, Thermostat.attributes.LocalTemperatureCalibration:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, Basic.attributes.SWBuildID:read(mock_device) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, CHILD_LOCK_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, BT_PAIRING_BROADCAST_REQ_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, OPEN_WINDOW_DETECTION_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, FROST_PROOF_TEMPERATURE_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, TEMPORARY_MODE_SETTINGS_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RADAR_SENSITIVITY_LEVEL_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RADAR_DO_NOT_DISTURB_ENABLE_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RADAR_DO_NOT_DISTURB_PERIOD_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, SCREEN_WORKING_BRIGHTNESS_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, SCREEN_STANDBY_BRIGHTNESS_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, SCREEN_NIGHT_STANDBY_BRIGHTNESS_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, SCREEN_NIGHT_MODE_ENABLE_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, SCREEN_NIGHT_MODE_PERIOD_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RELAY_OUTPUT_TYPE_BITMAP_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, HVAC_MESSAGE_NOTIFICATION_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, CURRENT_NTC_TEMPERATURE_RAW_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, OVERHEAT_PROTECTION_TEMPERATURE_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, OVERHEAT_PROTECTION_ENABLE_ATTR, MFG_CODE) }
    },
    {
      channel = "zigbee",
      direction = "send",
      message = { mock_device.id, cluster_base.read_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RADAR_ENABLE_ATTR, MFG_CODE) }
    }
  }
)

test.register_coroutine_test(
  "Configure should bind Thermostat cluster without configuring reports",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Thermostat.ID)
    })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Simple private capability writes should update vendor attributes and emit events",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = OpenWindowDetection.ID, component = "main", command = "setOpenWindowDetection", args = { "enabled" } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, OPEN_WINDOW_DETECTION_ATTR, MFG_CODE, data_types.Boolean, true)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", OpenWindowDetection.openWindowDetection("enabled")))

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = FrostProofTemperature.ID, component = "main", command = "setFrostProofTemperature", args = { 7.5 } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, FROST_PROOF_TEMPERATURE_ATTR, MFG_CODE, data_types.Int16, 750)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", FrostProofTemperature.frostProofTemperature({ value = 7.5, unit = "℃" })))

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = RadarEnable.ID, component = "main", command = "setRadarEnable", args = { "enabled" } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RADAR_ENABLE_ATTR, MFG_CODE, data_types.Boolean, true)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarEnable.radarEnable("enabled")))

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = RadarSensitivityLevel.ID, component = "main", command = "setRadarSensitivityLevel", args = { "high" } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RADAR_SENSITIVITY_LEVEL_ATTR, MFG_CODE, data_types.Uint8, 2)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarSensitivityLevel.radarSensitivityLevel("high")))
  end
)

test.register_coroutine_test(
  "Threshold and time-period capability writes should rewrite vendor structures",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TempCtrlThreshHigh.ID, component = "main", command = "setTempCtrlThreshHigh", args = { 1.8 } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(
        mock_device,
        SONOFF_PRIVATE_CLUSTER,
        TEMPERATURE_CONTROL_THRESHOLD_ATTR,
        MFG_CODE,
        data_types.Structure,
        data_types.Structure({
          data_types.Int16(-200),
          data_types.Int16(180)
        })
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", TempCtrlThreshLow.tempCtrlThreshLow({ value = -2.0, unit = "℃" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", TempCtrlThreshHigh.tempCtrlThreshHigh({ value = 1.8, unit = "℃" })))

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = RadarDndStartMin.ID, component = "main", command = "setRadarDndStartMin", args = { 65 } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(
        mock_device,
        SONOFF_PRIVATE_CLUSTER,
        RADAR_DO_NOT_DISTURB_PERIOD_ATTR,
        MFG_CODE,
        data_types.Structure,
        data_types.Structure({
          data_types.Uint16(60),
          data_types.Uint16(0)
        })
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarDndStartMin.radarDndStartMin({ value = 60, unit = "min" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RadarDndEndMin.radarDndEndMin({ value = 0, unit = "min" })))

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = ScreenNightEndMin.ID, component = "main", command = "setScreenNightEndMin", args = { 1410 } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(
        mock_device,
        SONOFF_PRIVATE_CLUSTER,
        SCREEN_NIGHT_MODE_PERIOD_ATTR,
        MFG_CODE,
        data_types.Structure,
        data_types.Structure({
          data_types.Uint16(0),
          data_types.Uint16(1410)
        })
      )
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenNightStartMin.screenNightStartMin({ value = 0, unit = "min" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", ScreenNightEndMin.screenNightEndMin({ value = 1410, unit = "min" })))
  end
)

test.register_coroutine_test(
  "Relay capability writes should rewrite the vendor bitmap with Bitmap8",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = RelayOutTypeR1.ID, component = "main", command = "setRelayOneOutputType", args = { "normallyClosed" } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, SONOFF_PRIVATE_CLUSTER, RELAY_OUTPUT_TYPE_BITMAP_ATTR, MFG_CODE, data_types.Bitmap8, 1)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RelayOutTypeR1.relayOneOutputType("normallyClosed")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RelayOutTypeR2.relayTwoOutputType("normallyOpen")))
  end
)

test.register_coroutine_test(
  "Temporary mode duration and temperature only update local capability state",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeDuration.ID, component = "main", command = "setTemporaryModeTimeSet", args = { 45 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeDuration.temporaryModeTimeSet({ value = 45, unit = "min" }))
    )

    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeTemperature.ID, component = "main", command = "setTemporaryModeTempSet", args = { 28.5 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeTemperature.temporaryModeTempSet({ value = 28.5, unit = "℃" }))
    )
  end
)

test.register_coroutine_test(
  "Temporary mode exit sends vendor command then emits action state",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeAction.ID, component = "main", command = "setTemporaryModeAction", args = { "exit" } }
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      build_cluster_specific_command(SONOFF_PRIVATE_CLUSTER, TEMPORARY_MODE_COMMAND_ID, "\x00")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemporaryModeAction.temporaryModeAction("exit")))
  end
)

test.register_coroutine_test(
  "Temporary mode boost forces 30C UI temperature and sends vendor payload",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeDuration.ID, component = "main", command = "setTemporaryModeTimeSet", args = { 45 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeDuration.temporaryModeTimeSet({ value = 45, unit = "min" }))
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeAction.ID, component = "main", command = "setTemporaryModeAction", args = { "boost" } }
    })
    -- action, duration seconds LE (45*60=2700 -> 8C 0A 00 00), temperature 30.00C -> B8 0B
    test.socket.zigbee:__expect_send({
      mock_device.id,
      build_cluster_specific_command(SONOFF_PRIVATE_CLUSTER, TEMPORARY_MODE_COMMAND_ID, "\x01\x8C\x0A\x00\x00\xB8\x0B")
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeTemperature.temporaryModeTempSet({ value = 30.0, unit = "℃" }))
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemporaryModeAction.temporaryModeAction("boost")))
  end
)

test.register_coroutine_test(
  "Temporary mode timer sends vendor payload built from cached duration and temperature",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeDuration.ID, component = "main", command = "setTemporaryModeTimeSet", args = { 45 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeDuration.temporaryModeTimeSet({ value = 45, unit = "min" }))
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeTemperature.ID, component = "main", command = "setTemporaryModeTempSet", args = { 28.5 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", TemporaryModeTemperature.temporaryModeTempSet({ value = 28.5, unit = "℃" }))
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = TemporaryModeAction.ID, component = "main", command = "setTemporaryModeAction", args = { "timer" } }
    })
    -- action=2, duration 2700s, temperature 28.50C -> 22 0B
    test.socket.zigbee:__expect_send({
      mock_device.id,
      build_cluster_specific_command(SONOFF_PRIVATE_CLUSTER, TEMPORARY_MODE_COMMAND_ID, "\x02\x8C\x0A\x00\x00\x22\x0B")
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", TemporaryModeAction.temporaryModeAction("timer")))
  end
)

test.register_coroutine_test(
  "HVAC message and NTC private reports should update read-only capabilities",
  function()
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { HVAC_MESSAGE_NOTIFICATION_ATTR, data_types.OctetString.ID, "\x00\x01\x01" }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", OpenWindowState.openWindowState("open")))

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { CURRENT_NTC_TEMPERATURE_RAW_ATTR, data_types.Int16.ID, 2350 }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", NtcTemperature.ntcTemperature("23.50 C")))

    test.wait_for_events()

    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { CURRENT_NTC_TEMPERATURE_RAW_ATTR, data_types.Int16.ID, -32768 }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", NtcTemperature.ntcTemperature("Not Connected")))
  end
)

test.register_coroutine_test(
  "Relay bitmap reports should split into heating and boiler contact capabilities",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, SONOFF_PRIVATE_CLUSTER, {
        { RELAY_OUTPUT_TYPE_BITMAP_ATTR, data_types.Bitmap8.ID, 0x03 }
      }, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RelayOutTypeR1.relayOneOutputType("normallyClosed")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", RelayOutTypeR2.relayTwoOutputType("normallyClosed")))
  end
)

end

test.run_registered_tests()
