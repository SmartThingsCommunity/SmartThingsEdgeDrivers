-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local log = require "log"
local cc = require "st.zwave.CommandClass"
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 2 })
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({ version = 3 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local ThermostatOperatingState =
  (require "st.zwave.CommandClass.ThermostatOperatingState")({ version = 1 })
local constants = require "st.zwave.constants"
local utils = require "st.utils"

-- Short aliases: these setpoint_type values are referenced ~15 times below.
local HEATING_1 = ThermostatSetpoint.setpoint_type.HEATING_1
local COOLING_1 = ThermostatSetpoint.setpoint_type.COOLING_1

----------------------------------------------------------------------
-- Everything in this subdriver exists only where the base zwave-thermostat
-- driver's default handlers (st.zwave.defaults.*) fall short for this device:
--   * fan mode: this device reports/expects AUTO_HIGH/HIGH on the wire
--     (confirmed on a real device), but the default fan-mode handling only
--     ever checks AUTO_LOW/LOW/CIRCULATION -- relying on it would silently
--     stop fan mode from updating for this device.
--   * setpoint deadband enforcement (the defaults have none)
--   * setpoint report rounding/precision + a missing-HEAT-report retry
--     (real quirks observed on this device)
--   * heat-pump auxiliary/second-stage operating states 7-11 (the default
--     operating-state handler only maps 0-6)
-- Thermostat mode, battery, and plain temperature/humidity reporting are
-- left to the base driver's defaults.
----------------------------------------------------------------------

local function send_after(device, delay_s, fn)
  device.thread:call_with_delay(delay_s, function()
    local ok, err = pcall(fn)
    if not ok then
      log.warn("[send_after] " .. tostring(err))
    end
  end)
end

local function request_sequence(device, steps, spacing_s, initial_delay_s)
  local delay = initial_delay_s or 0.0
  local space = spacing_s or 0.7
  for _, step in ipairs(steps) do
    send_after(device, delay, step)
    delay = delay + space
  end
end

----------------------------------------------------------------------
-- Helpers / prefs
----------------------------------------------------------------------

local function get_wire_scale(device)
  -- Remembered from the latest Setpoint report (or default to °F)
  return device:get_field(constants.TEMPERATURE_SCALE) or ThermostatSetpoint.scale.FAHRENHEIT
end

-- helpers to normalize rounding/precision by wire scale
local function round_int(x) return math.floor(x + 0.5) end

local function normalize_out(v, wire_scale)
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    return round_int(v), 0   -- whole °F, precision=0
  else
    local vv = math.floor(v * 10 + 0.5) / 10
    return vv, 1             -- 0.1 °C, precision=1
  end
end

-- Convert the unitless capability command number (usually °C) into the device's wire scale.
local function command_to_wire_value(cmd_val, wire_scale)
  local is_c_cmd = (cmd_val < 40)  -- ST often sends °C; heuristic
  local v
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    v = is_c_cmd and utils.c_to_f(cmd_val) or cmd_val
    v = round_int(v)
  else
    v = is_c_cmd and cmd_val or utils.f_to_c(cmd_val)
    v = math.floor(v * 10 + 0.5) / 10
  end
  if v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

-- ThermostatSetpoint:Set auto-sizes its wire field from the *unscaled* value,
-- before our explicit precision scales it up -- a whole-number degC setpoint
-- (e.g. 13.0) auto-sizes to 1 byte, then precision=1 scales it to 130 and
-- overflows that byte during serialization. Force 2 bytes for degC, which
-- comfortably covers the full range regardless of whether the value is a
-- whole number. degF never hits this (max value 99, precision 0 always fits).
local function setpoint_size_for(wire_scale)
  return (wire_scale == ThermostatSetpoint.scale.CELSIUS) and 2 or nil
end

local function poll_room_temp(device)
  if not device:is_cc_supported(cc.SENSOR_MULTILEVEL) then return end
  local wire_scale = get_wire_scale(device)
  local sm_scale =
    (wire_scale == ThermostatSetpoint.scale.FAHRENHEIT)
      and SensorMultilevel.scale.FAHRENHEIT
      or  SensorMultilevel.scale.CELSIUS
  device:send(SensorMultilevel:Get({
    sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
    scale       = sm_scale
  }))
end

local function poll_humidity(device)
  if not device:is_cc_supported(cc.SENSOR_MULTILEVEL) then return end
  device:send(SensorMultilevel:Get({
    sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
    scale       = SensorMultilevel.scale.relative_humidity.PERCENTAGE
  }))
end

-- Read the *other* setpoint (cool when setting heat, or heat when setting cool)
-- and express it in the same wire scale for deadband checks.
local function latest_other_in_wire(device, attr_capability, attr_name, wire_scale)
  local raw = device:get_latest_state("main", attr_capability.ID, attr_name)
  if raw == nil then return nil end
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    return (raw < 40) and utils.c_to_f(raw) or raw
  else
    return (raw >= 40) and utils.f_to_c(raw) or raw
  end
end

local function clamp_and_round(value, min_v, max_v, precision)
  local v = math.min(math.max(value, min_v), max_v)
  if precision then
    local p = 10 ^ precision
    v = math.floor(v * p + 0.5) / p
  end
  return v
end

-- Absolute limits expressed in the device's active wire scale
local function abs_limits_in_wire(wire_scale)
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    return 45.0, 99.0  -- heat_abs_min, cool_abs_max
  else
    return utils.f_to_c(45.0), utils.f_to_c(99.0)
  end
end

local HEAT_MIN_F, HEAT_MAX_F = 45.0, 97.0
local COOL_MIN_F, COOL_MAX_F = 47.0, 99.0
local DEADBAND_F             = 2.0

-- DEADBAND_F is a *temperature difference*, not an absolute value -- converting
-- it to degC must use the pure 5/9 ratio, not utils.f_to_c's affine (subtracts
-- 32 first) conversion, which is only valid for absolute temperatures. Matches
-- the Zigbee driver's DEADBAND_C = 1.1.
local function deadband_in(wire_scale)
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    return DEADBAND_F
  else
    return DEADBAND_F / 1.8
  end
end

local function device_caps_in_wire(wire_scale)
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    return math.max(HEAT_MIN_F, 45.0), HEAT_MAX_F, COOL_MIN_F, math.min(COOL_MAX_F, 99.0)
  else
    return utils.f_to_c(math.max(HEAT_MIN_F, 45.0)), utils.f_to_c(HEAT_MAX_F),
           utils.f_to_c(COOL_MIN_F), utils.f_to_c(math.min(COOL_MAX_F, 99.0))
  end
end

-- Shared by set_heating_setpoint/set_cooling_setpoint: enforce the deadband
-- between the two setpoints, pushing the *other* one out of the way first
-- (sent before the requested one) when needed, or rejecting the request if
-- doing so would itself exceed the absolute limit.
--
-- is_heat: true when setting the heating setpoint, false for cooling.
local function enforce_deadband_and_set(device, cmd, is_heat)
  local wire_scale = get_wire_scale(device)
  local requested = command_to_wire_value(cmd.args.setpoint, wire_scale)
  if not requested then return end

  local heat_min, heat_max, cool_min, cool_max = device_caps_in_wire(wire_scale)
  local db = deadband_in(wire_scale)

  local this_type, this_min, this_max = HEATING_1, heat_min, heat_max
  local other_type, other_min, other_max = COOLING_1, cool_min, cool_max
  local other_capability, other_attr = capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME
  if not is_heat then
    this_type, this_min, this_max = COOLING_1, cool_min, cool_max
    other_type, other_min, other_max = HEATING_1, heat_min, heat_max
    other_capability, other_attr = capabilities.thermostatHeatingSetpoint,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME
  end

  local tgt_this = clamp_and_round(requested, this_min, this_max, nil)
  local cur_other = latest_other_in_wire(device, other_capability, other_attr, wire_scale)

  local violates
  if is_heat then
    violates = (cur_other ~= nil) and (tgt_this > (cur_other - db))
  else
    violates = (cur_other ~= nil) and (tgt_this < (cur_other + db))
  end

  if not violates then
    local val_this, prec_this = normalize_out(tgt_this, wire_scale)
    device:send(ThermostatSetpoint:Set({
      setpoint_type = this_type,
      scale = wire_scale,
      precision = prec_this,
      value = val_this,
      size = setpoint_size_for(wire_scale)
    }))
    request_sequence(device, {
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = this_type })) end
    }, 0.7, 1.0)
    return
  end

  -- Would violate -> compute the required OTHER setpoint and check its absolute limit
  local needed_other = is_heat and (tgt_this + db) or (tgt_this - db)
  local heat_abs_min, cool_abs_max = abs_limits_in_wire(wire_scale)
  local other_abs_limit_violated
  if is_heat then
    other_abs_limit_violated = needed_other > cool_abs_max
  else
    other_abs_limit_violated = needed_other < heat_abs_min
  end

  if other_abs_limit_violated then
    log.warn(string.format(
      "[%s set %.1f] Rejecting: other setpoint would need to be %.1f, out of range",
      is_heat and "HEAT" or "COOL", tgt_this, needed_other))
    request_sequence(device, {
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = this_type })) end,
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = other_type })) end,
    }, 0.6, 0.2)
    return
  end

  local tgt_other = clamp_and_round(needed_other, other_min, other_max, nil)
  local val_other, prec_other = normalize_out(tgt_other, wire_scale)
  local val_this2, prec_this2 = normalize_out(tgt_this, wire_scale)

  -- Order: OTHER first, then THIS
  request_sequence(device, {
    function() device:send(ThermostatSetpoint:Set({
      setpoint_type = other_type,
      scale = wire_scale,
      precision = prec_other,
      value = val_other,
      size = setpoint_size_for(wire_scale)
    })) end,
    function() device:send(ThermostatSetpoint:Set({
      setpoint_type = this_type,
      scale = wire_scale,
      precision = prec_this2,
      value = val_this2,
      size = setpoint_size_for(wire_scale)
    })) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = other_type })) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = this_type })) end,
  }, 0.7, 0.4)
