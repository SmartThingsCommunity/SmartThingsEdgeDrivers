-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local constants = require "st.zwave.constants"

local ThermostatMode = (require "st.zwave.CommandClass.ThermostatMode")({ version = 2 })
local ThermostatSetpoint = (require "st.zwave.CommandClass.ThermostatSetpoint")({ version = 2 })
local ThermostatFanMode = (require "st.zwave.CommandClass.ThermostatFanMode")({ version = 3 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local ThermostatOperatingState =
  (require "st.zwave.CommandClass.ThermostatOperatingState")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })

-- Work around a lua_libs test-harness bug: without ST_CAPABILITY_JSON_DIR set
-- (it requires a SmartThings API token we don't have in this sandbox),
-- mock_capability_channel's fallback capability-JSON reconstruction reads a
-- live command object's `.arguments` field, but aware.lua only ever sets
-- `.arg_list` -- so every rebuilt capability ends up with an empty argument
-- list, and any setter command (setHeatingSetpoint, setThermostatFanMode,
-- ...) fails with "Too many args for <Capability>.<command>". Pre-seed the
-- channel's cache with the original bundled JSON (unresolved $ref schemas
-- validate permissively per capability_utils.validate_type, so this is safe)
-- so the buggy reconstruction path is never reached.
do
  local mock_capability_channel = require "integration_test.mock_capability_channel"
  local st_json = require "st.json"

  local function seed_capability_json(capability_id)
    local raw_json = require("st.capabilities.generated." .. capability_id)
    local cap = capabilities.build_cap_from_json_string(raw_json, false)

    local inlined = {
      id = cap.ID, name = cap.NAME, version = cap.version, attributes = {}, commands = {}
    }
    for key, value in pairs(cap) do
      if key ~= "commands" and type(value) == "table" and value.schema ~= nil then
        inlined.attributes[key] = { schema = value.schema }
        if value.enumCommands then
          inlined.attributes[key].enumCommands = value.enumCommands
        end
      end
    end
    for cmd_name, cmd in pairs(cap.commands) do
      inlined.commands[cmd_name] = { name = cmd.NAME, arguments = cmd.arg_list or {} }
    end

    mock_capability_channel:__load_capability_definition(capability_id, 1, st_json.encode(inlined))
  end

  seed_capability_json("thermostatFanMode")
  seed_capability_json("thermostatHeatingSetpoint")
  seed_capability_json("thermostatCoolingSetpoint")
end

local thermostat_endpoints = {
  {
    command_classes = {
      { value = zw.THERMOSTAT_MODE },
      { value = zw.THERMOSTAT_SETPOINT },
      { value = zw.THERMOSTAT_FAN_MODE },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.THERMOSTAT_OPERATING_STATE },
      { value = zw.BATTERY },
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("thermostat-sensi-st25z.yml"),
  zwave_endpoints = thermostat_endpoints,
  zwave_manufacturer_id = 0x046B,
  zwave_product_type = 0x0004,
  zwave_product_id = 0x0002,
})

local function test_init()
  test.mock_device.add_test_device(mock_device)

  -- The integration_test harness auto-dispatches an "init" lifecycle event
  -- for every test before the test body even starts running. Pre-queue a
  -- matching mock timer so device_init's call_with_delay(10.0, ...) has one
  -- to consume at that point, instead of firing immediately with nothing
  -- queued (which would otherwise send 8 unexpected GETs into every test).
  test.timer.__create_and_queue_test_time_advance_timer(10.0, "oneshot")
end
test.set_test_init_function(test_init)

----------------------------------------------------------------------
-- Lifecycle: init -- fires on every hub boot/driver reload (unlike `added`,
-- which only fires once at join). This device doesn't resend a setpoint
-- report on its own once the radio comes back, so a value changed locally
-- while the hub was powered off would otherwise never get picked up again.
--
-- The refresh is delayed 10s (device_init) so the test harness's own
-- auto-queued "init" event -- sent before every test in this file, per the
-- integration_test framework -- doesn't leak these sends into unrelated
-- tests below, none of which advance the mock clock anywhere near that far.
----------------------------------------------------------------------

