-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local capabilities    = require "st.capabilities"
local ZigbeeDriver    = require "st.zigbee"
local defaults        = require "st.zigbee.defaults"
local cluster_base    = require "st.zigbee.cluster_base"
local zcl_clusters    = require "st.zigbee.zcl.clusters"
local data_types      = require "st.zigbee.data_types"

local aqara           = require "aqara_cluster"

local OnOff           = zcl_clusters.OnOff
local Level           = zcl_clusters.Level
local ColorControl    = zcl_clusters.ColorControl

-- Aqara manufacturer-specific preference keys
local nightLightMode = "stse.nightLightMode"
local nightLightEndTime = "stse.nightLightEndTime"
local nightLightStartTime = "stse.nightLightStartTime"
local muteBeep = "stse.muteBeep"
local thermostatCtrl = "stse.thermostatCtrl"

-- AC code field values (see send_ac_code for the bit layout)
local PWR             = { OFF = 0x0, ON = 0x1 }
local MODE            = { HEAT = 0x0, DRYAIR = 0x3, COOL = 0x4, FANONLY = 0x5, INVALID = 0xF }
local FAN_LOW         = 0x0
local FAN_MID         = 0x1
local FAN_HIGH        = 0x2
local FAN_INVALID     = 0xF
local SWING_ON        = 0x0
local SWING_OFF       = 0x1

-- SmartThings fanMode capability values
local SPEED           = {
  LOW    = "low",
  MEDIUM = "medium",
  HIGH   = "high",
}
local MODE_TO_FAN     = { [SPEED.LOW] = FAN_LOW, [SPEED.MEDIUM] = FAN_MID, [SPEED.HIGH] = FAN_HIGH }
local FAN_TO_MODE     = { [FAN_LOW] = SPEED.LOW, [FAN_MID] = SPEED.MEDIUM, [FAN_HIGH] = SPEED.HIGH }

-- SmartThings fanOscillationMode capability values
local OSC             = {
  SWING = "swing",
  FIXED = "fixed",
}
local ST_FAN_TO_SWING = {
  [OSC.SWING] = SWING_ON,
  [OSC.FIXED] = SWING_OFF,
}

-- SmartThings thermostatMode capability values
local ST_MODE         = {
  OFF     = "off",
  HEAT    = "heat",
  DRYAIR  = "dryair",
  COOL    = "cool",
  FANONLY = "fanonly",
}

-- SmartThings thermostatMode -> AC parameters
local ST_TO_AC        = {
  [ST_MODE.OFF]     = { pwr = PWR.OFF, mode = MODE.INVALID, fan = FAN_INVALID },
  [ST_MODE.HEAT]    = { pwr = PWR.ON, mode = MODE.HEAT, fan = FAN_MID },
  [ST_MODE.DRYAIR]  = { pwr = PWR.ON, mode = MODE.DRYAIR, fan = FAN_MID },
  [ST_MODE.COOL]    = { pwr = PWR.ON, mode = MODE.COOL, fan = FAN_MID },
  [ST_MODE.FANONLY] = { pwr = PWR.ON, mode = MODE.FANONLY, fan = FAN_MID },
}