end

local function set_heating_setpoint(driver, device, cmd)
  enforce_deadband_and_set(device, cmd, true)
end

local function set_cooling_setpoint(driver, device, cmd)
  enforce_deadband_and_set(device, cmd, false)
end

----------------------------------------------------------------------
-- Fan mode -- this device reports/expects AUTO_HIGH/HIGH on the wire, never
-- AUTO_LOW/LOW, so the base driver's defaults (which never check
-- HIGH/AUTO_HIGH) are not sufficient here. Confirmed on a real device via
-- ThermostatFanMode SUPPORTED_REPORT (auto_high=true, high=true, on_high=true)
-- and REPORT (fan_mode="AUTO_HIGH"/"HIGH").
----------------------------------------------------------------------

local function zw_fan_mode_to_capability(val)
  local fm = ThermostatFanMode.fan_mode or {}
  local num = (type(val) == "number" and val) or (fm[val])
  if num == nil then return nil end
  if num == fm.AUTO_LOW or num == fm.AUTO_MEDIUM or num == fm.AUTO_HIGH then return "auto" end
  if num == fm.LOW or num == fm.MEDIUM or num == fm.HIGH then return "on" end
  if num == fm.CIRCULATION then return "circulate" end
  return nil
end

local function fan_mode_report(_, device, cmd)
  -- Examples seen: cmd.args.fan_mode = "HIGH" (string) or a number
  local cap = zw_fan_mode_to_capability(cmd.args.fan_mode)
  if cap then
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.thermostatFanMode.thermostatFanMode(cap)
    )
  end