test.register_coroutine_test(
  "Init lifecycle event should refresh every attribute 10s later (resync " ..
  "after a hub power-cycle, since a locally-changed setpoint isn't re-sent " ..
  "on its own)",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")

    -- test_init's pre-queued timer is what the harness's own ambient "init"
    -- dispatch (before this test body even starts) consumes; the callback
    -- it schedules is already pending by this point, waiting on mock time.
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        SensorMultilevel:Get({
          sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
          scale = SensorMultilevel.scale.relative_humidity.PERCENTAGE })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1 })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1 })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatMode:Get({})))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatFanMode:Get({})))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, Battery:Get({})))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({})))

    test.mock_time.advance_time(10.0)
  end
)

----------------------------------------------------------------------
-- Lifecycle: added -- overriding `added` replaces the base driver's own
-- (Supported* + device:refresh()), so our handler replicates that and adds
-- the idle-operating-state seed. Order among the refresh GETs isn't
-- meaningful (unstaggered, hub-queued), so this uses relaxed ordering.
----------------------------------------------------------------------

test.register_coroutine_test(
  "Added lifecycle event should request Supported* reports, seed an idle " ..
  "operating state, and refresh every other attribute",
  function()
    test.socket.zwave:__set_channel_ordering("relaxed")

    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatMode:SupportedGet({})))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatFanMode:SupportedGet({})))
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatOperatingState.thermostatOperatingState({ value = "idle" })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        SensorMultilevel:Get({
          sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
          scale = SensorMultilevel.scale.relative_humidity.PERCENTAGE })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1 })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1 })))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatMode:Get({})))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatFanMode:Get({})))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, Battery:Get({})))
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatOperatingState:Get({})))

    test.socket.device_lifecycle():__queue_receive({ mock_device.id, "added" })
    test.wait_for_events()
  end
)

----------------------------------------------------------------------
-- Thermostat fan mode -- this device reports/expects AUTO_HIGH/HIGH on the
-- wire, never AUTO_LOW/LOW (confirmed on a real device). The default Report
-- parser already handles AUTO_HIGH/HIGH, so only SupportedReport parsing and
-- the Set path are overridden here.
----------------------------------------------------------------------

test.register_message_test(
  "Setting the fan mode should generate the appropriate ThermostatFanMode:Set " ..
  "commands (on -> HIGH, auto -> AUTO_HIGH)",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id,
        { capability = "thermostatFanMode", command = "setThermostatFanMode", args = { "on" } } }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatFanMode:Set({ fan_mode = ThermostatFanMode.fan_mode.HIGH }))
    },
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id,
        { capability = "thermostatFanMode", command = "setThermostatFanMode", args = { "auto" } } }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatFanMode:Set({ fan_mode = ThermostatFanMode.fan_mode.AUTO_HIGH }))
    },
  }
)

test.register_coroutine_test(
  "Setting the fan mode should poll ThermostatFanMode:Get 5.0s later to verify",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(5.0, "oneshot")

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatFanMode", command = "setThermostatFanMode", args = { "on" } }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatFanMode:Set({ fan_mode = ThermostatFanMode.fan_mode.HIGH })))
    test.wait_for_events()

    test.mock_time.advance_time(5.0)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device, ThermostatFanMode:Get({})))
  end
)

test.register_message_test(
  "An unsolicited ThermostatFanMode:Report should update the thermostatFanMode " ..
  "capability (via the base driver's default Report parser)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
        zw_test_utils.zwave_test_build_receive_command(
          ThermostatFanMode:Report({ fan_mode = ThermostatFanMode.fan_mode.AUTO_HIGH }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatFanMode.thermostatFanMode("auto"))
    },
  }
)

test.register_message_test(
  "Supported fan mode report (boolean style, confirmed as what the real ST25Z " ..
  "sends: auto_high/high, no circulation) should populate the supported-values list",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        ThermostatFanMode:SupportedReport({ auto_high = true, high = true })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatFanMode.supportedThermostatFanModes({ "auto", "on" }))
    },
  }
)

----------------------------------------------------------------------
-- Setpoints: no deadband conflict, wire-scale precision handling
----------------------------------------------------------------------

test.register_message_test(
  "Setting the heating setpoint (no deadband conflict, default degF wire scale) " ..
  "should send a whole-integer degF Set",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id,
        { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint",
          args = { 24 } } }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT,
          precision = 0,
          value = 75
        }))
    }
  }
)