-- AC mode bits -> SmartThings thermostatMode
local AC_MODE_TO_ST   = {
  [0x0] = ST_MODE.HEAT,
  [0x3] = ST_MODE.DRYAIR,
  [0x4] = ST_MODE.COOL,
  [0x5] = ST_MODE.FANONLY,
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

-- Encode and send the 64-bit AC control code as an Aqara manufacturer attribute.
-- A nibble of 0xF means "no change"; the default 0xFFFFFFFFFFFFFFFF leaves
-- every field untouched so callers only need to set what they want to change.
--   pwr      : bits31-28  0=off    1=on
--   mode     : bits27-24  0=heat   3=dryair  4=cool  5=fanonly
--   fan      : bits23-20  0=low    1=mid     2=high  3=auto
--   swing    : bits17-16  0=swing  1=fixed
--   setpoint : bits63-48  Celsius x 100
local function send_ac_code(device, params)
  local hi32 = 0xFFFFFFFF
  local lo32 = 0xFFFFFFFF

  if params.setpoint ~= nil then
    local sp_raw = math.floor(clamp(params.setpoint, 16, 45) * 100) & 0xFFFF
    hi32 = (sp_raw << 16) | 0xFFFF
  end

  if params.pwr ~= nil then
    lo32 = (lo32 & 0x0FFFFFFF) | ((params.pwr & 0xF) << 28)
  end

  if params.mode ~= nil then
    lo32 = (lo32 & 0xF0FFFFFF) | ((params.mode & 0xF) << 24)
  end

  if params.fan ~= nil then
    lo32 = (lo32 & 0xFF0FFFFF) | ((params.fan & 0xF) << 20)
  end

  if params.swing ~= nil then
    lo32 = (lo32 & 0xFFFCFFFF) | ((params.swing & 0x3) << 16)
  end

  local bytes = string.char(
    (hi32 >> 24) & 0xFF,
    (hi32 >> 16) & 0xFF,
    (hi32 >> 8) & 0xFF,
    hi32 & 0xFF,
    (lo32 >> 24) & 0xFF,
    (lo32 >> 16) & 0xFF,
    (lo32 >> 8) & 0xFF,
    lo32 & 0xFF
  )

  device:send(cluster_base.write_manufacturer_specific_attribute(
    device, aqara.CLUSTER_ID, aqara.ATTR_AC_CODE, aqara.MFG_CODE,
    data_types.Uint64, bytes
  ))
end

-- Per-mode state persistence: remember the last swing/fan used in each
-- thermostat mode so they can be restored when the user returns to it.
-- Setpoint is shared across modes and read directly from the capability state.
local FIELD = {
  SWING    = "swing",
  FAN_MODE = "fan_mode",
}

-- Fields tracked per mode (modes not listed here have no per-mode state).
local MODE_FIELDS = {
  [ST_MODE.HEAT]    = { FIELD.SWING, FIELD.FAN_MODE },
  [ST_MODE.COOL]    = { FIELD.SWING, FIELD.FAN_MODE },
  [ST_MODE.DRYAIR]  = { FIELD.SWING, FIELD.FAN_MODE },
  [ST_MODE.FANONLY] = { FIELD.FAN_MODE },
}

-- Initial values when no saved state exists yet for a mode.
local MODE_DEFAULTS = {
  [ST_MODE.HEAT]    = { swing = OSC.SWING, fan_mode = SPEED.MEDIUM },
  [ST_MODE.COOL]    = { swing = OSC.SWING, fan_mode = SPEED.MEDIUM },
  [ST_MODE.DRYAIR]  = { swing = OSC.SWING, fan_mode = SPEED.MEDIUM },
  [ST_MODE.FANONLY] = { fan_mode = SPEED.MEDIUM },
}

local function save_mode_state(device, mode, field, value)
  device:set_field("mode_state." .. mode .. "." .. field, value, { persist = true })
end

local function load_mode_state(device, mode, field)
  return device:get_field("mode_state." .. mode .. "." .. field)
end

local function save_current_mode_field(device, field, value)
  local mode = device:get_field("thermostat_mode") or ST_MODE.OFF
  local fields = MODE_FIELDS[mode]
  if fields then
    for _, f in ipairs(fields) do
      if f == field then
        save_mode_state(device, mode, field, value)
        return
      end
    end
  end
end

-- Capture the current capability state for each field tracked by the given
-- mode. Used right before switching modes so any in-flight changes (e.g., a
-- setpoint set via the UI but not yet confirmed by the device) are preserved.
local function snapshot_mode_state(device, mode)
  local fields = MODE_FIELDS[mode]
  if not fields then return end

  for _, field in ipairs(fields) do
    local v
    if field == FIELD.SWING then
      v = device:get_latest_state("main",
        capabilities.fanOscillationMode.ID,
        capabilities.fanOscillationMode.fanOscillationMode.NAME)
    elseif field == FIELD.FAN_MODE then
      v = device:get_latest_state("main",
        capabilities.fanMode.ID,
        capabilities.fanMode.fanMode.NAME)
    end
    if v ~= nil then
      save_mode_state(device, mode, field, v)
    end
  end
end

-- Re-emit saved values for the entered mode and push them to the AC in a
-- single batched code, falling back to MODE_DEFAULTS on first use.
local function restore_mode_state(device, st_mode)
  local fields = MODE_FIELDS[st_mode]
  if not fields then return end

  local mode_defaults = MODE_DEFAULTS[st_mode] or {}
  local swing, fan = nil, nil

  for _, field in ipairs(fields) do
    if field == FIELD.SWING then
      local v = load_mode_state(device, st_mode, FIELD.SWING) or mode_defaults.swing
      if v ~= nil then
        swing = ST_FAN_TO_SWING[v]
        device:set_field("fan_mode", v)
        device:emit_event(capabilities.fanOscillationMode.fanOscillationMode(v))
      end
    elseif field == FIELD.FAN_MODE then
      local v = load_mode_state(device, st_mode, FIELD.FAN_MODE) or mode_defaults.fan_mode
      if v ~= nil then
        fan = MODE_TO_FAN[v]
        device:set_field("fan_mode_ac", fan)
        device:emit_event(capabilities.fanMode.fanMode(v))
      end
    end
  end

  if swing ~= nil or fan ~= nil then
    send_ac_code(device, { swing = swing, fan = fan })
  end
end


-- Capability handlers
local function handle_thermostat_mode(driver, device, cmd)
  local st_mode = cmd.args.mode
  local ac = ST_TO_AC[st_mode]
  if not ac then return end

  local prev_mode = device:get_field("thermostat_mode")
  if prev_mode and prev_mode ~= st_mode then
    snapshot_mode_state(device, prev_mode)
  end

  local pwr = (st_mode == ST_MODE.OFF) and PWR.OFF or PWR.ON
  -- Setpoint is shared across modes; on entry to HEAT, push the last value
  -- the user set so the device matches what the UI is currently showing.
  local setpoint = nil
  if st_mode == ST_MODE.HEAT then
    local state = device:get_latest_state("main",
      capabilities.thermostatHeatingSetpoint.ID,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME)
    if state ~= nil then
      setpoint = clamp(state, 16, 45)
    end
  end

  send_ac_code(device, { pwr = pwr, mode = ac.mode, setpoint = setpoint })
  device:set_field("thermostat_mode", st_mode)
  device:emit_event(capabilities.thermostatMode.thermostatMode(st_mode))
  restore_mode_state(device, st_mode)

  if st_mode ~= ST_MODE.OFF then
    device:set_field("pending_on_mode", st_mode)
  else
    device:set_field("pending_on_mode", nil)
  end
end

local function handle_heating_setpoint(driver, device, cmd)
  local temp_c = clamp(cmd.args.setpoint, 16, 45)
  device:set_field("heating_setpoint", temp_c)

  local cur = device:get_field("thermostat_mode") or ST_MODE.OFF
  if cur == ST_MODE.HEAT then
    send_ac_code(device, { setpoint = temp_c })
  end
end

local function handle_fan_oscillation_mode(driver, device, cmd)
  local st_fan = cmd.args.fanOscillationMode
  local swing  = ST_FAN_TO_SWING[st_fan] or SWING_ON

  device:set_field("fan_mode", st_fan)
  send_ac_code(device, { swing = swing })
end

local function handle_fan_mode(driver, device, cmd)
  local fan_mode = cmd.args.fanMode
  local fan      = MODE_TO_FAN[fan_mode] or FAN_MID
  device:set_field("fan_mode_ac", fan)
  send_ac_code(device, { fan = fan })
end

local function handle_refresh(driver, device)
  device:send(OnOff.attributes.OnOff:read(device))
  device:send(Level.attributes.CurrentLevel:read(device))
  device:send(ColorControl.attributes.ColorTemperatureMireds:read(device))
end

-- Zigbee attribute handlers
-- Decode the AC code reported by the device, emit matching capability events,
-- and persist the per-mode state so values are restored when the user returns
-- to that mode.
local function ac_code_attr_handler(driver, device, value, zb_rx)
  local raw = value.value
  local hi32, lo32

  -- The attribute is a Uint64 but may arrive either as a raw integer or as
  -- the 8-byte big-endian payload depending on the runtime path.
  if type(raw) == "string" then
    local b = { string.byte(raw, 1, 8) }
    hi32 = ((b[1] or 0) << 24) | ((b[2] or 0) << 16) | ((b[3] or 0) << 8) | (b[4] or 0)
    lo32 = ((b[5] or 0) << 24) | ((b[6] or 0) << 16) | ((b[7] or 0) << 8) | (b[8] or 0)
  else
    hi32 = (raw >> 32) & 0xFFFFFFFF
    lo32 = raw & 0xFFFFFFFF
  end

  local pwr          = (lo32 >> 28) & 0xF
  local mode         = (lo32 >> 24) & 0xF
  local fan_set      = (lo32 >> 20) & 0xF
  local b15_8        = (lo32 >> 8) & 0xFF
  local b7_0         = lo32 & 0xFF
  local bits7_2      = (b7_0 >> 2) & 0x3F

  -- The setpoint nibbles are only trustworthy when the surrounding sentinel
  -- bytes match this pattern; otherwise the device is reporting "no change".
  local hi_valid     = (b15_8 >= 0xFE) and (bits7_2 == 63)
  local setpoint_raw = (hi32 >> 16) & 0xFFFF

  if hi_valid and setpoint_raw ~= 0xFFFF then
    local sp = setpoint_raw / 100.0
    device:set_field("heating_setpoint", sp)
    device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint(
      { value = sp, unit = "C" }
    ))
  end

  -- fan speed (bits23-20): 0=low, 1=mid, 2=high; 3=auto and 0xF are ignored.
  if fan_set <= 2 then
    local fan_mode = FAN_TO_MODE[fan_set] or SPEED.MEDIUM
    device:set_field("fan_mode_ac", fan_set)
    save_current_mode_field(device, FIELD.FAN_MODE, fan_mode)
    device:emit_event(capabilities.fanMode.fanMode(fan_mode))
  end

  -- swing mode (bits17-16): 0=swing, 1=fixed; other values are ignored.
  local swing_bit = (lo32 >> 16) & 0x3
  if swing_bit == 0 then
    device:set_field("fan_mode", OSC.SWING)
    save_current_mode_field(device, FIELD.SWING, OSC.SWING)
    device:emit_event(capabilities.fanOscillationMode.fanOscillationMode(OSC.SWING))
  elseif swing_bit == 1 then
    device:set_field("fan_mode", OSC.FIXED)
    save_current_mode_field(device, FIELD.SWING, OSC.FIXED)
    device:emit_event(capabilities.fanOscillationMode.fanOscillationMode(OSC.FIXED))
  end

  -- 0xF in the pwr nibble is the "no change" sentinel; mode bits are unreliable.
  if pwr == 0xF then return end

  local st_mode
  if pwr == 0x0 then
    st_mode = ST_MODE.OFF
  else
    st_mode = AC_MODE_TO_ST[mode] or ST_MODE.HEAT
  end

  -- Suppress a transient "off" report that arrives between a mode change
  -- request and the device confirming the new mode.
  local pending = device:get_field("pending_on_mode")
  if st_mode ~= ST_MODE.OFF then
    device:set_field("pending_on_mode", nil)
  else
    if pending ~= nil then return end
  end

  local current = device:get_field("thermostat_mode")
  if current ~= st_mode then
    device:set_field("thermostat_mode", st_mode)
    device:emit_event(capabilities.thermostatMode.thermostatMode(st_mode))
  end
