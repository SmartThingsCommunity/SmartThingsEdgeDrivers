local capabilities = require "st.capabilities"
local log = require "log"
local cc = require "st.zwave.CommandClass"
local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 2 })
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({ version = 3 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Association = (require "st.zwave.CommandClass.Association")({ version = 3 })
local MultiChannelAssociation =
  (require "st.zwave.CommandClass.MultiChannelAssociation")({ version = 3 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local ThermostatOperatingState =
  (require "st.zwave.CommandClass.ThermostatOperatingState")({ version = 1 })
local constants = require "st.zwave.constants"
local utils = require "st.utils"

-- Short aliases: these setpoint_type values are referenced ~25 times below.
local HEATING_1 = ThermostatSetpoint.setpoint_type.HEATING_1
local COOLING_1 = ThermostatSetpoint.setpoint_type.COOLING_1

----------------------------------------------------------------------
-- Simple sequencer helpers (Option 1)
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

-- Safe enum extractors with fallbacks
local function tm_enums()
  local m = ThermostatMode and ThermostatMode.mode
  return {
    OFF = m and m.OFF or 0x00,
    HEAT = m and m.HEAT or 0x01,
    COOL = m and m.COOL or 0x02,
    AUTO = m and m.AUTO or 0x03,
    AUXILIARY_HEAT = m and m.AUXILIARY_HEAT or 0x04,
    EMERGENCY_HEAT = m and m.EMERGENCY_HEAT or 0x04,
  }
end

-- One-time normalized enums
local TM = tm_enums()

----------------------------------------------------------------------
-- Helpers / prefs
----------------------------------------------------------------------

-- Normalize Z-Wave mode to capability string
local function zw_mode_to_capability(val)
  -- val can be number (0..), enum string ("HEAT"), or table-like
  local m = ThermostatMode and ThermostatMode.mode
  local num = (type(val) == "number" and val) or (m and m[val]) -- e.g. "HEAT" -> 1
  if num == (m and m.OFF) or num == 0 then return "off" end
  if num == (m and m.HEAT) or num == 1 then return "heat" end
  if num == (m and m.COOL) or num == 2 then return "cool" end
  if num == (m and m.AUTO) or num == 3 then return "auto" end
  if num == (m and m.AUXILIARY_HEAT) or num == (m and m.EMERGENCY_HEAT) or num == 11 then
    return "emergency heat"
  end
  return nil
end

local function thermostat_mode_report(_, device, cmd)
  -- Examples seen: cmd.args.mode = "HEAT" (string) or 1 (number)
  local cap = zw_mode_to_capability(cmd.args.mode)
  if cap then
    device:emit_event_for_endpoint(
      cmd.src_channel,
      capabilities.thermostatMode.thermostatMode(cap)
    )
  end
end

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

-- Room temperature and relative humidity (Sensor Multilevel v5)
local function sensor_multilevel_report(_, device, cmd)
  local sensor_type = cmd.args.sensor_type
  if sensor_type ~= SensorMultilevel.sensor_type.TEMPERATURE
    and sensor_type ~= SensorMultilevel.sensor_type.RELATIVE_HUMIDITY then
    return
  end

  -- libs vary on the field name; check them in order
  local val = cmd.args.sensor_value or cmd.args.scaled_value or cmd.args.value
  if val == nil or val ~= val or val == math.huge or val == -math.huge then return end

  if sensor_type == SensorMultilevel.sensor_type.RELATIVE_HUMIDITY then
    -- scale 0 = percentage; whole percent, matching the Zigbee driver
    local pct = math.max(0, math.min(100, utils.round(val)))
    device:emit_event(capabilities.relativeHumidityMeasurement.humidity({ value = pct }))
    return
  end

  -- scale: 0=C, 1=F
  local is_f = (cmd.args.scale == SensorMultilevel.scale.FAHRENHEIT) or (cmd.args.scale == 1)
  local unit = is_f and "F" or "C"

  -- remember wire scale for your setpoint logic
  device:set_field(
    constants.TEMPERATURE_SCALE,
    is_f and ThermostatSetpoint.scale.FAHRENHEIT or ThermostatSetpoint.scale.CELSIUS,
    { persist = true }
  )

  device:emit_event(capabilities.temperatureMeasurement.temperature({ value = val, unit = unit }))
end

local function get_wire_scale(device)
  -- Remembered from the latest Setpoint (or default to °F)
  return device:get_field(constants.TEMPERATURE_SCALE) or ThermostatSetpoint.scale.FAHRENHEIT
end

-- helpers to normalize rounding/precision by wire scale
local function round_int(x) return math.floor(x + 0.5) end

local function normalize_out(v, wire_scale)
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    -- Whole °F only
    return round_int(v), 0   -- precision=0
  else
    -- Keep 0.5°C or 0.1°C as you prefer; sticking with 0.1 like your current code
    local vv = math.floor(v * 10 + 0.5) / 10
    return vv, 1             -- precision=1
  end
end
-- Convert the unitless capability command number (usually °C) into the device's wire scale.
local function command_to_wire_value(cmd_val, wire_scale)
  local is_c_cmd = (cmd_val < 40)  -- ST often sends °C; heuristic
  local v
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    v = is_c_cmd and utils.c_to_f(cmd_val) or cmd_val
    v = round_int(v)  -- whole °F here
  else
    v = is_c_cmd and cmd_val or utils.f_to_c(cmd_val)
    v = math.floor(v * 10 + 0.5) / 10  -- keep 0.1°C like before
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

-- Temperature Poll Helper
local function poll_room_temp(device)
  if not device:is_cc_supported(cc.SENSOR_MULTILEVEL) then return end

  -- Use your remembered wire scale (defaults to °F in your code); returns
  -- ThermostatSetpoint.scale.FAHRENHEIT or .CELSIUS
  local wire_scale = get_wire_scale(device)

  local sm_scale =
    (wire_scale == ThermostatSetpoint.scale.FAHRENHEIT)
      and SensorMultilevel.scale.FAHRENHEIT
      or SensorMultilevel.scale.CELSIUS

  device:send(SensorMultilevel:Get({
    sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
    scale = sm_scale
  }))
end

-- Humidity Poll Helper
local function poll_humidity(device)
  if not device:is_cc_supported(cc.SENSOR_MULTILEVEL) then return end
  device:send(SensorMultilevel:Get({
    sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
    scale = SensorMultilevel.scale.relative_humidity.PERCENTAGE
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
local DEADBAND_F = 2.0

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

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

local function device_init(driver, device)
  -- Force device scale to °F (persist). Reports can overwrite later if needed.
  device:set_field(
    constants.TEMPERATURE_SCALE, ThermostatSetpoint.scale.FAHRENHEIT, { persist = true })

  -- First pass: stagger Supported* and current values
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
      if device:is_cc_supported(cc.SENSOR_MULTILEVEL) then
        device:send(SensorMultilevel:Get({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          -- scale is advisory; many stats reply in their native scale anyway
          scale = SensorMultilevel.scale.CELSIUS
        }))
      end
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

  -- An issue was observed where changing fan mode from the thermostat wasn't getting updated on the SmartThings app
  -- Turned out FAN MODE report was not getting sent, but just the THERMOSTAT STATE which isn't enough for the app
  -- to determine status of fan mode
  -- This requires fix at the thermostat firmware side, which will be reported to them separately.
  -- until then a work-around is being put here where fan mode report will be sent out periodically
  --
  device.thread:call_on_schedule(20, function()
    if device:is_cc_supported(cc.THERMOSTAT_FAN_MODE) then
      device:send(ThermostatFanMode:Get({}))
    end
  end, "fan_mode_poll")
end

local function device_added(driver, device)
  -- Seed operating state so the provisioning UI doesn't hang waiting for it.
  -- The real value arrives once the radio settles and the GET succeeds.
  device:emit_event(
    capabilities.thermostatOperatingState.thermostatOperatingState({ value = "idle" }))
end

local function do_configure(driver, device)
  local hub_node =
    device.parent_assigned_node_id or device.driver.environment_info.hub_zwave_id or 1
  -- Lifeline association (group 1) — stagger to avoid right-after-join hammer.
  -- Prefer MultiChannelAssociation (which this device supports) so the hub's
  -- endpoint 0 is explicitly included; plain Association:Set was leaving node_ids={}.
  request_sequence(device, {
    function()
      if device:is_cc_supported(cc.MULTI_CHANNEL_ASSOCIATION) then
        device:send(MultiChannelAssociation:Set({
          grouping_identifier = 1,
          node_ids = {},
          multi_channel_nodes = { { node_id = hub_node, bit_address = false, end_point = 0 } }
        }))
      elseif device:is_cc_supported(cc.ASSOCIATION) then
        device:send(Association:Set({ grouping_identifier = 1, node_ids = { hub_node } }))
      end
    end,
    function()
      if device:is_cc_supported(cc.MULTI_CHANNEL_ASSOCIATION) then
        device:send(MultiChannelAssociation:Get({ grouping_identifier = 1 }))
      elseif device:is_cc_supported(cc.ASSOCIATION) then
        device:send(Association:Get({ grouping_identifier = 1 }))
      end
    end,
  }, 1.0, 1.5)
end

----------------------------------------------------------------------
-- Capability handlers (sequenced follow-ups)
----------------------------------------------------------------------

local MODE_MAP = {
  ["off"] = TM.OFF,
  ["heat"] = TM.HEAT,
  ["cool"] = TM.COOL,
  ["auto"] = TM.AUTO,
  ["emergency heat"] = TM.EMERGENCY_HEAT, -- will exist even if .mode is missing
}

local function set_mode(driver, device, cmd)
  local tstat_mode = MODE_MAP[cmd.args.mode]
  if not tstat_mode then return end
  device:send_to_component(ThermostatMode:Set({ mode = tstat_mode }), cmd.component)

  request_sequence(device, {
    function() device:send_to_component(ThermostatMode:Get({}), cmd.component) end
  }, 0.7, 0.9)
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
  ["auto"] = _pick_auto_enum(),
  ["on"] = _pick_on_enum(),
  ["circulate"] = (ThermostatFanMode.fan_mode and ThermostatFanMode.fan_mode.CIRCULATION) or 0x06,
}

local function set_fan_mode(driver, device, cmd)
  local requested = cmd.args.mode or cmd.args.fanMode
  if not requested then return end

  -- normalize just in case
  requested = string.lower(tostring(requested))

  local fan_mode = FAN_MAP[requested]
  if not fan_mode then return end

  device:send_to_component(ThermostatFanMode:Set({ fan_mode = fan_mode }), cmd.component)
  -- verify
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

-- === Heating setpoint (honors wire scale) ===
local function set_heating_setpoint(driver, device, cmd)
  local wire_scale = get_wire_scale(device)

  local requested = command_to_wire_value(cmd.args.setpoint, wire_scale)
  if not requested then return end

  -- Device caps (keep your existing limits)
  local heat_min, heat_max, cool_min, cool_max
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    heat_min, heat_max = math.max(HEAT_MIN_F, 45.0), HEAT_MAX_F
    cool_min, cool_max = COOL_MIN_F, math.min(COOL_MAX_F, 99.0)
  else
    heat_min, heat_max = utils.f_to_c(math.max(HEAT_MIN_F, 45.0)), utils.f_to_c(HEAT_MAX_F)
    cool_min, cool_max = utils.f_to_c(COOL_MIN_F), utils.f_to_c(math.min(COOL_MAX_F, 99.0))
  end

  -- Clamp only; final rounding/precision chosen by normalize_out
  local tgt_heat = clamp_and_round(requested, heat_min, heat_max, nil)

  -- Current COOL (same wire scale)
  local cur_cool = latest_other_in_wire(
    device,
    capabilities.thermostatCoolingSetpoint,
    capabilities.thermostatCoolingSetpoint.coolingSetpoint.NAME,
    wire_scale
  )

  local db = deadband_in(wire_scale)
  local violates = (cur_cool ~= nil) and (tgt_heat > (cur_cool - db))

  if not violates then
    -- No deadband issue → set HEAT only
    local val_heat, prec_heat = normalize_out(tgt_heat, wire_scale)
    device:send(ThermostatSetpoint:Set({
      setpoint_type = HEATING_1,
      scale = wire_scale,
      precision = prec_heat,
      value = val_heat,
      size = setpoint_size_for(wire_scale)
    }))
    request_sequence(device, {
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 })) end
    }, 0.7, 1.0)
    return
  end

  -- Would violate → compute required COOL and check absolute limit
  local _, cool_abs_max = abs_limits_in_wire(wire_scale)
  local needed_cool = tgt_heat + db
  if needed_cool > cool_abs_max then
    log.warn(string.format("[HEAT set %.1f] Rejecting: COOL would need to be %.1f > abs max %.1f",
      tgt_heat, needed_cool, cool_abs_max))
    request_sequence(device, {
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 })) end,
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 })) end,
    }, 0.6, 0.2)
    return
  end

  local tgt_cool = clamp_and_round(needed_cool, cool_min, cool_max, nil)

  -- Order: COOL first, then HEAT
  local val_cool, prec_cool = normalize_out(tgt_cool, wire_scale)
  local val_heat2, prec_heat2 = normalize_out(tgt_heat, wire_scale)
  request_sequence(device, {
    function() device:send(ThermostatSetpoint:Set({
      setpoint_type = COOLING_1,
      scale = wire_scale,
      precision = prec_cool,
      value = val_cool,
      size = setpoint_size_for(wire_scale)
    })) end,
    function() device:send(ThermostatSetpoint:Set({
      setpoint_type = HEATING_1,
      scale = wire_scale,
      precision = prec_heat2,
      value = val_heat2,
      size = setpoint_size_for(wire_scale)
    })) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 })) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 })) end,
  }, 0.7, 0.4)
