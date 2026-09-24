-- Copyright 2026 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.

local capabilities = require "st.capabilities"
local cluster_base = require "st.zigbee.cluster_base"
local clusters = require "st.zigbee.zcl.clusters"
local data_types = require "st.zigbee.data_types"
local device_management = require "st.zigbee.device_management"
local generic_body = require "st.zigbee.generic_body"
local utils = require "st.utils"
local ZigbeeConstants = require "st.zigbee.constants"
local ZigbeeMessages = require "st.zigbee.messages"
local ZigbeeZcl = require "st.zigbee.zcl"
local log = require "log"

local Basic = clusters.Basic
local Thermostat = clusters.Thermostat

local FirmwareUpdate = capabilities.firmwareUpdate
local ThermostatHeatingSetpoint = capabilities.thermostatHeatingSetpoint
local ThermostatMode = capabilities.thermostatMode
local ThermostatOperatingState = capabilities.thermostatOperatingState
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

local SONOFF_MFG_CODE = 0x1286
local SONOFF_PRIVATE_CLUSTER = 0xFC11

local TEMPORARY_MODE_COMMAND_ID = 0x11
local TEMPORARY_MODE_EXIT = 0x00
local TEMPORARY_MODE_BOOST = 0x01
local TEMPORARY_MODE_TIMER = 0x02
local TEMPORARY_MODE_ATTR_BOOST = 0x00
local TEMPORARY_MODE_ATTR_TIMER = 0x01
local TEMPORARY_MODE_ATTR_NONE = 0xFF

local PRIVATE_ATTR_CHILD_LOCK = 0x0000
local PRIVATE_ATTR_BT_PAIRING_BROADCAST_REQ = 0x0029
local PRIVATE_ATTR_OPEN_WINDOW_DETECTION = 0x6000
local PRIVATE_ATTR_FROST_PROOF_TEMPERATURE = 0x6002
local PRIVATE_ATTR_TEMPORARY_MODE_SETTINGS = 0x6014
local PRIVATE_ATTR_TEMPERATURE_CONTROL_THRESHOLD = 0x601F
local PRIVATE_ATTR_RADAR_SENSITIVITY_LEVEL = 0x6020
local PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_ENABLE = 0x6021
local PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD = 0x6022
local PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS = 0x6023
local PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS = 0x6024
local PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS = 0x6025
local PRIVATE_ATTR_SCREEN_NIGHT_MODE_ENABLE = 0x6026
local PRIVATE_ATTR_SCREEN_NIGHT_MODE_PERIOD = 0x6027
local PRIVATE_ATTR_RELAY_OUTPUT_TYPE_BITMAP = 0x6028
local PRIVATE_ATTR_HVAC_MESSAGE_NOTIFICATION = 0x6030
local PRIVATE_ATTR_CURRENT_NTC_TEMPERATURE_RAW = 0x6031
local PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE = 0x6032
local PRIVATE_ATTR_OVERHEAT_PROTECTION_ENABLE = 0x6034
local PRIVATE_ATTR_RADAR_ENABLE = 0x6035

local CAPABILITY_STATE_ENABLED = "enabled"
local CAPABILITY_STATE_DISABLED = "disabled"
local OPEN_WINDOW_STATE_OPEN = "open"
local OPEN_WINDOW_STATE_CLOSED = "closed"
local RADAR_SENSITIVITY_LOW = "low"
local RADAR_SENSITIVITY_MEDIUM = "medium"
local RADAR_SENSITIVITY_HIGH = "high"
local RELAY_OUTPUT_TYPE_NORMALLY_OPEN = "normallyOpen"
local RELAY_OUTPUT_TYPE_NORMALLY_CLOSED = "normallyClosed"
local TEMPORARY_MODE_STATE_NONE = "None"
local TEMPORARY_MODE_STATE_BOOST = "Boost"
local TEMPORARY_MODE_STATE_TIMER = "Timer"
local TEMPORARY_MODE_ACTION_EXIT = "exit"
local TEMPORARY_MODE_ACTION_BOOST = "boost"
local TEMPORARY_MODE_ACTION_TIMER = "timer"
local UNIT_CELSIUS = "℃"
local UNIT_MINUTES = "min"
local UNIT_LEVEL = "level"
local PRIVATE_HVAC_OPEN_WINDOW_TLV = 0x00
local PRIVATE_HVAC_OPEN_WINDOW_TLV_LENGTH = 0x01
local PRIVATE_NTC_INVALID_CODE = -32768
local PRIVATE_NTC_OPEN_CIRCUIT_CODE = -32512
local PRIVATE_NTC_SHORT_CIRCUIT_CODE = -32256
local PRIVATE_NTC_ADC_INVALID_CODE = -32000
local PRIVATE_NTC_MIN_VALID = -27315
local PRIVATE_TEMP_CTRL_THRESH_LOW_DEFAULT = -2.0
local PRIVATE_TEMP_CTRL_THRESH_HIGH_DEFAULT = 2.0
local PRIVATE_TEMP_CTRL_THRESH_LOW_MIN = -2.6
local PRIVATE_TEMP_CTRL_THRESH_LOW_MAX = -0.2
local PRIVATE_TEMP_CTRL_THRESH_HIGH_MIN = 0.0
local PRIVATE_TEMP_CTRL_THRESH_HIGH_MAX = 2.6
local PRIVATE_TIME_STEP_MINUTES = 30
local PRIVATE_TIME_MAX_MINUTES = 1439
local SUPPORTED_MODES = {
  ThermostatMode.thermostatMode.off.NAME,
  ThermostatMode.thermostatMode.auto.NAME,
  ThermostatMode.thermostatMode.heat.NAME
}

local THERMOSTAT_MODE_MAP = {
  [ThermostatMode.thermostatMode.off.NAME] = Thermostat.attributes.SystemMode.OFF,
  [ThermostatMode.thermostatMode.auto.NAME] = Thermostat.attributes.SystemMode.AUTO,
  [ThermostatMode.thermostatMode.heat.NAME] = Thermostat.attributes.SystemMode.HEAT
}