end

local function fan_mode_supported_report(_, device, cmd)
  local a = cmd.args or {}
  local supported = {}

  -- Style A: boolean fields (confirmed on a real device: auto_high=true, high=true, ...)
  if type(a.auto_high) == "boolean" or type(a.auto_low) == "boolean" then
    if a.auto_low or a.auto_medium or a.auto_high then
      table.insert(supported, "auto")
    end
    if a.low or a.medium or a.high or a.on or a.on_high then
      table.insert(supported, "on")
    end
    if a.circulation then
      table.insert(supported, "circulate")
    end
  else
    -- Style B: numeric bitmask
    local sm = a.supported or {}
    local tfm = ThermostatFanMode.fan_mode or {}
    local auto_any = sm[tfm.AUTO_LOW] or sm[tfm.AUTO_MEDIUM] or sm[tfm.AUTO_HIGH]
    local on_any = sm[tfm.LOW] or sm[tfm.MEDIUM] or sm[tfm.HIGH]
    local circ = sm[tfm.CIRCULATION]

    if auto_any then table.insert(supported, "auto") end
    if on_any then table.insert(supported, "on") end
    if circ then table.insert(supported, "circulate") end
  end

  if #supported > 0 then
    device:emit_event(capabilities.thermostatFanMode.supportedThermostatFanModes(supported))
  end