end

-- === Cooling setpoint (honors wire scale) ===
local function set_cooling_setpoint(driver, device, cmd)
  local wire_scale = get_wire_scale(device)

  local requested = command_to_wire_value(cmd.args.setpoint, wire_scale)
  if not requested then return end

  -- Device caps
  local heat_min, heat_max, cool_min, cool_max
  if wire_scale == ThermostatSetpoint.scale.FAHRENHEIT then
    heat_min, heat_max = math.max(HEAT_MIN_F, 45.0), HEAT_MAX_F
    cool_min, cool_max = COOL_MIN_F, math.min(COOL_MAX_F, 99.0)
  else
    heat_min, heat_max = utils.f_to_c(math.max(HEAT_MIN_F, 45.0)), utils.f_to_c(HEAT_MAX_F)
    cool_min, cool_max = utils.f_to_c(COOL_MIN_F), utils.f_to_c(math.min(COOL_MAX_F, 99.0))
  end

  local tgt_cool = clamp_and_round(requested, cool_min, cool_max, nil)

  -- Current HEAT (same wire scale)
  local cur_heat = latest_other_in_wire(
    device,
    capabilities.thermostatHeatingSetpoint,
    capabilities.thermostatHeatingSetpoint.heatingSetpoint.NAME,
    wire_scale
  )

  local db = deadband_in(wire_scale)
  local violates = (cur_heat ~= nil) and (tgt_cool < (cur_heat + db))

  if not violates then
    -- No deadband issue → set COOL only
    local val_cool, prec_cool = normalize_out(tgt_cool, wire_scale)
    device:send(ThermostatSetpoint:Set({
      setpoint_type = COOLING_1,
      scale = wire_scale,
      precision = prec_cool,
      value = val_cool,
      size = setpoint_size_for(wire_scale)
    }))
    request_sequence(device, {
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 })) end
    }, 0.7, 1.0)
    return
  end

  -- Would violate → compute required HEAT and check absolute limit
  local heat_abs_min, _ = abs_limits_in_wire(wire_scale)
  local needed_heat = tgt_cool - db
  if needed_heat < heat_abs_min then
    log.warn(string.format("[COOL set %.1f] Rejecting: HEAT would need to be %.1f < abs min %.1f",
      tgt_cool, needed_heat, heat_abs_min))
    request_sequence(device, {
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 })) end,
      function() device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 })) end,
    }, 0.6, 0.2)
    return
  end

  local tgt_heat = clamp_and_round(needed_heat, heat_min, heat_max, nil)

  -- Order: HEAT first, then COOL
  local val_heat, prec_heat = normalize_out(tgt_heat, wire_scale)
  local val_cool2, prec_cool2 = normalize_out(tgt_cool, wire_scale)
  request_sequence(device, {
    function() device:send(ThermostatSetpoint:Set({
      setpoint_type = HEATING_1,
      scale = wire_scale,
      precision = prec_heat,
      value = val_heat,
      size = setpoint_size_for(wire_scale)
    })) end,
    function() device:send(ThermostatSetpoint:Set({
      setpoint_type = COOLING_1,
      scale = wire_scale,
      precision = prec_cool2,
      value = val_cool2,
      size = setpoint_size_for(wire_scale)
    })) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 })) end,
    function() device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 })) end,
  }, 0.7, 0.4)