local SIMPLE_PRIVATE_ATTRIBUTE_INFO = {
  [PRIVATE_ATTR_CHILD_LOCK] = {
    capability = ChildLock,
    attribute_name = "childLockState",
    argument_name = "childLockState",
    data_type = data_types.Boolean,
    kind = "bool"
  },
  [PRIVATE_ATTR_BT_PAIRING_BROADCAST_REQ] = {
    capability = BtPairingBroadcastReq,
    attribute_name = "btPairingBroadcastReq",
    argument_name = "btPairingBroadcastReq",
    data_type = data_types.Uint8,
    kind = "enum",
    enum_values = {
      [0] = CAPABILITY_STATE_DISABLED,
      [1] = CAPABILITY_STATE_ENABLED
    },
    reverse_enum_values = {
      [CAPABILITY_STATE_DISABLED] = 0,
      [CAPABILITY_STATE_ENABLED] = 1
    }
  },
  [PRIVATE_ATTR_OPEN_WINDOW_DETECTION] = {
    capability = OpenWindowDetection,
    attribute_name = "openWindowDetection",
    argument_name = "openWindowDetection",
    data_type = data_types.Boolean,
    kind = "bool"
  },
  [PRIVATE_ATTR_FROST_PROOF_TEMPERATURE] = {
    capability = FrostProofTemperature,
    attribute_name = "frostProofTemperature",
    argument_name = "frostProofTemperature",
    data_type = data_types.Int16,
    kind = "scaled",
    min = 5.0,
    max = 15.0,
    scale = 100,
    unit = UNIT_CELSIUS
  },
  [PRIVATE_ATTR_TEMPORARY_MODE_SETTINGS] = {
    capability = TemporaryModeStatus,
    attribute_name = "temporaryTemperatureModeSettings",
    argument_name = "temporaryTemperatureModeSettings",
    data_type = data_types.Uint8,
    kind = "enum",
    enum_values = {
      [TEMPORARY_MODE_ATTR_NONE] = TEMPORARY_MODE_STATE_NONE,
      [TEMPORARY_MODE_ATTR_BOOST] = TEMPORARY_MODE_STATE_BOOST,
      [TEMPORARY_MODE_ATTR_TIMER] = TEMPORARY_MODE_STATE_TIMER
    }
  },
  [PRIVATE_ATTR_RADAR_SENSITIVITY_LEVEL] = {
    capability = RadarSensitivityLevel,
    attribute_name = "radarSensitivityLevel",
    argument_name = "radarSensitivityLevel",
    data_type = data_types.Uint8,
    kind = "enum",
    enum_values = {
      [0] = RADAR_SENSITIVITY_LOW,
      [1] = RADAR_SENSITIVITY_MEDIUM,
      [2] = RADAR_SENSITIVITY_HIGH
    },
    reverse_enum_values = {
      [RADAR_SENSITIVITY_LOW] = 0,
      [RADAR_SENSITIVITY_MEDIUM] = 1,
      [RADAR_SENSITIVITY_HIGH] = 2
    }
  },
  [PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_ENABLE] = {
    capability = RadarDoNotDisturbEnable,
    attribute_name = "radarDoNotDisturbEnable",
    argument_name = "radarDoNotDisturbEnable",
    data_type = data_types.Boolean,
    kind = "bool"
  },
  [PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS] = {
    capability = ScreenWorkingBrightness,
    attribute_name = "screenWorkingBrightness",
    argument_name = "screenWorkingBrightness",
    data_type = data_types.Uint8,
    kind = "int",
    min = 0,
    max = 8,
    unit = UNIT_LEVEL
  },
  [PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS] = {
    capability = ScreenStandbyBrightness,
    attribute_name = "screenStandbyBrightness",
    argument_name = "screenStandbyBrightness",
    data_type = data_types.Uint8,
    kind = "int",
    min = 0,
    max = 8,
    unit = UNIT_LEVEL
  },
  [PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS] = {
    capability = ScreenNightStandbyBrightness,
    attribute_name = "screenNightStandbyBrightness",
    argument_name = "screenNightStandbyBrightness",
    data_type = data_types.Uint8,
    kind = "int",
    min = 0,
    max = 8,
    unit = UNIT_LEVEL
  },
  [PRIVATE_ATTR_SCREEN_NIGHT_MODE_ENABLE] = {
    capability = ScreenNightModeEnable,
    attribute_name = "screenNightModeEnable",
    argument_name = "screenNightModeEnable",
    data_type = data_types.Boolean,
    kind = "bool"
  },
  [PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE] = {
    capability = OverheatProtectionTemperature,
    attribute_name = "overheatProtectionTemperature",
    argument_name = "overheatProtectionTemperature",
    data_type = data_types.Int16,
    kind = "scaled",
    min = 20.0,
    max = 50.0,
    scale = 100,
    unit = UNIT_CELSIUS
  },
  [PRIVATE_ATTR_OVERHEAT_PROTECTION_ENABLE] = {
    capability = OverheatProtectionEnable,
    attribute_name = "overheatProtectionEnable",
    argument_name = "overheatProtectionEnable",
    data_type = data_types.Boolean,
    kind = "bool"
  },
  [PRIVATE_ATTR_RADAR_ENABLE] = {
    capability = RadarEnable,
    attribute_name = "radarEnable",
    argument_name = "radarEnable",
    data_type = data_types.Boolean,
    kind = "bool"
  }
}

local PRIVATE_REFRESH_ATTRIBUTES = {
  PRIVATE_ATTR_CHILD_LOCK,
  PRIVATE_ATTR_BT_PAIRING_BROADCAST_REQ,
  PRIVATE_ATTR_OPEN_WINDOW_DETECTION,
  PRIVATE_ATTR_FROST_PROOF_TEMPERATURE,
  PRIVATE_ATTR_TEMPORARY_MODE_SETTINGS,
  PRIVATE_ATTR_RADAR_SENSITIVITY_LEVEL,
  PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_ENABLE,
  PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD,
  PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS,
  PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS,
  PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS,
  PRIVATE_ATTR_SCREEN_NIGHT_MODE_ENABLE,
  PRIVATE_ATTR_SCREEN_NIGHT_MODE_PERIOD,
  PRIVATE_ATTR_RELAY_OUTPUT_TYPE_BITMAP,
  PRIVATE_ATTR_HVAC_MESSAGE_NOTIFICATION,
  PRIVATE_ATTR_CURRENT_NTC_TEMPERATURE_RAW,
  PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE,
  PRIVATE_ATTR_OVERHEAT_PROTECTION_ENABLE,
  PRIVATE_ATTR_RADAR_ENABLE
}

local INITIAL_SIMPLE_PRIVATE_ATTRIBUTE_DEFAULTS = {
  [PRIVATE_ATTR_CHILD_LOCK] = false,
  [PRIVATE_ATTR_BT_PAIRING_BROADCAST_REQ] = 0,
  [PRIVATE_ATTR_OPEN_WINDOW_DETECTION] = false,
  [PRIVATE_ATTR_FROST_PROOF_TEMPERATURE] = 500,
  [PRIVATE_ATTR_RADAR_SENSITIVITY_LEVEL] = 2,
  [PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_ENABLE] = false,
  [PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS] = 5,
  [PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS] = 0,
  [PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS] = 0,
  [PRIVATE_ATTR_SCREEN_NIGHT_MODE_ENABLE] = false,
  [PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE] = 3350,
  [PRIVATE_ATTR_OVERHEAT_PROTECTION_ENABLE] = false,
  [PRIVATE_ATTR_RADAR_ENABLE] = false
}

local emit_simple_private_attribute
local write_temperature_control_threshold

-- Emits an event only when the active profile declares the capability.
local function emit_event_if_supported(device, capability, event)
  -- This keeps sub-driver code safe if the profile is temporarily pared down.
  if device:supports_capability_by_id(capability.ID) then
    device:emit_event(event)
  end
end

-- Emits the supported thermostat mode list expected by TP-WGZBA.
local function emit_supported_modes(device)
  -- The device only exposes off, auto, and heat in the first version.
  device:emit_event(ThermostatMode.supportedThermostatModes(SUPPORTED_MODES, { visibility = { displayed = false } }))
end

-- Seeds writable main-page capability defaults only when the driver has no cached state yet.
local function emit_main_page_defaults_if_needed(device)
  -- Keep initial controls clickable during join-time gaps or when a vendor report is temporarily missing.
  if device:get_latest_state("main", OpenWindowState.ID, "openWindowState", nil) == nil then
    emit_event_if_supported(device, OpenWindowState, OpenWindowState.openWindowState(OPEN_WINDOW_STATE_CLOSED))
  end
  if device:get_latest_state("main", NtcTemperature.ID, "ntcTemperature", nil) == nil then
    emit_event_if_supported(device, NtcTemperature, NtcTemperature.ntcTemperature("Not Connected"))
  end
  if device:get_latest_state("main", TemperatureCompensation.ID, "temperatureCompensation", nil) == nil then
    emit_event_if_supported(device, TemperatureCompensation, TemperatureCompensation.temperatureCompensation({ value = 0.0, unit = UNIT_CELSIUS }))
  end

  for attribute_id, raw_value in pairs(INITIAL_SIMPLE_PRIVATE_ATTRIBUTE_DEFAULTS) do
    local info = SIMPLE_PRIVATE_ATTRIBUTE_INFO[attribute_id]
    if info ~= nil and device:get_latest_state("main", info.capability.ID, info.attribute_name, nil) == nil then
      emit_simple_private_attribute(device, attribute_id, raw_value)
    end
  end

  -- Seed the split threshold pair with the firmware defaults until the real struct arrives.
  if device:get_latest_state("main", TempCtrlThreshLow.ID, "tempCtrlThreshLow", nil) == nil then
    emit_event_if_supported(
      device,
      TempCtrlThreshLow,
      TempCtrlThreshLow.tempCtrlThreshLow({ value = PRIVATE_TEMP_CTRL_THRESH_LOW_DEFAULT, unit = UNIT_CELSIUS })
    )
  end
  if device:get_latest_state("main", TempCtrlThreshHigh.ID, "tempCtrlThreshHigh", nil) == nil then
    emit_event_if_supported(
      device,
      TempCtrlThreshHigh,
      TempCtrlThreshHigh.tempCtrlThreshHigh({ value = PRIVATE_TEMP_CTRL_THRESH_HIGH_DEFAULT, unit = UNIT_CELSIUS })
    )
  end

  -- Seed both time-period pairs so the UI remains operable before the first structure report.
  if device:get_latest_state("main", RadarDndStartMin.ID, "radarDndStartMin", nil) == nil then
    emit_event_if_supported(device, RadarDndStartMin, RadarDndStartMin.radarDndStartMin({ value = 0, unit = UNIT_MINUTES }))
  end
  if device:get_latest_state("main", RadarDndEndMin.ID, "radarDndEndMin", nil) == nil then
    emit_event_if_supported(device, RadarDndEndMin, RadarDndEndMin.radarDndEndMin({ value = 0, unit = UNIT_MINUTES }))
  end
  if device:get_latest_state("main", ScreenNightStartMin.ID, "screenNightStartMin", nil) == nil then
    emit_event_if_supported(device, ScreenNightStartMin, ScreenNightStartMin.screenNightStartMin({ value = 0, unit = UNIT_MINUTES }))
  end
  if device:get_latest_state("main", ScreenNightEndMin.ID, "screenNightEndMin", nil) == nil then
    emit_event_if_supported(device, ScreenNightEndMin, ScreenNightEndMin.screenNightEndMin({ value = 0, unit = UNIT_MINUTES }))
  end

  -- Seed relay contact polarity with the firmware default bitmap until the real value is reported.
  if device:get_latest_state("main", RelayOutTypeR1.ID, "relayOneOutputType", nil) == nil then
    emit_event_if_supported(device, RelayOutTypeR1, RelayOutTypeR1.relayOneOutputType(RELAY_OUTPUT_TYPE_NORMALLY_OPEN))
  end
  if device:get_latest_state("main", RelayOutTypeR2.ID, "relayTwoOutputType", nil) == nil then
    emit_event_if_supported(device, RelayOutTypeR2, RelayOutTypeR2.relayTwoOutputType(RELAY_OUTPUT_TYPE_NORMALLY_OPEN))
  end