test.register_coroutine_test(
  "Setting the cooling setpoint (no deadband conflict, degC wire scale) should " ..
  "send a 0.1-precision degC Set",
  function()
    mock_device:set_field(
      constants.TEMPERATURE_SCALE, ThermostatSetpoint.scale.CELSIUS, { persist = true })

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatCoolingSetpoint", command = "setCoolingSetpoint", args = { 12.34 } }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = ThermostatSetpoint.scale.CELSIUS,
          precision = 1,
          value = 12.3,
          size = 2
        })))
  end
)

test.register_coroutine_test(
  "Setting a whole-number degC cooling setpoint should not crash serialization " ..
  "(regression: ThermostatSetpoint:Set size/precision mismatch)",
  function()
    mock_device:set_field(
      constants.TEMPERATURE_SCALE, ThermostatSetpoint.scale.CELSIUS, { persist = true })

    -- ThermostatSetpoint:Set auto-sizes its wire field from the *unscaled*
    -- value. For a whole-number degC value like 20.0, the auto-detector sees
    -- no fractional part and picks a 1-byte field -- but the driver always
    -- requests precision=1 for degC, so the actual encoded integer is
    -- 20.0 * 10 = 200, which overflows that byte and crashes string.pack.
    -- The driver forces size=2 explicitly for degC to avoid this.
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatCoolingSetpoint", command = "setCoolingSetpoint", args = { 20 } }
    })
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = ThermostatSetpoint.scale.CELSIUS,
          precision = 1,
          value = 20.0,
          size = 2
        })))
  end
)

----------------------------------------------------------------------
-- Deadband: push-opposing-setpoint-first, in both directions
----------------------------------------------------------------------

test.register_coroutine_test(
  "Heating setpoint request that would violate the deadband should bump COOLING " ..
  "first, then HEATING, landing on exactly a 2degF gap",
  function()
    -- Current cooling setpoint is 75degF. Requesting 24degC (~75degF) heat
    -- would leave a 0degF gap, so the driver must push cooling up to 77degF
    -- first and land heat at 75degF: a clean 2degF gap, adjacent violation.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 75, unit = "F" })))
    mock_device:emit_event(
      capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 75, unit = "F" }))
    test.wait_for_events()

    for _, delay in ipairs({ 0.4, 1.1, 1.8, 2.5 }) do
      test.timer.__create_and_queue_test_time_advance_timer(delay, "oneshot")
    end

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { 24 } }
    })
    test.wait_for_events()

    test.mock_time.advance_time(0.4)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT, precision = 0, value = 77
        })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 1.1
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT, precision = 0, value = 75
        })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 1.8
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1 })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 2.5
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1 })))
  end
)

test.register_coroutine_test(
  "Cooling setpoint request with a larger jump that would violate the deadband " ..
  "should bump HEATING first, then COOLING",
  function()
    -- Current heating setpoint is 70degF. Requesting a cooling setpoint of
    -- ~60degF (a 10degF jump, well past the deadband) forces heat down to
    -- 58degF first, landing cool at 60degF: still exactly a 2degF gap.
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 70, unit = "F" })))
    mock_device:emit_event(
      capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 70, unit = "F" }))
    test.wait_for_events()

    for _, delay in ipairs({ 0.4, 1.1, 1.8, 2.5 }) do
      test.timer.__create_and_queue_test_time_advance_timer(delay, "oneshot")
    end

    local requested_celsius = utils.f_to_c(60)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatCoolingSetpoint", command = "setCoolingSetpoint",
        args = { requested_celsius } }
    })
    test.wait_for_events()

    test.mock_time.advance_time(0.4)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT, precision = 0, value = 58
        })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 1.1
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT, precision = 0, value = 60
        })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 1.8
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1 })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 2.5
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1 })))
  end
)