end

local OPERATING_STATE_MAP = {
  -- string enum form (some SDK versions)
  IDLE = "idle",
  HEATING = "heating",
  COOLING = "cooling",
  FAN_ONLY = "fan only",
  PENDING_HEAT = "pending heat",
  PENDING_COOL = "pending cool",
  VENT_ECONOMIZER = "vent economizer",
  AUX_HEATING = "heating",
  SECOND_STAGE_HEATING = "heating",
  SECOND_STAGE_COOLING = "cooling",
  SECOND_STAGE_AUX_HEAT = "heating",
  AUX_PLUS_SECOND_STAGE_HEAT = "heating",
  -- numeric form (other SDK versions)
  [0] = "idle",
  [1] = "heating",
  [2] = "cooling",
  [3] = "fan only",
  [4] = "pending heat",
  [5] = "pending cool",
  [6] = "vent economizer",
  [7] = "heating", -- AUX_HEATING
  [8] = "heating", -- 2ND_STAGE_HEATING (heat pump second stage / aux)
  [9] = "cooling", -- 2ND_STAGE_COOLING
  [10] = "heating", -- 2ND_STAGE_AUX_HEAT
  [11] = "heating", -- AUX_PLUS_2ND_STAGE_HEAT
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

local function refresh_all(self, device)
  request_sequence(device, {
    function()
      poll_room_temp(device)
    end,
    function()
      device:send(ThermostatSetpoint:Get({ setpoint_type = HEATING_1 }))
    end,
    function()
      device:send(ThermostatSetpoint:Get({ setpoint_type = COOLING_1 }))
    end,
    function()
      device:send(ThermostatMode:Get({}))
    end,
    function()
      device:send(ThermostatFanMode:Get({}))
    end,
    function()
      device:send(Battery:Get({}))
    end,
    function()
      if device:is_cc_supported(cc.THERMOSTAT_OPERATING_STATE) then
        device:send(ThermostatOperatingState:Get({}))
      end
    end,
    function()
      poll_humidity(device)
    end,
  }, 1.0, 0.0)
end

----------------------------------------------------------------------
-- Z-Wave report handlers
----------------------------------------------------------------------

local function thermostat_setpoint_report(_, device, cmd)
  -- Normalize scale: can be number (0/1) or string ("CELSIUS"/"FAHRENHEIT")
  local s = cmd.args.scale
  local is_f = (s == ThermostatSetpoint.scale.FAHRENHEIT) or (s == "FAHRENHEIT") or (s == 1)
  local unit = is_f and "F" or "C"

  -- Remember whatever the device told us (persist)
  device:set_field(
    constants.TEMPERATURE_SCALE,
    is_f and ThermostatSetpoint.scale.FAHRENHEIT or ThermostatSetpoint.scale.CELSIUS,
    { persist = true }
  )

  -- Round before emitting so app stays in integer mode for °F
  local raw = cmd.args.value
  local out_val
  if unit == "F" then
    out_val = round_int(raw) -- whole °F
  else
    out_val = math.floor(raw * 10 + 0.5) / 10 -- 0.1 °C
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

local function thermostat_mode_supported_report(_, device, cmd)
  local a = cmd.args or {}
  local supported = {}

  -- Style A: boolean fields (what your logs show)
  if type(a.off) == "boolean" then
    if a.off then table.insert(supported, "off") end
    if a.heat then table.insert(supported, "heat") end
    if a.cool then table.insert(supported, "cool") end
    if a.auto then table.insert(supported, "auto") end
    -- Aux/emergency shows up as "auxiliary_emergency_heat" on some stacks
    if a.auxiliary_emergency_heat or a.emergency_heat then
      table.insert(supported, "emergency heat")
    end
  else
    -- Style B: numeric bitmask (older libs)
    local map = {
      OFF = "off",
      HEAT = "heat",
      COOL = "cool",
      AUTO = "auto",
      AUXILIARY_HEAT = "emergency heat",
      EMERGENCY_HEAT = "emergency heat",
    }
    local sm = a.supported_modes or {}
    for k, name in pairs(map) do
      -- k could be enum name or numeric; accept both
      local bit = (ThermostatMode.mode and ThermostatMode.mode[k]) or k
      if sm[bit] then table.insert(supported, name) end
    end
  end

  if #supported > 0 then
    device:emit_event(capabilities.thermostatMode.supportedThermostatModes(supported))
  end

  device.thread:call_with_delay(1.2, function()
    if device:is_cc_supported(cc.THERMOSTAT_MODE) then
      device:send(ThermostatMode:Get({}))
    end
  end)
end

local function fan_mode_supported_report(_, device, cmd)
  local a = cmd.args or {}
  local supported = {}

  -- Style A: boolean fields (your logs: auto_high=true, high=true, ...)
  if type(a.auto_high) == "boolean" or type(a.auto_low) == "boolean" then
    -- Any AUTO_* counts as "auto"
    if a.auto_low or a.auto_medium or a.auto_high then
      table.insert(supported, "auto")
    end
    -- Any *_SPEED or "on"/"on_high" counts as "on"
    if a.low or a.medium or a.high or a.on or a.on_high then
      table.insert(supported, "on")
    end
    -- Circulation
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

local function battery_report(_, device, cmd)
  local pct = math.max(0, math.min(100, cmd.args.battery_level or 0))
  device:emit_event(capabilities.battery.battery(pct))
end

----------------------------------------------------------------------
-- Sub-driver table
----------------------------------------------------------------------

return {
  NAME = "thermostat-sensi-st25z",

  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
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
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = set_mode
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
    [cc.THERMOSTAT_MODE] = {
      [ThermostatMode.SUPPORTED_REPORT] = thermostat_mode_supported_report,
      [ThermostatMode.REPORT] = thermostat_mode_report,
    },
    [cc.THERMOSTAT_FAN_MODE] = {
      [ThermostatFanMode.SUPPORTED_REPORT] = fan_mode_supported_report,
      [ThermostatFanMode.REPORT] = fan_mode_report,
    },
    [cc.BATTERY] = {
      [Battery.REPORT] = battery_report,
    },
    [cc.SENSOR_MULTILEVEL] = {
      [SensorMultilevel.REPORT] = sensor_multilevel_report,
    },
    [cc.THERMOSTAT_OPERATING_STATE] = {
      [ThermostatOperatingState.REPORT] = thermostat_operating_state_report,
    },
  },

  can_handle = require("thermostat-sensi-st25z.can_handle")
}