end

-- Reads a SONOFF private cluster attribute using the eWeLink manufacturer code.
local function read_private_attribute(device, attribute_id)
  -- Manufacturer-specific reads are required for the 0xFC11 vendor cluster.
  return cluster_base.read_manufacturer_specific_attribute(device, SONOFF_PRIVATE_CLUSTER, attribute_id, SONOFF_MFG_CODE)
end

-- Writes a SONOFF private cluster attribute with the provided typed payload.
local function write_private_attribute(device, attribute_id, data_type, value)
  -- Preserve numeric precision by letting the Zigbee type builder own encoding.
  return cluster_base.write_manufacturer_specific_attribute(device, SONOFF_PRIVATE_CLUSTER, attribute_id, SONOFF_MFG_CODE, data_type, value)
end

-- Sends a SONOFF private cluster-specific command with a raw payload body.
local function send_private_cluster_command(device, command_id, payload)
  -- The private command lives on the vendor cluster rather than a standard Zigbee attribute write path.
  local endpoint = device:get_endpoint(SONOFF_PRIVATE_CLUSTER) or device.fingerprinted_endpoint_id or 1
  local zcl_header = ZigbeeZcl.ZclHeader({
    cmd = data_types.ZCLCommandId(command_id)
  })
  zcl_header.frame_ctrl:set_cluster_specific()

  return ZigbeeMessages.ZigbeeMessageTx({
    address_header = ZigbeeMessages.AddressHeader(
      ZigbeeConstants.HUB.ADDR,
      ZigbeeConstants.HUB.ENDPOINT,
      device:get_short_address(),
      endpoint,
      ZigbeeConstants.HA_PROFILE_ID,
      SONOFF_PRIVATE_CLUSTER
    ),
    body = ZigbeeZcl.ZclMessageBody({
      zcl_header = zcl_header,
      zcl_body = generic_body.GenericBody(payload)
    })
  })
end

-- Converts a wrapped Zigbee value to its raw payload value.
local function get_attribute_value(value)
  -- Attr handlers receive both raw tables and typed wrappers depending on the path.
  if type(value) == "table" and value.value ~= nil then
    return value.value
  end
  return value
end

-- Returns raw bytes from a Zigbee payload object when the private attr uses an opaque byte string.
local function get_payload_bytes(value)
  -- Vendor message attributes may arrive as raw strings or nested wrappers.
  if type(value) == "string" then
    return value
  end
  if type(value) == "table" then
    if type(value.value) == "string" then
      return value.value
    end
    if type(value.value) == "table" and type(value.value.value) == "string" then
      return value.value.value
    end
  end
  return nil
end

-- Converts a SmartThings number-like value to a Lua number.
local function coerce_numeric_value(value)
  -- Capability arguments may arrive as either numbers or decimal strings.
  if type(value) == "number" then
    return value
  end
  if type(value) == "string" and value ~= "" then
    return tonumber(value)
  end
  return nil
end

-- Returns the latest numeric state for a capability, or the provided fallback.
local function get_latest_numeric_state(device, capability, attribute_name, fallback)
  -- Temporary mode duration and target temperature are UI-side cached values.
  local cached_value = device:get_latest_state("main", capability.ID, attribute_name, fallback)
  local numeric_value = coerce_numeric_value(cached_value)
  if numeric_value == nil then
    return fallback
  end
  return numeric_value
end

-- Snaps a minute value to the device's 30-minute grid and valid range.
local function normalize_half_hour_minutes(value)
  -- The device stores radar and screen periods in 30-minute steps only.
  local numeric_value = coerce_numeric_value(value)
  if numeric_value == nil then
    return nil
  end

  numeric_value = utils.clamp_value(utils.round(numeric_value), 0, PRIVATE_TIME_MAX_MINUTES)
  local snapped_value = math.floor((numeric_value + (PRIVATE_TIME_STEP_MINUTES / 2)) / PRIVATE_TIME_STEP_MINUTES) * PRIVATE_TIME_STEP_MINUTES
  return math.min(snapped_value, PRIVATE_TIME_MAX_MINUTES - (PRIVATE_TIME_MAX_MINUTES % PRIVATE_TIME_STEP_MINUTES))
end

-- Encodes an unsigned 16-bit value in little-endian order.
local function encode_uint16_le(value)
  -- Avoid string.pack so this runs on the stock SmartThings Lua runtime.
  local normalized = math.floor(value) % 0x10000
  return string.char(normalized % 0x100, math.floor(normalized / 0x100))
end

-- Encodes a signed 16-bit value in little-endian order.
local function encode_int16_le(value)
  -- Vendor commands store temperatures as signed centi-degrees.
  local normalized = math.floor(value)
  if normalized < 0 then
    normalized = normalized + 0x10000
  end
  return encode_uint16_le(normalized)
end

-- Encodes an unsigned 32-bit value in little-endian order.
local function encode_uint32_le(value)
  -- Vendor commands store duration in seconds across four bytes.
  local normalized = math.floor(value)
  local b1 = normalized % 0x100
  local b2 = math.floor(normalized / 0x100) % 0x100
  local b3 = math.floor(normalized / 0x10000) % 0x100
  local b4 = math.floor(normalized / 0x1000000) % 0x100
  return string.char(b1, b2, b3, b4)
end

-- Decodes an unsigned 16-bit value from a raw little-endian payload offset.
local function decode_uint16_le(raw, offset)
  -- Some private structure reports arrive as raw bytes rather than decoded tables.
  local low_byte, high_byte = raw:byte(offset, offset + 1)
  if low_byte == nil or high_byte == nil then
    return nil
  end
  return low_byte + (high_byte * 0x100)
end

-- Decodes a signed 16-bit value from a raw little-endian payload offset.
local function decode_int16_le(raw, offset)
  -- Threshold payloads store signed centi-degree values in two-byte little-endian form.
  local value = decode_uint16_le(raw, offset)
  if value == nil then
    return nil
  end
  if value >= 0x8000 then
    return value - 0x10000
  end
  return value
end

-- Encodes the relay-output bitmap for relay1 and relay2.
local function encode_relay_output_bitmap(relay1, relay2)
  -- Bit0 is relay1 and bit1 is relay2 in the vendor bitmap.
  return (relay1 % 2) + ((relay2 % 2) * 2)
end

-- Encodes the start/end minute structure used by radar DND and screen night periods.
local function encode_time_period(start_minute, end_minute)
  -- Both vendor attributes use a Uint16 pair in local minutes from midnight.
  return data_types.Structure({
    data_types.Uint16(start_minute),
    data_types.Uint16(end_minute)
  })
end

-- Emits a boolean-style capability event using enabled/disabled states.
local function emit_enabled_disabled_event(device, info, raw_value)
  -- The custom SONOFF boolean capabilities use string states instead of bare booleans.
  local event_value = raw_value and CAPABILITY_STATE_ENABLED or CAPABILITY_STATE_DISABLED
  emit_event_if_supported(device, info.capability, info.capability[info.attribute_name](event_value))