test.register_coroutine_test(
  "Heating setpoint request that would violate the deadband (degC wire scale) " ..
  "should land on the converted ~1.1degC gap, not a raw 2.0 " ..
  "(regression: deadband unit conversion)",
  function()
    mock_device:set_field(
      constants.TEMPERATURE_SCALE, ThermostatSetpoint.scale.CELSIUS, { persist = true })

    -- DEADBAND_F (2.0) is a degF *difference*; converting it to degC must use
    -- the pure 5/9 ratio (~1.1degC), not treat 2.0 as if it were already a
    -- degC value. Current cooling setpoint is 25.0degC; requesting 24.0degC
    -- heat leaves only a 1.0degC gap, violating the ~1.1degC deadband, so the
    -- driver must bump cooling up first. The bumped value pins down which
    -- deadband was actually applied: 24.0 + 1.1 = 25.1degC (correct) vs.
    -- 24.0 + 2.0 = 26.0degC (the pre-fix bug).
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 25.0, unit = "C" })))
    mock_device:emit_event(
      capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 25.0, unit = "C" }))
    test.wait_for_events()

    for _, delay in ipairs({ 0.4, 1.1, 1.8, 2.5 }) do
      test.timer.__create_and_queue_test_time_advance_timer(delay, "oneshot")
    end

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatHeatingSetpoint", command = "setHeatingSetpoint", args = { 24.0 } }
    })
    test.wait_for_events()

    test.mock_time.advance_time(0.4)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = ThermostatSetpoint.scale.CELSIUS, precision = 1, value = 25.1, size = 2
        })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 1.1
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Set({
          setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
          scale = ThermostatSetpoint.scale.CELSIUS, precision = 1, value = 24.0, size = 2
        })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 1.8
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1 })))
    test.wait_for_events()

    test.mock_time.advance_time(0.7) -- 2.5
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1 })))
  end
)

----------------------------------------------------------------------
-- Unsolicited setpoint / operating state reports
----------------------------------------------------------------------

test.register_message_test(
  "A HEATING_1 setpoint report should round to a whole degF value",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        ThermostatSetpoint:Report({
          setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT,
          precision = 0,
          value = 72
        })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 72, unit = "F" }))
    },
  }
)

test.register_coroutine_test(
  "A COOLING_1 setpoint report should schedule an extra HEATING_1 Get 2.5s later",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2.5, "oneshot")

    test.socket.zwave:__queue_receive({
      mock_device.id,
      zw_test_utils.zwave_test_build_receive_command(
        ThermostatSetpoint:Report({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT,
          precision = 0,
          value = 75
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 75, unit = "F" })))
    test.wait_for_events()

    test.mock_time.advance_time(2.5)
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(mock_device,
        ThermostatSetpoint:Get({ setpoint_type = ThermostatSetpoint.setpoint_type.HEATING_1 })))
  end
)

test.register_coroutine_test(
  "A COOLING_1 setpoint report should NOT re-fire the HEATING_1 Get if the heat " ..
  "setpoint is already known",
  function()
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 70, unit = "F" })))
    mock_device:emit_event(
      capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 70, unit = "F" }))
    test.wait_for_events()

    test.socket.zwave:__queue_receive({
      mock_device.id,
      zw_test_utils.zwave_test_build_receive_command(
        ThermostatSetpoint:Report({
          setpoint_type = ThermostatSetpoint.setpoint_type.COOLING_1,
          scale = ThermostatSetpoint.scale.FAHRENHEIT,
          precision = 0,
          value = 75
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 75, unit = "F" })))
    test.wait_for_events()

    -- No zwave send expected: the guard sees heatingSetpoint already known.
    test.mock_time.advance_time(2.5)
    test.wait_for_events()
  end
)

test.register_message_test(
  "AUX_HEATING (heat-pump auxiliary/second-stage state 7, outside the base " ..
  "driver's default 0-6 range) should map to the heating operating state",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        ThermostatOperatingState:Report(
          { operating_state = ThermostatOperatingState.operating_state.AUX_HEATING })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatOperatingState.thermostatOperatingState({ value = "heating" }))
    },
  }
)

test.register_message_test(
  "2ND_STAGE_COOLING (heat-pump second-stage state 9) should map to the " ..
  "cooling operating state",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, zw_test_utils.zwave_test_build_receive_command(
        ThermostatOperatingState:Report(
          { operating_state = ThermostatOperatingState.operating_state.SECOND_STAGE_COOLING })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
        capabilities.thermostatOperatingState.thermostatOperatingState({ value = "cooling" }))
    },
  }
)

test.run_registered_tests()
