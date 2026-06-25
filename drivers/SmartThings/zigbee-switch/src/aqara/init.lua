-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local constants = require "st.zigbee.constants"
local SinglePrecisionFloat = require "st.zigbee.data_types".SinglePrecisionFloat

local OnOff = clusters.OnOff
local ElectricalMeasurement = clusters.ElectricalMeasurement
local SimpleMetering = clusters.SimpleMetering
local Groups = clusters.Groups

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F
local WIRELESS_SWITCH_CLUSTER_ID = 0x0012
local WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0055
local RESTORE_POWER_STATE_ATTRIBUTE_ID = 0x0201
local CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID = 0x0200
local RESTORE_TURN_OFF_INDICATOR_LIGHT_ATTRIBUTE_ID = 0x0203
local MAX_POWER_ATTRIBUTE_ID = 0x020B
local ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID = 0x000A
-- Aqara private cluster (0xFCC0) attributes used by the Dual Relay Module T2 (lumi.switch.acn047)
local DEVICE_MODE_ATTRIBUTE_ID = 0x0289      -- relay working mode (wet/dry contact, pulse), Uint8 0..3
local INTERLOCK_ATTRIBUTE_ID = 0x02D0        -- interlock between the two relays, Boolean
local POWER_OFF_MEMORY_ATTRIBUTE_ID = 0x0517 -- power-off memory behavior, Uint8 (see powerOffMemory value_map)
local PULSE_INTERVAL_ATTRIBUTE_ID = 0x00EB   -- pulse width in ms when running in pulse mode, Uint16
local LAST_REPORT_TIME = "LAST_REPORT_TIME"
local PRIVATE_MODE = "PRIVATE_MODE"
-- "interlock" / "devicemode" are extra profile components on aqara-dual-relay-module-unified.yml.
-- The order of the SUPPORTED_* lists matches the raw device values (0-based), see the handlers below.
local COMPONENT_INTERLOCK = "interlock"
local SUPPORTED_INTERLOCK = { "normal", "interlock" }
local COMPONENT_DEVICE_MODE = "devicemode"
-- Relay working modes mapped to their raw device values. dry_contact_open_pulse_mode (raw 2) is
-- intentionally not exposed; the remaining modes keep their original device values (on_off stays 3).
local DEVICE_MODE_TO_VALUE = {
  wet_contact_mode = 0,
  dry_contact_closed_pulse_mode = 1,
  dry_contact_on_off_mode = 3,
}
local DEVICE_MODE_FROM_VALUE = {
  [0] = "wet_contact_mode",
  [1] = "dry_contact_closed_pulse_mode",
  [3] = "dry_contact_on_off_mode",
}