end

-- Emits a scalar capability event after scaling and clamping.
local function emit_numeric_event(device, info, raw_value)
  -- Convert vendor integer storage to the capability's display unit.
  local event_value = raw_value
  if info.scale ~= nil then
    event_value = raw_value / info.scale
  end
  if info.unit ~= nil then
    emit_event_if_supported(device, info.capability, info.capability[info.attribute_name]({ value = event_value, unit = info.unit }))
  else
    emit_event_if_supported(device, info.capability, info.capability[info.attribute_name](event_value))
  end
end

-- Emits an enum-style capability event from the vendor value map.
local function emit_enum_event(device, info, raw_value)
  -- Ignore unknown enum values to avoid poisoning capability state.
  local mapped_value = info.enum_values and info.enum_values[raw_value] or nil
  if mapped_value ~= nil then
    emit_event_if_supported(device, info.capability, info.capability[info.attribute_name](mapped_value))
  end
end

-- Converts a vendor attribute report into the corresponding capability event.
emit_simple_private_attribute = function(device, attribute_id, raw_value)
  -- A single table keeps most private mappings declarative and easy to audit.
  local info = SIMPLE_PRIVATE_ATTRIBUTE_INFO[attribute_id]
  if info == nil or info.capability == nil or info.attribute_name == nil then
    return
  end

  if info.kind == "bool" then
    emit_enabled_disabled_event(device, info, raw_value == true)
  elseif info.kind == "enum" then
    emit_enum_event(device, info, raw_value)
  else
    emit_numeric_event(device, info, raw_value)
  end
end

-- Converts a capability command value into the vendor payload for a simple private attribute.
local function encode_simple_private_capability_value(info, requested_value)
  -- Keep encoding rules centralized so handlers remain trivial.
  if info.kind == "bool" then
    if requested_value == CAPABILITY_STATE_ENABLED then
      return true
    end
    if requested_value == CAPABILITY_STATE_DISABLED then
      return false
    end
    return nil
  end

  if info.kind == "enum" then
    return info.reverse_enum_values and info.reverse_enum_values[requested_value] or nil
  end

  if type(requested_value) ~= "number" then
    return nil
  end

  local numeric_value = requested_value
  if info.min ~= nil then
    numeric_value = math.max(info.min, numeric_value)
  end
  if info.max ~= nil then
    numeric_value = math.min(info.max, numeric_value)
  end
  if info.scale ~= nil then
    numeric_value = utils.round(numeric_value * info.scale)
  else
    numeric_value = utils.round(numeric_value)
  end
  return numeric_value
end

-- Writes a simple private capability value through the shared vendor attribute path.
local function set_simple_private_capability(driver, device, command, attribute_id)
  -- Most SONOFF main-page controls map directly to one FC11 private attribute.
  local info = SIMPLE_PRIVATE_ATTRIBUTE_INFO[attribute_id]
  if info == nil then
    return
  end

  local requested_value = command.args[info.argument_name]
  local encoded_value = encode_simple_private_capability_value(info, requested_value)
  if encoded_value == nil then
    log.warn("Invalid TP-WGZBA capability value for " .. info.argument_name)
    return
  end

  device:send(write_private_attribute(device, attribute_id, info.data_type, encoded_value))
  emit_simple_private_attribute(device, attribute_id, encoded_value)
end

-- Writes the vendor threshold struct after one side of the pair changes.
local function write_temperature_control_threshold_from_capability(device, low_value, high_value)
  -- The device stores both hysteresis values in one structure attribute.
  return write_temperature_control_threshold(device, low_value, high_value)
end

-- Writes the vendor time-period struct after one side of the pair changes.
local function write_time_period_attribute(device, attribute_id, start_minute, end_minute)
  -- The device expects both start and end minutes together in one structure write.
  local normalized_start = normalize_half_hour_minutes(start_minute)
  local normalized_end = normalize_half_hour_minutes(end_minute)
  if normalized_start == nil or normalized_end == nil then
    return false
  end

  device:send(write_private_attribute(
    device,
    attribute_id,
    data_types.Structure,
    encode_time_period(normalized_start, normalized_end)
  ))
  if attribute_id == PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD then
    emit_event_if_supported(device, RadarDndStartMin, RadarDndStartMin.radarDndStartMin({ value = normalized_start, unit = UNIT_MINUTES }))
    emit_event_if_supported(device, RadarDndEndMin, RadarDndEndMin.radarDndEndMin({ value = normalized_end, unit = UNIT_MINUTES }))
  elseif attribute_id == PRIVATE_ATTR_SCREEN_NIGHT_MODE_PERIOD then
    emit_event_if_supported(device, ScreenNightStartMin, ScreenNightStartMin.screenNightStartMin({ value = normalized_start, unit = UNIT_MINUTES }))
    emit_event_if_supported(device, ScreenNightEndMin, ScreenNightEndMin.screenNightEndMin({ value = normalized_end, unit = UNIT_MINUTES }))
  end
  return true
end

-- Converts relay capability values to the vendor bit representation.
local function coerce_relay_output_value(value)
  -- The custom relay capabilities expose open/closed contact names.
  if value == RELAY_OUTPUT_TYPE_NORMALLY_OPEN or value == 0 or value == "0" then
    return 0
  end
  if value == RELAY_OUTPUT_TYPE_NORMALLY_CLOSED or value == 1 or value == "1" then
    return 1
  end
  return nil
end

-- Writes the split relay states back into the vendor bitmap.
local function write_relay_output_type(device, relay1_value, relay2_value)
  -- Both relay bits must be rewritten together because the device stores a bitmap.
  local relay1 = coerce_relay_output_value(relay1_value)
  local relay2 = coerce_relay_output_value(relay2_value)
  if relay1 == nil or relay2 == nil then
    return false
  end

  device:send(write_private_attribute(device, PRIVATE_ATTR_RELAY_OUTPUT_TYPE_BITMAP, data_types.Bitmap8, encode_relay_output_bitmap(relay1, relay2)))
  emit_event_if_supported(
    device,
    RelayOutTypeR1,
    RelayOutTypeR1.relayOneOutputType(relay1 == 1 and RELAY_OUTPUT_TYPE_NORMALLY_CLOSED or RELAY_OUTPUT_TYPE_NORMALLY_OPEN)
  )
  emit_event_if_supported(
    device,
    RelayOutTypeR2,
    RelayOutTypeR2.relayTwoOutputType(relay2 == 1 and RELAY_OUTPUT_TYPE_NORMALLY_CLOSED or RELAY_OUTPUT_TYPE_NORMALLY_OPEN)
  )
  return true
end

-- Decodes the vendor HVAC message payload into a simple open-window state.
local function decode_open_window_state(value)
  -- The private HVAC payload is a short TLV packet where tag 0 reports the window state.
  local raw = get_payload_bytes(value)
  if raw == nil or #raw < 3 then
    return false
  end

  return raw:byte(1) == PRIVATE_HVAC_OPEN_WINDOW_TLV
    and raw:byte(2) == PRIVATE_HVAC_OPEN_WINDOW_TLV_LENGTH
    and raw:byte(3) ~= 0
end

-- Decodes the vendor NTC raw temperature into a single display string.
local function decode_ntc_temperature_display(value)
  -- Any invalid or fault code should collapse to one user-facing disconnected state.
  local raw_value = get_attribute_value(value)
  if raw_value == nil then
    return "Not Connected"
  end
  if raw_value == PRIVATE_NTC_INVALID_CODE then
    return "Not Connected"
  end
  if raw_value == PRIVATE_NTC_OPEN_CIRCUIT_CODE then
    return "Not Connected"
  end
  if raw_value == PRIVATE_NTC_SHORT_CIRCUIT_CODE then
    return "Not Connected"
  end
  if raw_value == PRIVATE_NTC_ADC_INVALID_CODE then
    return "Not Connected"
  end
  if raw_value < PRIVATE_NTC_MIN_VALID then
    return "Not Connected"
  end
  return string.format("%.2f C", raw_value / 100.0)
end

-- Converts the vendor temporary-mode byte to the published override status string.
local function decode_temporary_mode_state(raw_value)
  -- The device reports only none, boost, and timer for this attribute.
  if raw_value == TEMPORARY_MODE_ATTR_BOOST then
    return TEMPORARY_MODE_STATE_BOOST
  end
  if raw_value == TEMPORARY_MODE_ATTR_TIMER then
    return TEMPORARY_MODE_STATE_TIMER
  end
  if raw_value == TEMPORARY_MODE_ATTR_NONE then
    return TEMPORARY_MODE_STATE_NONE
  end
  return nil