end

local SUPPORTED_THERMOSTAT_MODES = {
  capabilities.thermostatMode.thermostatMode.off.NAME,
  capabilities.thermostatMode.thermostatMode.heat.NAME,
  capabilities.thermostatMode.thermostatMode.dryair.NAME,
  capabilities.thermostatMode.thermostatMode.cool.NAME,
  capabilities.thermostatMode.thermostatMode.fanonly.NAME
}

local SUPPORTED_FAN_MODES = {
  capabilities.fanOscillationMode.fanOscillationMode.swing.NAME,
  capabilities.fanOscillationMode.fanOscillationMode.fixed.NAME
}

local SUPPORTED_SPEED_MODES = { SPEED.LOW, SPEED.MEDIUM, SPEED.HIGH }

-- Lifecycle handlers
local function device_init(driver, device)
  device:emit_event(capabilities.thermostatMode.supportedThermostatModes(
    SUPPORTED_THERMOSTAT_MODES, { visibility = { displayed = false } }
  ))
  device:emit_event(capabilities.fanOscillationMode.supportedFanOscillationModes(
    SUPPORTED_FAN_MODES, { visibility = { displayed = false } }
  ))
  device:emit_event(capabilities.fanMode.supportedFanModes(
    SUPPORTED_SPEED_MODES, { visibility = { displayed = false } }
  ))
  device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpointRange(
    { value = { minimum = 16, maximum = 45, step = 1 }, unit = "C" }
  ))
  handle_refresh(driver, device)