local preference_map = {
  ["stse.restorePowerState"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = RESTORE_POWER_STATE_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Boolean,
  },
  ["stse.changeToWirelessSwitch"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = CHANGE_TO_WIRELESS_SWITCH_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { [true] = 0x00, [false] = 0x01 },
  },
  ["stse.maxPower"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = MAX_POWER_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.SinglePrecisionFloat,
    value_map = {
      ["1"] = SinglePrecisionFloat(0, 6, 0.5625),
      ["2"] = SinglePrecisionFloat(0, 7, 0.5625),
      ["3"] = SinglePrecisionFloat(0, 8, 0.171875),
      ["4"] = SinglePrecisionFloat(0, 8, 0.5625),
      ["5"] = SinglePrecisionFloat(0, 8, 0.953125),
      ["6"] = SinglePrecisionFloat(0, 9, 0.171875),
      ["7"] = SinglePrecisionFloat(0, 9, 0.3671875),
      ["8"] = SinglePrecisionFloat(0, 9, 0.5625),
      ["9"] = SinglePrecisionFloat(0, 9, 0.7578125),
      ["10"] = SinglePrecisionFloat(0, 9, 0.953125),
      ["11"] = SinglePrecisionFloat(0, 10, 0.07421875),
      ["12"] = SinglePrecisionFloat(0, 10, 0.171875),
      ["13"] = SinglePrecisionFloat(0, 10, 0.26953125),
      ["14"] = SinglePrecisionFloat(0, 10, 0.3671875),
      ["15"] = SinglePrecisionFloat(0, 10, 0.46484375),
      ["16"] = SinglePrecisionFloat(0, 10, 0.5625),
      ["17"] = SinglePrecisionFloat(0, 10, 0.66015625),
      ["18"] = SinglePrecisionFloat(0, 10, 0.7578125),
      ["19"] = SinglePrecisionFloat(0, 10, 0.85546875),
      ["20"] = SinglePrecisionFloat(0, 10, 0.953125),
      ["21"] = SinglePrecisionFloat(0, 11, 0.025390625),
      ["22"] = SinglePrecisionFloat(0, 11, 0.07421875),
      ["23"] = SinglePrecisionFloat(0, 11, 0.123046875)
    },
  },
  ["stse.maxPowerCN"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = MAX_POWER_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.SinglePrecisionFloat,
    value_map = {
      ["1"] = SinglePrecisionFloat(0, 6, 0.5625),
      ["2"] = SinglePrecisionFloat(0, 7, 0.5625),
      ["3"] = SinglePrecisionFloat(0, 8, 0.171875),
      ["4"] = SinglePrecisionFloat(0, 8, 0.5625),
      ["5"] = SinglePrecisionFloat(0, 8, 0.953125),
      ["6"] = SinglePrecisionFloat(0, 9, 0.171875),
      ["7"] = SinglePrecisionFloat(0, 9, 0.3671875),
      ["8"] = SinglePrecisionFloat(0, 9, 0.5625),
      ["9"] = SinglePrecisionFloat(0, 9, 0.7578125),
      ["10"] = SinglePrecisionFloat(0, 9, 0.953125),
      ["11"] = SinglePrecisionFloat(0, 10, 0.07421875),
      ["12"] = SinglePrecisionFloat(0, 10, 0.171875),
      ["13"] = SinglePrecisionFloat(0, 10, 0.26953125),
      ["14"] = SinglePrecisionFloat(0, 10, 0.3671875),
      ["15"] = SinglePrecisionFloat(0, 10, 0.46484375),
      ["16"] = SinglePrecisionFloat(0, 10, 0.5625),
      ["17"] = SinglePrecisionFloat(0, 10, 0.66015625),
      ["18"] = SinglePrecisionFloat(0, 10, 0.7578125),
      ["19"] = SinglePrecisionFloat(0, 10, 0.85546875),
      ["20"] = SinglePrecisionFloat(0, 10, 0.953125),
      ["21"] = SinglePrecisionFloat(0, 11, 0.025390625),
      ["22"] = SinglePrecisionFloat(0, 11, 0.07421875),
      ["23"] = SinglePrecisionFloat(0, 11, 0.123046875),
      ["24"] = SinglePrecisionFloat(0, 11, 0.171875),
      ["25"] = SinglePrecisionFloat(0, 11, 0.220703125)
    },
  },
  ["stse.electricSwitchType"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { rocker = 0x01, rebound = 0x02 },
  },
  -- External switch wiring type (same attribute as stse.electricSwitchType, with an extra "disabled"
  -- option): rocker = maintained, rebound/button = momentary, disabled = external switch ignored.
  ["switchType"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = ELECTRIC_SWITCH_TYPE_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { rocker = 0x01, rebound = 0x02, disabled = 0x00 },
  },
  ["stse.turnOffIndicatorLight"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = RESTORE_TURN_OFF_INDICATOR_LIGHT_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Boolean,
  },
  ["powerOffMemory"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = POWER_OFF_MEMORY_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint8,
    value_map = { restore = 0x01, poweron = 0x00, poweroff = 0x02, reverse = 0x03 },
  },
  ["pulseInterval"] = {
    cluster_id = PRIVATE_CLUSTER_ID,
    attribute_id = PULSE_INTERVAL_ATTRIBUTE_ID,
    mfg_code = MFG_CODE,
    data_type = data_types.Uint16,
    value_type = { "number" }, -- presence flag: coerce the preference value with tonumber() before writing
  }
}

-- Handles reports of the private-mode attribute. Caches the current private-mode state and, when the
-- device is not yet in private mode, forces it into private mode and configures energy reporting.
-- acn047 is excluded from being forced into private mode (it stays on standard clusters).
local function private_mode_handler(driver, device, value, zb_rx)
  device:set_field(PRIVATE_MODE, value.value, { persist = true })

  if value.value ~= 1 then
    if device:get_model() ~= "lumi.switch.acn047" then
      device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, 0x01)) -- private
    end
    device:send(SimpleMetering.attributes.CurrentSummationDelivered:configure_reporting(device, 900, 3600, 1)) -- minimal interval : 15min
    device:set_field(constants.ELECTRICAL_MEASUREMENT_DIVISOR_KEY, 10, { persist = true })
    device:set_field(constants.SIMPLE_METERING_DIVISOR_KEY, 1000, { persist = true })
  end