end

-- Seeds the override capability defaults when the platform cache is still empty.
local function emit_temporary_mode_defaults_if_needed(device)
  -- These capability values are UI inputs, so they need local defaults before any write happens.
  if device:get_latest_state("main", TemporaryModeStatus.ID, "temporaryTemperatureModeSettings", nil) == nil then
    emit_event_if_supported(device, TemporaryModeStatus, TemporaryModeStatus.temporaryTemperatureModeSettings(TEMPORARY_MODE_STATE_NONE))
  end
  if device:get_latest_state("main", TemporaryModeDuration.ID, "temporaryModeTimeSet", nil) == nil then
    emit_event_if_supported(device, TemporaryModeDuration, TemporaryModeDuration.temporaryModeTimeSet({ value = 30, unit = UNIT_MINUTES }))
  end
  if device:get_latest_state("main", TemporaryModeTemperature.ID, "temporaryModeTempSet", nil) == nil then
    emit_event_if_supported(device, TemporaryModeTemperature, TemporaryModeTemperature.temporaryModeTempSet({ value = 30.0, unit = UNIT_CELSIUS }))
  end
  if device:get_latest_state("main", TemporaryModeAction.ID, "temporaryModeAction", nil) == nil then
    emit_event_if_supported(device, TemporaryModeAction, TemporaryModeAction.temporaryModeAction(TEMPORARY_MODE_ACTION_EXIT))
  end
end

-- Writes both temperature-control thresholds together using the vendor structure payload.
write_temperature_control_threshold = function(device, low_value, high_value)
  -- Attribute 0x601F stores the low/high hysteresis pair atomically in one struct.
  if type(low_value) ~= "number" or type(high_value) ~= "number" then
    return false
  end

  local clamped_low = utils.clamp_value(low_value, PRIVATE_TEMP_CTRL_THRESH_LOW_MIN, PRIVATE_TEMP_CTRL_THRESH_LOW_MAX)
  local clamped_high = utils.clamp_value(high_value, PRIVATE_TEMP_CTRL_THRESH_HIGH_MIN, PRIVATE_TEMP_CTRL_THRESH_HIGH_MAX)
  local threshold_value = data_types.Structure({
    data_types.Int16(utils.round(clamped_low * 100)),
    data_types.Int16(utils.round(clamped_high * 100))
  })

  device:send(write_private_attribute(
    device,
    PRIVATE_ATTR_TEMPERATURE_CONTROL_THRESHOLD,
    data_types.Structure,
    threshold_value
  ))
  emit_event_if_supported(device, TempCtrlThreshLow, TempCtrlThreshLow.tempCtrlThreshLow({ value = clamped_low, unit = UNIT_CELSIUS }))
  emit_event_if_supported(device, TempCtrlThreshHigh, TempCtrlThreshHigh.tempCtrlThreshHigh({ value = clamped_high, unit = UNIT_CELSIUS }))
  return true
end

-- Emits the override status reported by the vendor temporary-mode attribute.
local function private_temporary_mode_settings_handler(driver, device, value, zb_rx)
  -- Ignore unknown states so the app never shows a misleading override mode.
  local event_value = decode_temporary_mode_state(get_attribute_value(value))
  if event_value ~= nil then
    emit_event_if_supported(device, TemporaryModeStatus, TemporaryModeStatus.temporaryTemperatureModeSettings(event_value))
  end
end

-- Emits the read-only open-window state extracted from the private HVAC message payload.
local function private_hvac_message_handler(driver, device, value, zb_rx)
  -- Keep the detection state separate from the writable open-window feature toggle.
  local is_open = decode_open_window_state(value)
  local event_value = is_open and OPEN_WINDOW_STATE_OPEN or OPEN_WINDOW_STATE_CLOSED
  emit_event_if_supported(device, OpenWindowState, OpenWindowState.openWindowState(event_value))
end

-- Emits the read-only NTC display string derived from the private raw temperature attribute.
local function private_ntc_temperature_handler(driver, device, value, zb_rx)
  -- Keep the UI on one field so App layout stays compact and predictable.
  emit_event_if_supported(device, NtcTemperature, NtcTemperature.ntcTemperature(decode_ntc_temperature_display(value)))
end

-- Extracts a Lua number from one member of a Zigbee structure payload.
local function get_structure_member_number(member)
  -- Attribute reports may wrap each structure element in nested typed tables.
  if type(member) == "number" then
    return member
  end
  if type(member) == "table" and member.value ~= nil then
    return get_structure_member_number(member.value)
  end
  if type(member) == "string" then
    local hex_value = member:match("0x([%x]+)")
    if hex_value ~= nil then
      return tonumber(hex_value, 16)
    end
    local decimal_value = member:match("(-?%d+)")
    if decimal_value ~= nil then
      return tonumber(decimal_value)
    end
  end

  local text = tostring(member)
  if type(text) == "string" then
    local hex_value = text:match("0x([%x]+)")
    if hex_value ~= nil then
      return tonumber(hex_value, 16)
    end
    local decimal_value = text:match("(-?%d+)")
    if decimal_value ~= nil then
      return tonumber(decimal_value)
    end
  end
  return nil
end

-- Extracts the first two numeric members from a Zigbee structure payload.
local function get_structure_pair_numbers(value)
  -- SmartThings may surface structure members as indexed fields, nested values, or stringified typed values.
  local candidates = {
    value,
    get_attribute_value(value)
  }

  for _, candidate in ipairs(candidates) do
    if type(candidate) == "table" then
      local first = get_structure_member_number(candidate[1])
      local second = get_structure_member_number(candidate[2])
      if first ~= nil and second ~= nil then
        return first, second
      end

      if type(candidate.value) == "table" then
        first = get_structure_member_number(candidate.value[1])
        second = get_structure_member_number(candidate.value[2])
        if first ~= nil and second ~= nil then
          return first, second
        end
      end
    end
  end

  local text = tostring(value)
  if type(text) == "string" then
    local numbers = {}
    for hex_value in text:gmatch(":%s*0x([%x]+)") do
      table.insert(numbers, tonumber(hex_value, 16))
    end
    if #numbers >= 2 then
      return numbers[1], numbers[2]
    end

    numbers = {}
    for decimal_value in text:gmatch(":%s*(-?%d+)") do
      table.insert(numbers, tonumber(decimal_value))
    end
    if #numbers >= 2 then
      return numbers[1], numbers[2]
    end
  end

  return nil, nil
end

-- Decodes a SONOFF start/end minute structure into two Lua numbers.
local function decode_time_period(value)
  -- Both vendor time-period attributes are reported as a two-member structure.
  return get_structure_pair_numbers(value)
end

-- Builds a generic attr handler for simple private attributes.
local function simple_private_attribute_handler(attribute_id)
  -- Most TP-WGZBA vendor attributes are simple bool/int/enum values.
  return function(driver, device, value, zb_rx)
    emit_simple_private_attribute(device, attribute_id, get_attribute_value(value))
  end
end

-- Emits the split low/high threshold capability values from the vendor structure payload.
local function private_temperature_control_threshold_handler(driver, device, value, zb_rx)
  -- The threshold attribute reports both hysteresis values atomically.
  local low_threshold, high_threshold = get_structure_pair_numbers(value)
  if low_threshold ~= nil and high_threshold ~= nil then
    emit_event_if_supported(device, TempCtrlThreshLow, TempCtrlThreshLow.tempCtrlThreshLow({ value = low_threshold / 100.0, unit = UNIT_CELSIUS }))
    emit_event_if_supported(device, TempCtrlThreshHigh, TempCtrlThreshHigh.tempCtrlThreshHigh({ value = high_threshold / 100.0, unit = UNIT_CELSIUS }))
    return
  end

  local raw = get_payload_bytes(value)
  if raw == nil or #raw < 8 then
    log.warn("Invalid TP-WGZBA temperature control threshold payload")
    return
  end

  local low_threshold = decode_int16_le(raw, 4)
  local high_threshold = decode_int16_le(raw, 7)
  if low_threshold == nil or high_threshold == nil then
    log.warn("Incomplete TP-WGZBA temperature control threshold payload")
    return
  end

  emit_event_if_supported(device, TempCtrlThreshLow, TempCtrlThreshLow.tempCtrlThreshLow({ value = low_threshold / 100.0, unit = UNIT_CELSIUS }))
  emit_event_if_supported(device, TempCtrlThreshHigh, TempCtrlThreshHigh.tempCtrlThreshHigh({ value = high_threshold / 100.0, unit = UNIT_CELSIUS }))