end

local function device_added(driver, device)
  if device:get_latest_state("main", capabilities.thermostatHeatingSetpoint.ID,
        capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME) == nil then
    device:emit_event(capabilities.thermostatHeatingSetpoint.heatingSetpoint(
      { value = 25, unit = "C" }
    ))
    send_ac_code(device, { setpoint = 25 })
  end
  if device:get_latest_state("main", capabilities.fanMode.ID,
        capabilities.fanMode.fanMode.NAME) == nil then
    device:emit_event(capabilities.fanMode.fanMode(SPEED.MEDIUM))
  end
  if device:get_latest_state("main", capabilities.fanOscillationMode.ID,
        capabilities.fanOscillationMode.fanOscillationMode.NAME) == nil then
    device:emit_event(capabilities.fanOscillationMode.fanOscillationMode(OSC.SWING))
  end
end

local function send_night_light(device, new)
  local start_time = (tonumber(new[nightLightStartTime]) * 60) & 0xFFF
  local end_time  = (tonumber(new[nightLightEndTime]) * 60) & 0xFFF
  local on_val    = (end_time << 12) | start_time
  local val       = new[nightLightMode] and on_val or (on_val + 1)
  device:send(cluster_base.write_manufacturer_specific_attribute(
    device, aqara.CLUSTER_ID, aqara.ATTR_NIGHT_LIGHT,
    aqara.MFG_CODE, data_types.Uint32, val))