end
-- Reflect the device's interlock state onto the "interlock" component.
-- value.value is a Boolean; +1 converts the 0/1 state into a Lua (1-based) list index.
local function interlock_switch_handler(driver, device, value, zb_rx)
  local component = device.profile.components[COMPONENT_INTERLOCK]
  if component == nil then return end
  local cur_state = 0
  if value.value then cur_state = 1 end
  device:emit_component_event(component, capabilities.mode.mode(SUPPORTED_INTERLOCK[cur_state + 1]))
end
-- Reflect the relay working mode onto the "devicemode" component.
-- value.value is the raw device value; only emit for modes we expose (open_pulse is ignored).
local function device_mode_handler(driver, device, value, zb_rx)
  local component = device.profile.components[COMPONENT_DEVICE_MODE]
  if component == nil then return end
  local mode = DEVICE_MODE_FROM_VALUE[value.value]
  if mode ~= nil then
    device:emit_component_event(component, capabilities.mode.mode(mode))
  end
end

local function wireless_switch_handler(driver, device, value, zb_rx)
  if value.value == 1 then
    device:emit_event_for_endpoint(zb_rx.address_header.src_endpoint.value,
      capabilities.button.button.pushed({ state_change = true }))
  end
end

local function energy_meter_power_consumption_report(driver, device, value, zb_rx)
  -- ignore unexpected event when the device is private mode
  local private_mode = device:get_field(PRIVATE_MODE) or 0
  if private_mode == 1 then return end

  local raw_value = value.value
  -- energy meter
  local offset = device:get_field(constants.ENERGY_METER_OFFSET) or 0
  if raw_value < offset then
    --- somehow our value has gone below the offset, so we'll reset the offset, since the device seems to have
    offset = 0
    device:set_field(constants.ENERGY_METER_OFFSET, offset, { persist = true })
  end
  device:emit_event(capabilities.energyMeter.energy({ value = raw_value - offset, unit = "Wh" }))

  -- report interval
  local current_time = os.time()
  local last_time = device:get_field(LAST_REPORT_TIME) or 0
  local next_time = last_time + 60 * 15 -- 15 mins, the minimum interval allowed between reports
  if current_time < next_time then
    return
  end
  device:set_field(LAST_REPORT_TIME, current_time, { persist = true })

  -- power consumption report
  local delta_energy = 0.0
  local current_power_consumption = device:get_latest_state("main", capabilities.powerConsumptionReport.ID, capabilities.powerConsumptionReport.powerConsumption.NAME)
  if current_power_consumption ~= nil then
    delta_energy = math.max(raw_value - current_power_consumption.energy, 0.0)
  end
  device:emit_event(capabilities.powerConsumptionReport.powerConsumption({ energy = raw_value, deltaEnergy = delta_energy })) -- the unit of these values should be 'Wh'
end

local function power_meter_handler(driver, device, value, zb_rx)
  -- ignore unexpected event when the device is private mode
  local private_mode = device:get_field(PRIVATE_MODE) or 0
  if private_mode == 1 then return end

  local raw_value = value.value -- '10W'
  raw_value = raw_value / 10
  device:emit_event(capabilities.powerMeter.power({ value = raw_value, unit = "W" }))
end

-- setMode command handler shared by the "interlock" and "devicemode" components.
-- The target component is used to decide which private-cluster attribute to write.
local function mode_handler(driver, device, command)
  if command.component == COMPONENT_INTERLOCK then
    -- interlock attribute is a Boolean: true = relays interlocked, false = independent
    local interlock_mode = false
    if command.args.mode == SUPPORTED_INTERLOCK[2] then interlock_mode = true end
    device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, INTERLOCK_ATTRIBUTE_ID, MFG_CODE, data_types.Boolean, interlock_mode))
  elseif command.component == COMPONENT_DEVICE_MODE then
    -- map the selected mode string to its raw device value
    local device_mode = DEVICE_MODE_TO_VALUE[command.args.mode]
    if device_mode ~= nil then
      device:send(cluster_base.write_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, DEVICE_MODE_ATTRIBUTE_ID, MFG_CODE, data_types.Uint8, device_mode))
    end
  end