end

-- Emits the split relay output type capability values from the vendor bitmap payload.
local function private_relay_output_type_handler(driver, device, value, zb_rx)
  -- Relay bits 0 and 1 encode heating and boiler contact polarity.
  local raw_value = get_attribute_value(value)
  if type(raw_value) ~= "number" then
    return
  end

  local relay_one = (raw_value % 2) == 1 and RELAY_OUTPUT_TYPE_NORMALLY_CLOSED or RELAY_OUTPUT_TYPE_NORMALLY_OPEN
  local relay_two = (math.floor(raw_value / 2) % 2) == 1 and RELAY_OUTPUT_TYPE_NORMALLY_CLOSED or RELAY_OUTPUT_TYPE_NORMALLY_OPEN
  emit_event_if_supported(device, RelayOutTypeR1, RelayOutTypeR1.relayOneOutputType(relay_one))
  emit_event_if_supported(device, RelayOutTypeR2, RelayOutTypeR2.relayTwoOutputType(relay_two))
end

-- Emits the start/end minute capability values from the vendor time period structure.
local function emit_time_period_events(device, value, start_capability, end_capability, start_attribute_name, end_attribute_name)
  -- Radar DND and screen night mode share the same minute-pair encoding.
  local start_minute, end_minute = decode_time_period(value)
  if start_minute ~= nil and end_minute ~= nil then
    emit_event_if_supported(device, start_capability, start_capability[start_attribute_name]({ value = start_minute, unit = UNIT_MINUTES }))
    emit_event_if_supported(device, end_capability, end_capability[end_attribute_name]({ value = end_minute, unit = UNIT_MINUTES }))
    return
  end

  local raw = get_payload_bytes(value)
  if raw == nil or #raw < 8 then
    log.warn("Invalid TP-WGZBA time period payload")
    return
  end

  start_minute = decode_uint16_le(raw, 4)
  end_minute = decode_uint16_le(raw, 7)
  if start_minute == nil or end_minute == nil then
    log.warn("Incomplete TP-WGZBA time period payload")
    return
  end

  emit_event_if_supported(device, start_capability, start_capability[start_attribute_name]({ value = start_minute, unit = UNIT_MINUTES }))
  emit_event_if_supported(device, end_capability, end_capability[end_attribute_name]({ value = end_minute, unit = UNIT_MINUTES }))
end

-- Stores the decoded radar DND start/end minutes from the vendor structure report.
local function private_radar_do_not_disturb_period_handler(driver, device, value, zb_rx)
  -- Keep the reported minute pair visible directly on the main page capability.
  emit_time_period_events(device, value, RadarDndStartMin, RadarDndEndMin, "radarDndStartMin", "radarDndEndMin")
end

-- Stores the decoded screen night start/end minutes from the vendor structure report.
local function private_screen_night_mode_period_handler(driver, device, value, zb_rx)
  -- Keep the reported minute pair visible directly on the main page capability.
  emit_time_period_events(device, value, ScreenNightStartMin, ScreenNightEndMin, "screenNightStartMin", "screenNightEndMin")
end

-- Refreshes all standard and selected private attributes used by the first version.
local function do_refresh(self, device)
  -- Keep refresh bounded to validated attributes so troubleshooting stays manageable.
  device:send(Thermostat.attributes.LocalTemperature:read(device))
  device:send(Thermostat.attributes.OccupiedHeatingSetpoint:read(device))
  device:send(Thermostat.attributes.SystemMode:read(device))
  device:send(Thermostat.attributes.ThermostatRunningState:read(device))
  device:send(Thermostat.attributes.LocalTemperatureCalibration:read(device))
  device:send(Basic.attributes.SWBuildID:read(device))
  for _, attribute_id in ipairs(PRIVATE_REFRESH_ATTRIBUTES) do
    device:send(read_private_attribute(device, attribute_id))
  end
end

-- Publishes the device-provided Basic Cluster software build identifier as its firmware version.
local function software_build_id_handler(driver, device, value, zb_rx)
  -- Ignore malformed reports because the capability requires a non-empty string.
  if type(value.value) ~= "string" or value.value == "" then
    log.warn("Invalid TP-WGZBA Basic SWBuildID payload")
    return
  end

  emit_event_if_supported(device, FirmwareUpdate, FirmwareUpdate.currentVersion({ value = value.value }))
end

-- Configures standard thermostat reporting only.
local function do_configure(self, device)
  -- Keep the standard bind but do not configure automatic reporting.
  device:send(device_management.build_bind_request(device, Thermostat.ID, self.environment_info.hub_zigbee_eui))
end

-- Handles initial device join state.
local function device_added(self, device)
  -- Seed capability defaults before the first vendor refresh arrives.
  emit_supported_modes(device)
  emit_main_page_defaults_if_needed(device)
  emit_temporary_mode_defaults_if_needed(device)
  do_refresh(self, device)
end

-- Handles driver switch the same way as first add.
local function device_driver_switched(self, device)
  -- Driver replacement should refresh state from the device again.
  emit_supported_modes(device)
  emit_main_page_defaults_if_needed(device)
  emit_temporary_mode_defaults_if_needed(device)
  do_refresh(self, device)
end

-- Restores volatile UI state on driver init.
local function device_init(self, device)
  -- Override inputs are UI-cached values and still need local defaults before the first interaction.
  emit_main_page_defaults_if_needed(device)
  emit_temporary_mode_defaults_if_needed(device)
end

-- Writes the standard thermostat system mode and schedules a readback.
local function set_thermostat_mode(driver, device, command)
  -- Write the Zigbee mode directly instead of remapping app semantics.
  local mode = THERMOSTAT_MODE_MAP[command.args.mode]
  if mode == nil then
    return
  end

  device:send_to_component(command.component, Thermostat.attributes.SystemMode:write(device, mode))
end

-- Creates dedicated thermostat-mode command handlers.
local function thermostat_mode_setter(mode_name)
  -- Reuse the common setter so all mode commands share one write path.
  return function(driver, device, command)
    set_thermostat_mode(driver, device, { component = command.component, args = { mode = mode_name } })
  end
end

-- Writes the standard heating setpoint and schedules a readback.
local function set_heating_setpoint(driver, device, command)
  -- Keep the first version on the standard setpoint attribute only.
  local value = command.args.setpoint
  if value >= 40 then
    value = utils.f_to_c(value)
  end

  value = utils.clamp_value(value, 5.0, 30.0)
  device:send_to_component(command.component, Thermostat.attributes.OccupiedHeatingSetpoint:write(device, utils.round(value * 100)))
end

-- Sends the vendor temporary mode command built from the current UI-side override values.
local function send_temporary_mode_command(device, action_value)
  -- Exit carries only the action byte, while boost and timer include duration and target temperature.
  local duration_minutes = utils.clamp_value(
    utils.round(get_latest_numeric_state(device, TemporaryModeDuration, "temporaryModeTimeSet", 30)),
    1,
    1439
  )

  if action_value == TEMPORARY_MODE_EXIT then
    device:send(send_private_cluster_command(device, TEMPORARY_MODE_COMMAND_ID, string.char(action_value)))
    return
  end

  local target_temperature = 30.0
  if action_value == TEMPORARY_MODE_TIMER then
    target_temperature = utils.clamp_value(
      get_latest_numeric_state(device, TemporaryModeTemperature, "temporaryModeTempSet", 30.0),
      5.0,
      30.0
    )
  elseif action_value ~= TEMPORARY_MODE_BOOST then
    log.warn("Invalid TP-WGZBA temporary mode action value")
    return
  end

  local payload = string.char(action_value)
    .. encode_uint32_le(duration_minutes * 60)
    .. encode_int16_le(utils.round(target_temperature * 100))
  device:send(send_private_cluster_command(device, TEMPORARY_MODE_COMMAND_ID, payload))
end

-- Updates the locally cached override duration without writing a vendor attribute.
local function set_temporary_mode_duration(driver, device, command)
  -- The duration is only consumed when the user later sends boost or timer.
  local requested_value = coerce_numeric_value(command.args.temporaryModeTimeSet)
  if requested_value == nil then
    log.warn("Invalid TP-WGZBA temporary mode duration value")
    return
  end

  requested_value = utils.clamp_value(utils.round(requested_value), 1, 1439)
  emit_event_if_supported(device, TemporaryModeDuration, TemporaryModeDuration.temporaryModeTimeSet({ value = requested_value, unit = UNIT_MINUTES }))