end

-- choose enums the device actually supports
local function _pick_auto_enum()
  local fm = ThermostatFanMode.fan_mode or {}
  return fm.AUTO_HIGH or fm.AUTO_LOW            -- prefer AUTO_HIGH if available
end

local function _pick_on_enum()
  local fm = ThermostatFanMode.fan_mode or {}
  return fm.HIGH or fm.LOW                      -- prefer HIGH if available
end

local FAN_MAP = {
  ["auto"]      = _pick_auto_enum(),
  ["on"]        = _pick_on_enum(),
  ["circulate"] = (ThermostatFanMode.fan_mode and ThermostatFanMode.fan_mode.CIRCULATION) or 0x06,
}

local function set_fan_mode(driver, device, cmd)
  local requested = cmd.args.mode or cmd.args.fanMode
  if not requested then return end

  requested = string.lower(tostring(requested))

  local fan_mode = FAN_MAP[requested]
  if not fan_mode then return end

  device:send_to_component(ThermostatFanMode:Set({ fan_mode = fan_mode }), cmd.component)
  device.thread:call_with_delay(5.0, function()
    device:send_to_component(ThermostatFanMode:Get({}), cmd.component)
  end)
end

-- thermostatFanMode's fanAuto/fanOn/fanCirculate are separate commands (not just
-- setThermostatFanMode with an arg), each needs its own handler registered below
local function fan_auto(driver, device, cmd)
  set_fan_mode(driver, device, { args = { mode = "auto" }, component = cmd.component })
end

local function fan_on(driver, device, cmd)
  set_fan_mode(driver, device, { args = { mode = "on" }, component = cmd.component })
end

local function fan_circulate(driver, device, cmd)
  set_fan_mode(driver, device, { args = { mode = "circulate" }, component = cmd.component })
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