end
-- Read back switch state, power/energy (standard clusters) and, when present, the interlock and
-- device-mode private attributes.
local function do_refresh(self, device)
  device:send(OnOff.attributes.OnOff:read(device))
  if (device:supports_capability_by_id(capabilities.powerMeter.ID)) then
    device:send(ElectricalMeasurement.attributes.ActivePower:read(device))
    device:send(SimpleMetering.attributes.CurrentSummationDelivered:read(device))
  end
  if device.profile.components[COMPONENT_INTERLOCK] then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, INTERLOCK_ATTRIBUTE_ID, MFG_CODE))
  end
  if device.profile.components[COMPONENT_DEVICE_MODE] then
    device:send(cluster_base.read_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, DEVICE_MODE_ATTRIBUTE_ID, MFG_CODE))
  end
end

-- On preference change, write any preference whose value changed to its mapped private-cluster
-- attribute (see preference_map). value_map translates enum strings; value_type coerces numbers.
local function device_info_changed(driver, device, event, args)
  local preferences = device.preferences
  local old_preferences = args.old_st_store.preferences
  if preferences ~= nil then
    for id, attr in pairs(preference_map) do
      local old_value = old_preferences[id]
      local value = preferences[id]
      if value ~= nil and value ~= old_value then
        if attr.value_map ~= nil then
          value = attr.value_map[value]
        end
        -- numeric preferences (e.g. pulseInterval) are coerced to a Lua number before being written
        if attr.value_type ~= nil then
          value = tonumber(value)
        end
        device:send(cluster_base.write_manufacturer_specific_attribute(device, attr.cluster_id, attr.attribute_id, attr.mfg_code, attr.data_type, value))
      end
    end
  end
end

-- Standard configuration: bind/report standard clusters, read the private-mode attribute, clear any
-- groups (required by these devices) and refresh current state.
local function do_configure(self, device)
  device:configure()
  device:send(cluster_base.read_manufacturer_specific_attribute(device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE))
  device:send(Groups.server.commands.RemoveAllGroups(device)) -- required
  do_refresh(self, device)
end

-- On add, advertise supported button values and restore the last known power/energy (so the values
-- are not blanked to 0 on re-add).
local function device_added(driver, device)
  if (device:supports_capability_by_id(capabilities.button.ID)) then
    device:emit_event(capabilities.button.supportedButtonValues({ "pushed" }, { visibility = { displayed = false } }))
  end
  if (device:supports_capability_by_id(capabilities.powerMeter.ID)) then
    local lastPower = device:get_latest_state("main", capabilities.powerMeter.ID, capabilities.powerMeter.power.NAME) or 0.0
    local lastEnergy = device:get_latest_state("main", capabilities.energyMeter.ID, capabilities.energyMeter.energy.NAME) or 0.0
    device:emit_event(capabilities.powerMeter.power({ value = lastPower, unit = "W" }))
    device:emit_event(capabilities.energyMeter.energy({ value = lastEnergy, unit = "Wh" }))
  end
end

local aqara_switch_handler = {
  NAME = "Aqara Switch Handler",
  lifecycle_handlers = {
    added = device_added,
    doConfigure = do_configure,
    infoChanged = device_info_changed
  },
  capability_handlers = {
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = mode_handler
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zigbee_handlers = {
    attr = {
      [ElectricalMeasurement.ID] = {
        [ElectricalMeasurement.attributes.ActivePower.ID] = power_meter_handler
      },
      [SimpleMetering.ID] = {
        [SimpleMetering.attributes.CurrentSummationDelivered.ID] = energy_meter_power_consumption_report
      },
      [WIRELESS_SWITCH_CLUSTER_ID] = {
        [WIRELESS_SWITCH_ATTRIBUTE_ID] = wireless_switch_handler
      },
      [PRIVATE_CLUSTER_ID] = {
        [PRIVATE_ATTRIBUTE_ID] = private_mode_handler,
        [INTERLOCK_ATTRIBUTE_ID] = interlock_switch_handler,
        [DEVICE_MODE_ATTRIBUTE_ID] = device_mode_handler
      }
    }
  },
  sub_drivers = {
    require("aqara.version"),
    require("aqara.multi-switch")
  },
  can_handle = require("aqara.can_handle"),
}

return aqara_switch_handler