end

-- Updates the locally cached override target temperature without writing a vendor attribute.
local function set_temporary_mode_temperature(driver, device, command)
  -- Timer mode uses this cached value, while boost always forces 30C on-device.
  local requested_value = coerce_numeric_value(command.args.temporaryModeTempSet)
  if requested_value == nil then
    log.warn("Invalid TP-WGZBA temporary mode temperature value")
    return
  end

  requested_value = utils.clamp_value(requested_value, 5.0, 30.0)
  emit_event_if_supported(device, TemporaryModeTemperature, TemporaryModeTemperature.temporaryModeTempSet({ value = requested_value, unit = UNIT_CELSIUS }))
end

-- Sends the selected override action and then refreshes the reported vendor status.
local function set_temporary_mode_action(driver, device, command)
  -- Only exit, boost, and timer are supported by the published override action capability.
  local requested_value = command.args.temporaryModeAction
  if requested_value == TEMPORARY_MODE_ACTION_EXIT then
    send_temporary_mode_command(device, TEMPORARY_MODE_EXIT)
  elseif requested_value == TEMPORARY_MODE_ACTION_BOOST then
    send_temporary_mode_command(device, TEMPORARY_MODE_BOOST)
    emit_event_if_supported(device, TemporaryModeTemperature, TemporaryModeTemperature.temporaryModeTempSet({ value = 30.0, unit = UNIT_CELSIUS }))
  elseif requested_value == TEMPORARY_MODE_ACTION_TIMER then
    send_temporary_mode_command(device, TEMPORARY_MODE_TIMER)
  else
    log.warn("Invalid TP-WGZBA temporary mode action capability value")
    return
  end

  emit_event_if_supported(device, TemporaryModeAction, TemporaryModeAction.temporaryModeAction(requested_value))
end

-- Writes the vendor threshold struct after changing the low capability value.
local function set_temp_ctrl_thresh_low(driver, device, command)
  -- The current high threshold must be preserved because the vendor attribute is atomic.
  local low_value = coerce_numeric_value(command.args.tempCtrlThreshLow)
  local high_value = get_latest_numeric_state(device, TempCtrlThreshHigh, "tempCtrlThreshHigh", PRIVATE_TEMP_CTRL_THRESH_HIGH_DEFAULT)
  if low_value == nil or not write_temperature_control_threshold_from_capability(device, low_value, high_value) then
    log.warn("Invalid TP-WGZBA low threshold capability value")
  end
end

-- Writes the vendor threshold struct after changing the high capability value.
local function set_temp_ctrl_thresh_high(driver, device, command)
  -- The current low threshold must be preserved because the vendor attribute is atomic.
  local low_value = get_latest_numeric_state(device, TempCtrlThreshLow, "tempCtrlThreshLow", PRIVATE_TEMP_CTRL_THRESH_LOW_DEFAULT)
  local high_value = coerce_numeric_value(command.args.tempCtrlThreshHigh)
  if high_value == nil or not write_temperature_control_threshold_from_capability(device, low_value, high_value) then
    log.warn("Invalid TP-WGZBA high threshold capability value")
  end
end

-- Writes the radar DND struct after changing the start minute capability.
local function set_radar_dnd_start_min(driver, device, command)
  -- The end minute must be preserved because both values share one structure write.
  local start_minute = coerce_numeric_value(command.args.radarDndStartMin)
  local end_minute = get_latest_numeric_state(device, RadarDndEndMin, "radarDndEndMin", 0)
  if start_minute == nil or not write_time_period_attribute(device, PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD, start_minute, end_minute) then
    log.warn("Invalid TP-WGZBA radar DND start minute capability value")
  end
end

-- Writes the radar DND struct after changing the end minute capability.
local function set_radar_dnd_end_min(driver, device, command)
  -- The start minute must be preserved because both values share one structure write.
  local start_minute = get_latest_numeric_state(device, RadarDndStartMin, "radarDndStartMin", 0)
  local end_minute = coerce_numeric_value(command.args.radarDndEndMin)
  if end_minute == nil or not write_time_period_attribute(device, PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD, start_minute, end_minute) then
    log.warn("Invalid TP-WGZBA radar DND end minute capability value")
  end
end

-- Writes the screen night struct after changing the start minute capability.
local function set_screen_night_start_min(driver, device, command)
  -- The end minute must be preserved because both values share one structure write.
  local start_minute = coerce_numeric_value(command.args.screenNightStartMin)
  local end_minute = get_latest_numeric_state(device, ScreenNightEndMin, "screenNightEndMin", 0)
  if start_minute == nil or not write_time_period_attribute(device, PRIVATE_ATTR_SCREEN_NIGHT_MODE_PERIOD, start_minute, end_minute) then
    log.warn("Invalid TP-WGZBA screen night start minute capability value")
  end
end

-- Writes the screen night struct after changing the end minute capability.
local function set_screen_night_end_min(driver, device, command)
  -- The start minute must be preserved because both values share one structure write.
  local start_minute = get_latest_numeric_state(device, ScreenNightStartMin, "screenNightStartMin", 0)
  local end_minute = coerce_numeric_value(command.args.screenNightEndMin)
  if end_minute == nil or not write_time_period_attribute(device, PRIVATE_ATTR_SCREEN_NIGHT_MODE_PERIOD, start_minute, end_minute) then
    log.warn("Invalid TP-WGZBA screen night end minute capability value")
  end
end

-- Converts thermostat running-state bitmaps into the standard operating-state capability.
local function thermostat_running_state_handler(driver, device, value, zb_rx)
  -- Use the device-reported state directly instead of inferring from temperatures.
  if value:is_heat_second_stage_on_set() or value:is_heat_on_set() then
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.heating())
  else
    device:emit_event(ThermostatOperatingState.thermostatOperatingState.idle())
  end
end

-- Emits the standard calibration report through the main-page temperature compensation capability.
local function local_temperature_calibration_handler(driver, device, value, zb_rx)
  -- LocalTemperatureCalibration is stored in 0.1 C units by the thermostat cluster.
  local raw_value = get_attribute_value(value)
  local calibration = coerce_numeric_value(raw_value)
  if calibration == nil then
    log.warn("Invalid TP-WGZBA local temperature calibration attribute value")
    return
  end

  calibration = utils.clamp_value(calibration / 10.0, -10.0, 10.0)
  emit_event_if_supported(device, TemperatureCompensation, TemperatureCompensation.temperatureCompensation({ value = calibration, unit = UNIT_CELSIUS }))
end

-- Writes main-page temperature compensation to standard local-temperature calibration.
local function set_temperature_compensation(driver, device, command)
  -- The app sends Celsius, while Zigbee LocalTemperatureCalibration uses 0.1 C units.
  local calibration = coerce_numeric_value(command.args.temperatureCompensation)
  if calibration == nil then
    log.warn("Invalid TP-WGZBA temperature compensation capability value")
    return
  end

  calibration = utils.clamp_value(calibration, -10.0, 10.0)
  device:send_to_component(command.component, Thermostat.attributes.LocalTemperatureCalibration:write(device, utils.round(calibration * 10)))
  emit_event_if_supported(device, TemperatureCompensation, TemperatureCompensation.temperatureCompensation({ value = calibration, unit = UNIT_CELSIUS }))
end