local function device_init(driver, device)
  -- Force device scale to °F (persist). Reports can overwrite later if needed.
  device:set_field(
    constants.TEMPERATURE_SCALE, ThermostatSetpoint.scale.FAHRENHEIT, { persist = true })

  -- Stagger Supported* and current-value requests: this radio can't handle
  -- simultaneous requests at join.
  request_sequence(device, {
    function()
      if device:is_cc_supported(cc.THERMOSTAT_MODE) then
        device:send(ThermostatMode:SupportedGet({}))
      end
    end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_FAN_MODE) then
        device:send(ThermostatFanMode:SupportedGet({}))
      end
    end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_SETPOINT) then
        device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 }))
      end
    end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_SETPOINT) then
        device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 }))
      end
    end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_MODE) then
        device:send(ThermostatMode:Get({}))
      end
    end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_FAN_MODE) then
        device:send(ThermostatFanMode:Get({}))
      end
    end,
    function()
      poll_room_temp(device)
    end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_OPERATING_STATE) then
        device:send(ThermostatOperatingState:Get({}))
      end
    end,
    function()
      poll_humidity(device)
    end,
  }, 1.1, 1.2)

  -- Single late retry for mode only — guarded so it only fires if mode is still unknown
  device.thread:call_with_delay(15.0, function()
    local cur = device:get_latest_state("main", capabilities.thermostatMode.ID, "thermostatMode")
    if not cur and device:is_cc_supported(cc.THERMOSTAT_MODE) then
      device:send(ThermostatMode:Get({}))
    end
  end)

  -- Late guards: retry heating setpoint and temperature if still missing after
  -- radio has fully settled. Handles the case where initial GETs failed and
  -- the device didn't send unsolicited reports for these during join.
  device.thread:call_with_delay(12.0, function()
    local cur = device:get_latest_state(
      "main", capabilities.thermostatHeatingSetpoint.ID, "heatingSetpoint")
    if not cur and device:is_cc_supported(cc.THERMOSTAT_SETPOINT) then
      device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 }))
    end
  end)

  device.thread:call_with_delay(14.0, function()
    local cur = device:get_latest_state(
      "main", capabilities.thermostatCoolingSetpoint.ID, "coolingSetpoint")
    if not cur and device:is_cc_supported(cc.THERMOSTAT_SETPOINT) then
      device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 }))
    end
  end)

  device.thread:call_with_delay(16.0, function()
    local cur = device:get_latest_state(
      "main", capabilities.thermostatOperatingState.ID, "thermostatOperatingState")
    if not cur and device:is_cc_supported(cc.THERMOSTAT_OPERATING_STATE) then
      device:send(ThermostatOperatingState:Get({}))
    end
  end)

  device.thread:call_with_delay(17.0, function()
    local cur = device:get_latest_state(
      "main", capabilities.thermostatFanMode.ID, "thermostatFanMode")
    if not cur and device:is_cc_supported(cc.THERMOSTAT_FAN_MODE) then
      device:send(ThermostatFanMode:Get({}))
    end
  end)

  device.thread:call_with_delay(13.0, function()
    local cur = device:get_latest_state(
      "main", capabilities.temperatureMeasurement.ID, "temperature")
    if not cur then
      poll_room_temp(device)
    end
  end)

  device.thread:call_with_delay(18.0, function()
    local cur = device:get_latest_state(
      "main", capabilities.relativeHumidityMeasurement.ID, "humidity")
    if not cur then
      poll_humidity(device)
    end
  end)
end

local function device_added(driver, device)
  -- Seed operating state so the provisioning UI doesn't hang waiting for it.
  -- The real value arrives once the radio settles and the GET succeeds.
  device:emit_event(
    capabilities.thermostatOperatingState.thermostatOperatingState({ value = "idle" }))
end

----------------------------------------------------------------------
-- Operating state (heat-pump auxiliary / second-stage states; the base
-- driver's default only maps states 0-6)
----------------------------------------------------------------------

local OPERATING_STATE_MAP = {
  -- string enum form (some SDK versions)
  IDLE                       = "idle",
  HEATING                    = "heating",
  COOLING                    = "cooling",
  FAN_ONLY                   = "fan only",
  PENDING_HEAT               = "pending heat",
  PENDING_COOL                = "pending cool",
  VENT_ECONOMIZER            = "vent economizer",
  AUX_HEATING                = "heating",
  SECOND_STAGE_HEATING       = "heating",
  SECOND_STAGE_COOLING       = "cooling",
  SECOND_STAGE_AUX_HEAT      = "heating",
  AUX_PLUS_SECOND_STAGE_HEAT = "heating",
  -- numeric form (other SDK versions)
  [0]  = "idle",
  [1]  = "heating",
  [2]  = "cooling",
  [3]  = "fan only",
  [4]  = "pending heat",
  [5]  = "pending cool",
  [6]  = "vent economizer",
  [7]  = "heating",   -- AUX_HEATING
  [8]  = "heating",   -- 2ND_STAGE_HEATING (heat pump second stage / aux)
  [9]  = "cooling",   -- 2ND_STAGE_COOLING
  [10] = "heating",   -- 2ND_STAGE_AUX_HEAT
  [11] = "heating",   -- AUX_PLUS_2ND_STAGE_HEAT
}

local function thermostat_operating_state_report(_, device, cmd)
  local state = OPERATING_STATE_MAP[cmd.args.operating_state]
  log.debug(string.format(
    "[OperatingState] raw=%s mapped=%s", tostring(cmd.args.operating_state), tostring(state)))
  if state then
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.thermostatOperatingState.thermostatOperatingState({ value = state })
    )
  end