end

local function info_changed(driver, device, event, args)
  if args.old_st_store.preferences == nil then return end

  local old = args.old_st_store.preferences
  local new = device.preferences

  -- Night-light: re-send when the on/off toggle flips, or when the schedule
  -- changes while the feature is enabled.
  local mode_changed = old[nightLightMode] ~= new[nightLightMode]
  local time_changed =
      old[nightLightEndTime] ~= new[nightLightEndTime] or
      old[nightLightStartTime] ~= new[nightLightStartTime]
  if mode_changed then
    send_night_light(device, new)
  elseif time_changed and new[nightLightMode] == true then
    send_night_light(device, new)
  end

  -- Mute beep ("do not disturb"). On first init we always push the value so
  -- the device matches the preference even if it was changed before pairing.
  if old[muteBeep] ~= new[muteBeep] or device:get_field("inited") == nil then
    local val = new[muteBeep] and 1 or 0
    device:set_field("inited", true)
    device:send(cluster_base.write_manufacturer_specific_attribute(
      device, aqara.CLUSTER_ID, aqara.ATTR_DND_BEEP,
      aqara.MFG_CODE, data_types.Uint8, val))
    -- When un-muted, configure the DND window to span 24h (00:18 - 00:18).
    if val == 0 then
      device:send(cluster_base.write_manufacturer_specific_attribute(
        device, aqara.CLUSTER_ID, aqara.ATTR_DND_TIME,
        aqara.MFG_CODE, data_types.Uint32, 0x00120012))
    end
  end

  -- Constant-temperature thermostat control switch.
  if old[thermostatCtrl] ~= new[thermostatCtrl] then
    device:send(cluster_base.write_manufacturer_specific_attribute(
      device, aqara.CLUSTER_ID, aqara.ATTR_THERMOSTAT_CTRL_SW,
      aqara.MFG_CODE, data_types.Uint8, new[thermostatCtrl] and 1 or 0))
  end
end

local aqara_bathroom_heater_driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.colorTemperature
  },

  capability_handlers = {
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = handle_thermostat_mode,
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = handle_heating_setpoint,
    },
    [capabilities.fanOscillationMode.ID] = {
      [capabilities.fanOscillationMode.commands.setFanOscillationMode.NAME] = handle_fan_oscillation_mode,
    },
    [capabilities.fanMode.ID] = {
      [capabilities.fanMode.commands.setFanMode.NAME] = handle_fan_mode,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
  },

  zigbee_handlers = {
    attr = {
      [aqara.CLUSTER_ID] = {
        [aqara.ATTR_AC_CODE] = ac_code_attr_handler,
      },
    },
  },
  health_check = false,
  lifecycle_handlers = {
    init        = device_init,
    added       = device_added,
    infoChanged = info_changed,
  },
}

defaults.register_for_default_handlers(
  aqara_bathroom_heater_driver_template,
  aqara_bathroom_heater_driver_template.supported_capabilities,
  { native_capability_cmds_enabled = true, native_capability_attrs_enabled = true }
)

local aqara_bathroom_heater_driver = ZigbeeDriver("aqara-bathroom-heater-t1", aqara_bathroom_heater_driver_template)
aqara_bathroom_heater_driver:run()