local sonoff_thermostat = {
  NAME = "SONOFF TP-WGZBA Handler",
  zigbee_handlers = {
    attr = {
      [Basic.ID] = {
        [Basic.attributes.SWBuildID.ID] = software_build_id_handler
      },
      [Thermostat.ID] = {
        [Thermostat.attributes.ThermostatRunningState.ID] = thermostat_running_state_handler,
        [Thermostat.attributes.LocalTemperatureCalibration.ID] = local_temperature_calibration_handler
      },
      [SONOFF_PRIVATE_CLUSTER] = {
        [PRIVATE_ATTR_CHILD_LOCK] = simple_private_attribute_handler(PRIVATE_ATTR_CHILD_LOCK),
        [PRIVATE_ATTR_BT_PAIRING_BROADCAST_REQ] = simple_private_attribute_handler(PRIVATE_ATTR_BT_PAIRING_BROADCAST_REQ),
        [PRIVATE_ATTR_OPEN_WINDOW_DETECTION] = simple_private_attribute_handler(PRIVATE_ATTR_OPEN_WINDOW_DETECTION),
        [PRIVATE_ATTR_FROST_PROOF_TEMPERATURE] = simple_private_attribute_handler(PRIVATE_ATTR_FROST_PROOF_TEMPERATURE),
        [PRIVATE_ATTR_TEMPORARY_MODE_SETTINGS] = private_temporary_mode_settings_handler,
        [PRIVATE_ATTR_TEMPERATURE_CONTROL_THRESHOLD] = private_temperature_control_threshold_handler,
        [PRIVATE_ATTR_RADAR_SENSITIVITY_LEVEL] = simple_private_attribute_handler(PRIVATE_ATTR_RADAR_SENSITIVITY_LEVEL),
        [PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_ENABLE] = simple_private_attribute_handler(PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_ENABLE),
        [PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_PERIOD] = private_radar_do_not_disturb_period_handler,
        [PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS] = simple_private_attribute_handler(PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS),
        [PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS] = simple_private_attribute_handler(PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS),
        [PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS] = simple_private_attribute_handler(PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS),
        [PRIVATE_ATTR_SCREEN_NIGHT_MODE_ENABLE] = simple_private_attribute_handler(PRIVATE_ATTR_SCREEN_NIGHT_MODE_ENABLE),
        [PRIVATE_ATTR_SCREEN_NIGHT_MODE_PERIOD] = private_screen_night_mode_period_handler,
        [PRIVATE_ATTR_RELAY_OUTPUT_TYPE_BITMAP] = private_relay_output_type_handler,
        [PRIVATE_ATTR_HVAC_MESSAGE_NOTIFICATION] = private_hvac_message_handler,
        [PRIVATE_ATTR_CURRENT_NTC_TEMPERATURE_RAW] = private_ntc_temperature_handler,
        [PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE] = simple_private_attribute_handler(PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE),
        [PRIVATE_ATTR_OVERHEAT_PROTECTION_ENABLE] = simple_private_attribute_handler(PRIVATE_ATTR_OVERHEAT_PROTECTION_ENABLE),
        [PRIVATE_ATTR_RADAR_ENABLE] = simple_private_attribute_handler(PRIVATE_ATTR_RADAR_ENABLE)
      }
    }
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [ThermostatMode.ID] = {
      [ThermostatMode.commands.setThermostatMode.NAME] = set_thermostat_mode,
      [ThermostatMode.commands.auto.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.auto.NAME),
      [ThermostatMode.commands.off.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.off.NAME),
      [ThermostatMode.commands.heat.NAME] = thermostat_mode_setter(ThermostatMode.thermostatMode.heat.NAME)
    },
    [ThermostatHeatingSetpoint.ID] = {
      [ThermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = set_heating_setpoint
    },
    [TemperatureCompensation.ID] = {
      ["setTemperatureCompensation"] = set_temperature_compensation
    },
    [ChildLock.ID] = {
      [ChildLock.commands.setChildLockState.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_CHILD_LOCK)
      end
    },
    [OpenWindowDetection.ID] = {
      [OpenWindowDetection.commands.setOpenWindowDetection.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_OPEN_WINDOW_DETECTION)
      end
    },
    [BtPairingBroadcastReq.ID] = {
      [BtPairingBroadcastReq.commands.setBtPairingBroadcastReq.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_BT_PAIRING_BROADCAST_REQ)
      end
    },
    [FrostProofTemperature.ID] = {
      [FrostProofTemperature.commands.setFrostProofTemperature.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_FROST_PROOF_TEMPERATURE)
      end
    },
    [TemporaryModeDuration.ID] = {
      [TemporaryModeDuration.commands.setTemporaryModeTimeSet.NAME] = set_temporary_mode_duration
    },
    [TemporaryModeTemperature.ID] = {
      [TemporaryModeTemperature.commands.setTemporaryModeTempSet.NAME] = set_temporary_mode_temperature
    },
    [TemporaryModeAction.ID] = {
      [TemporaryModeAction.commands.setTemporaryModeAction.NAME] = set_temporary_mode_action
    },
    [RadarSensitivityLevel.ID] = {
      [RadarSensitivityLevel.commands.setRadarSensitivityLevel.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_RADAR_SENSITIVITY_LEVEL)
      end
    },
    [RadarDoNotDisturbEnable.ID] = {
      [RadarDoNotDisturbEnable.commands.setRadarDoNotDisturbEnable.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_RADAR_DO_NOT_DISTURB_ENABLE)
      end
    },
    [RadarDndStartMin.ID] = {
      [RadarDndStartMin.commands.setRadarDndStartMin.NAME] = set_radar_dnd_start_min
    },
    [RadarDndEndMin.ID] = {
      [RadarDndEndMin.commands.setRadarDndEndMin.NAME] = set_radar_dnd_end_min
    },
    [ScreenWorkingBrightness.ID] = {
      [ScreenWorkingBrightness.commands.setScreenWorkingBrightness.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_SCREEN_WORKING_BRIGHTNESS)
      end
    },
    [ScreenStandbyBrightness.ID] = {
      [ScreenStandbyBrightness.commands.setScreenStandbyBrightness.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_SCREEN_STANDBY_BRIGHTNESS)
      end
    },
    [ScreenNightStandbyBrightness.ID] = {
      [ScreenNightStandbyBrightness.commands.setScreenNightStandbyBrightness.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_SCREEN_NIGHT_STANDBY_BRIGHTNESS)
      end
    },
    [ScreenNightModeEnable.ID] = {
      [ScreenNightModeEnable.commands.setScreenNightModeEnable.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_SCREEN_NIGHT_MODE_ENABLE)
      end
    },
    [ScreenNightStartMin.ID] = {
      [ScreenNightStartMin.commands.setScreenNightStartMin.NAME] = set_screen_night_start_min
    },
    [ScreenNightEndMin.ID] = {
      [ScreenNightEndMin.commands.setScreenNightEndMin.NAME] = set_screen_night_end_min
    },
    [RelayOutTypeR1.ID] = {
      [RelayOutTypeR1.commands.setRelayOneOutputType.NAME] = function(driver, device, command)
        local relay1_value = command.args.relayOneOutputType
        local relay2_value = device:get_latest_state("main", RelayOutTypeR2.ID, "relayTwoOutputType", RELAY_OUTPUT_TYPE_NORMALLY_OPEN)
        if not write_relay_output_type(device, relay1_value, relay2_value) then
          log.warn("Invalid TP-WGZBA relay 1 output type capability value")
        end
      end
    },
    [RelayOutTypeR2.ID] = {
      [RelayOutTypeR2.commands.setRelayTwoOutputType.NAME] = function(driver, device, command)
        local relay1_value = device:get_latest_state("main", RelayOutTypeR1.ID, "relayOneOutputType", RELAY_OUTPUT_TYPE_NORMALLY_OPEN)
        local relay2_value = command.args.relayTwoOutputType
        if not write_relay_output_type(device, relay1_value, relay2_value) then
          log.warn("Invalid TP-WGZBA relay 2 output type capability value")
        end
      end
    },
    [TempCtrlThreshLow.ID] = {
      [TempCtrlThreshLow.commands.setTempCtrlThreshLow.NAME] = set_temp_ctrl_thresh_low
    },
    [TempCtrlThreshHigh.ID] = {
      [TempCtrlThreshHigh.commands.setTempCtrlThreshHigh.NAME] = set_temp_ctrl_thresh_high
    },
    [OverheatProtectionTemperature.ID] = {
      [OverheatProtectionTemperature.commands.setOverheatProtectionTemperature.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_OVERHEAT_PROTECTION_TEMPERATURE)
      end
    },
    [OverheatProtectionEnable.ID] = {
      [OverheatProtectionEnable.commands.setOverheatProtectionEnable.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_OVERHEAT_PROTECTION_ENABLE)
      end
    },
    [RadarEnable.ID] = {
      [RadarEnable.commands.setRadarEnable.NAME] = function(driver, device, command)
        set_simple_private_capability(driver, device, command, PRIVATE_ATTR_RADAR_ENABLE)
      end
    }
  },
  lifecycle_handlers = {
    added = device_added,
    init = device_init,
    driverSwitched = device_driver_switched,
    doConfigure = do_configure
  },
  can_handle = require("sonoff.tp_wgzba.can_handle")
}

return sonoff_thermostat