end

----------------------------------------------------------------------
-- Setpoint report (rounding/precision to match this device + a retry for a
-- missing HEAT report; the base driver's default report doesn't round and
-- doesn't retry)
----------------------------------------------------------------------

local function thermostat_setpoint_report(_, device, cmd)
  -- Normalize scale: can be number (0/1) or string ("CELSIUS"/"FAHRENHEIT")
  local s     = cmd.args.scale
  local is_f  = (s == ThermostatSetpoint.scale.FAHRENHEIT) or (s == "FAHRENHEIT") or (s == 1)
  local unit  = is_f and "F" or "C"

  device:set_field(
    constants.TEMPERATURE_SCALE,
    is_f and ThermostatSetpoint.scale.FAHRENHEIT or ThermostatSetpoint.scale.CELSIUS,
    { persist = true }
  )

  -- Round before emitting so app stays in integer mode for °F
  local raw = cmd.args.value
  local out_val
  if unit == "F" then
    out_val = round_int(raw)
  else
    out_val = math.floor(raw * 10 + 0.5) / 10
  end

  if cmd.args.setpoint_type == HEATING_1 then
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = out_val, unit = unit })
    )
  elseif cmd.args.setpoint_type == COOLING_1 then
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = out_val, unit = unit })
    )
    -- Retry HEAT once the radio quiets down, but only if we still don't have it.
    device.thread:call_with_delay(2.5, function()
      local cur_heat = device:get_latest_state(
        "main", capabilities.thermostatHeatingSetpoint.ID, "heatingSetpoint")
      if not cur_heat and device:is_cc_supported(cc.THERMOSTAT_SETPOINT) then
        device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 }))
      end
    end)
  end
end

----------------------------------------------------------------------
-- Refresh (staggered, for the same radio-can't-handle-simultaneous-requests
-- reason as device_init; the base driver's default refresh batches all GETs
-- at once)
----------------------------------------------------------------------

local function refresh_all(self, device)
  request_sequence(device, {
    function() poll_room_temp(device) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 })) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 })) end,
    function() device:send(ThermostatMode:Get({})) end,
    function() device:send(ThermostatFanMode:Get({})) end,
    function() device:send(Battery:Get({})) end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_OPERATING_STATE) then
        device:send(ThermostatOperatingState:Get({}))
      end
    end,
    function() poll_humidity(device) end,
  }, 1.0, 0.0)
end

----------------------------------------------------------------------
-- Sub-driver table
----------------------------------------------------------------------

return {
  NAME = "thermostat-sensi-st25z",

  lifecycle_handlers = {
    init  = device_init,
    added = device_added,
  },

  capability_handlers = {
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] =
        set_heating_setpoint
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      [capabilities.thermostatCoolingSetpoint.commands.setCoolingSetpoint.NAME] =
        set_cooling_setpoint
    },
    [capabilities.thermostatFanMode.ID] = {
      [capabilities.thermostatFanMode.commands.setThermostatFanMode.NAME] = set_fan_mode,
      [capabilities.thermostatFanMode.commands.fanAuto.NAME] = fan_auto,
      [capabilities.thermostatFanMode.commands.fanOn.NAME] = fan_on,
      [capabilities.thermostatFanMode.commands.fanCirculate.NAME] = fan_circulate
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = refresh_all
    }
  },

  zwave_handlers = {
    [cc.THERMOSTAT_SETPOINT] = {
      [ThermostatSetpoint.REPORT] = thermostat_setpoint_report,
    },
    [cc.THERMOSTAT_FAN_MODE] = {
      [ThermostatFanMode.SUPPORTED_REPORT] = fan_mode_supported_report,
      [ThermostatFanMode.REPORT]           = fan_mode_report,
    },
    [cc.THERMOSTAT_OPERATING_STATE] = {
      [ThermostatOperatingState.REPORT] = thermostat_operating_state_report,
    },
  },

  can_handle = require("thermostat-sensi-st25z.can_handle")
}
