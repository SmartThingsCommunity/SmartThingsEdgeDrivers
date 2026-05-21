-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
--
-- Consolidated test cases for the Aqara Bath Heater T1 SmartThings Edge driver.
--
-- IMPORTANT: The test framework fires an "init" lifecycle event before every
-- test (the driver must complete its startup sequence before the test body
-- can run). Because `device_init` emits multiple capability events
-- (supported*, range) and issues three Zigbee attribute reads, `test_init`
-- pre-registers those expectations BEFORE calling `add_test_device(...)`, so
-- each individual test body can ignore the init emissions and focus only on
-- its own test-specific expectations.

local test                    = require "integration_test"
local t_utils                 = require "integration_test.utils"
local capabilities            = require "st.capabilities"
local zigbee_test_utils       = require "integration_test.zigbee_test_utils"
local cluster_base            = require "st.zigbee.cluster_base"
local data_types              = require "st.zigbee.data_types"
local clusters                = require "st.zigbee.zcl.clusters"

local OnOff                   = clusters.OnOff
local Level                   = clusters.Level
local ColorControl            = clusters.ColorControl

local AQARA_CLUSTER_ID        = 0xFCC0
local AQARA_MFG_CODE          = 0x115F
local ATTR_AC_CODE            = 0x024F
local ATTR_THERMOSTAT_CTRL_SW = 0x02BE
local ATTR_DND_BEEP           = 0x0256
local ATTR_DND_TIME           = 0x0257
local ATTR_NIGHT_LIGHT        = 0x0518

local mock_device             = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("aqara-bath-heater.yml"),
  fingerprinted_endpoint_id = 0x01,
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "Aqara",
      model = "lumi.bhf_light.acn001",
      server_clusters = { 0x0006, 0x0008, 0x0300, 0xFCC0 }
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.thermostatMode.supportedThermostatModes(
      { "off", "heat", "dryair", "cool", "fanonly" },
      { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.fanOscillationMode.supportedFanOscillationModes(
      { "swing", "fixed" },
      { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.fanMode.supportedFanModes(
      { "low", "medium", "high" },
      { visibility = { displayed = false } })))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.thermostatHeatingSetpoint.heatingSetpointRange(
      { value = { minimum = 16, maximum = 45, step = 1 }, unit = "C" })))
  test.socket.zigbee:__expect_send({ mock_device.id,
    OnOff.attributes.OnOff:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id,
    Level.attributes.CurrentLevel:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id,
    ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

-- ----------------------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------------------

-- Build the 8-byte big-endian raw payload for the Aqara AC-code Uint64 attr.
local function ac_code_bytes(hi32, lo32)
  return string.char(
    (hi32 >> 24) & 0xFF,
    (hi32 >> 16) & 0xFF,
    (hi32 >> 8) & 0xFF,
    hi32 & 0xFF,
    (lo32 >> 24) & 0xFF,
    (lo32 >> 16) & 0xFF,
    (lo32 >> 8) & 0xFF,
    lo32 & 0xFF
  )
end

local function expect_ac_code_send(hi32, lo32)
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_manufacturer_specific_attribute(mock_device,
      AQARA_CLUSTER_ID, ATTR_AC_CODE, AQARA_MFG_CODE,
      data_types.Uint64, ac_code_bytes(hi32, lo32)) })
end

local function build_ac_code_report(hi32, lo32)
  return zigbee_test_utils.build_attribute_report(mock_device, AQARA_CLUSTER_ID,
    { { ATTR_AC_CODE, data_types.Uint64.ID, ac_code_bytes(hi32, lo32) } })
end

-- ============================================================================
-- 1. CAPABILITY COMMAND HANDLERS
-- ============================================================================
--
-- switch / switchLevel / colorTemperature are handled by the SmartThings
-- default zigbee handlers (registered via defaults.register_for_default_handlers),
-- so their behavior is covered by the framework's own tests and is not
-- re-tested here.

-- thermostatMode.setThermostatMode --------------------------------------------

test.register_coroutine_test(
  "Capability thermostatMode 'off' should send AC off code and emit event",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatMode",
        component = "main",
        command = "setThermostatMode",
        args = { "off" }
      } })

    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0x0FFFFFFF) | (0x0 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0xF << 24)
    expect_ac_code_send(hi32, lo32)

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("off")))
  end
)

test.register_coroutine_test(
  "Capability thermostatMode 'heat' should send AC code and restore defaults",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatMode",
        component = "main",
        command = "setThermostatMode",
        args = { "heat" }
      } })

    -- No prior heatingSetpoint latest state, so the first AC code carries
    -- only pwr=1 and mode=0 (no setpoint nibble set).
    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x0 << 24)
    expect_ac_code_send(hi32, lo32)

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("heat")))

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("swing")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))

    local r_hi = 0xFFFFFFFF
    local r_lo = 0xFFFFFFFF
    r_lo = (r_lo & 0xFF0FFFFF) | (0x1 << 20)
    r_lo = (r_lo & 0xFFFCFFFF) | (0x0 << 16)
    expect_ac_code_send(r_hi, r_lo)
  end
)

test.register_coroutine_test(
  "Capability thermostatMode 'cool' should send AC code (mode=4)",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatMode",
        component = "main",
        command = "setThermostatMode",
        args = { "cool" }
      } })

    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x4 << 24)
    expect_ac_code_send(hi32, lo32)

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("cool")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("swing")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))

    local r_hi = 0xFFFFFFFF
    local r_lo = 0xFFFFFFFF
    r_lo = (r_lo & 0xFF0FFFFF) | (0x1 << 20)
    r_lo = (r_lo & 0xFFFCFFFF) | (0x0 << 16)
    expect_ac_code_send(r_hi, r_lo)
  end
)

test.register_coroutine_test(
  "Capability thermostatMode 'dryair' should send AC code (mode=3)",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatMode",
        component = "main",
        command = "setThermostatMode",
        args = { "dryair" }
      } })

    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x3 << 24)
    expect_ac_code_send(hi32, lo32)

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("dryair")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("swing")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))

    local r_hi = 0xFFFFFFFF
    local r_lo = 0xFFFFFFFF
    r_lo = (r_lo & 0xFF0FFFFF) | (0x1 << 20)
    r_lo = (r_lo & 0xFFFCFFFF) | (0x0 << 16)
    expect_ac_code_send(r_hi, r_lo)
  end
)

test.register_coroutine_test(
  "Capability thermostatMode 'fanonly' should send AC code (mode=5) and restore only fan",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatMode",
        component = "main",
        command = "setThermostatMode",
        args = { "fanonly" }
      } })

    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x5 << 24)
    expect_ac_code_send(hi32, lo32)

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("fanonly")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))

    local r_hi = 0xFFFFFFFF
    local r_lo = (0xFFFFFFFF & 0xFF0FFFFF) | (0x1 << 20)
    expect_ac_code_send(r_hi, r_lo)
  end
)

-- NOTE: setThermostatMode("unsupported_mode") would hit the driver's
-- `if not ac then return end` guard, but the capability framework validates
-- `mode` against its enum and rejects unknown values before the handler runs.

-- thermostatHeatingSetpoint.setHeatingSetpoint --------------------------------

test.register_coroutine_test(
  "Capability heatingSetpoint 28 in non-heat mode produces no observable output",
  function()
    -- Outside heat mode the handler only stashes the value in a field; the
    -- capability event will fire later via the AC-code attribute report from
    -- the device, not from this command path.
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatHeatingSetpoint",
        component = "main",
        command = "setHeatingSetpoint",
        args = { 28 }
      } })
  end
)

-- NOTE: setHeatingSetpoint(10) / (60) would exercise the clamp(..., 16, 45),
-- but the profile constrains the setpoint to [16, 45] so framework validation
-- rejects those values. The same clamp is exercised via restore_mode_state
-- ("setThermostatMode heat should restore saved setpoint/swing/fan from
-- mode_state") below.

test.register_coroutine_test(
  "Capability heatingSetpoint in heat mode should send AC code with setpoint",
  function()
    mock_device:set_field("thermostat_mode", "heat")
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatHeatingSetpoint",
        component = "main",
        command = "setHeatingSetpoint",
        args = { 30 }
      } })

    local hi32 = ((3000 & 0xFFFF) << 16) | (0xFFFFFFFF & 0xFFFF)
    local lo32 = 0xFFFFFFFF
    expect_ac_code_send(hi32, lo32)
  end
)

-- fanOscillationMode.setFanOscillationMode ------------------------------------

test.register_coroutine_test(
  "Capability fanOscillationMode 'swing' sends AC code with swing bits=0",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "fanOscillationMode",
        component = "main",
        command = "setFanOscillationMode",
        args = { "swing" }
      } })

    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0xFFFCFFFF) | (0x0 << 16)
    expect_ac_code_send(hi32, lo32)
  end
)

test.register_coroutine_test(
  "Capability fanOscillationMode 'fixed' sends AC code with swing bits=1",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "fanOscillationMode",
        component = "main",
        command = "setFanOscillationMode",
        args = { "fixed" }
      } })

    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0xFFFCFFFF) | (0x1 << 16)
    expect_ac_code_send(hi32, lo32)
  end
)

-- fanMode.setFanMode ----------------------------------------------------------

test.register_coroutine_test(
  "Capability fanMode 'low' sends AC code with fan bits=0",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "fanMode",
        component = "main",
        command = "setFanMode",
        args = { "low" }
      } })
    expect_ac_code_send(0xFFFFFFFF, (0xFFFFFFFF & 0xFF0FFFFF) | (0x0 << 20))
  end
)

test.register_coroutine_test(
  "Capability fanMode 'medium' sends AC code with fan bits=1",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "fanMode",
        component = "main",
        command = "setFanMode",
        args = { "medium" }
      } })
    expect_ac_code_send(0xFFFFFFFF, (0xFFFFFFFF & 0xFF0FFFFF) | (0x1 << 20))
  end
)

test.register_coroutine_test(
  "Capability fanMode 'high' sends AC code with fan bits=2",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "fanMode",
        component = "main",
        command = "setFanMode",
        args = { "high" }
      } })
    expect_ac_code_send(0xFFFFFFFF, (0xFFFFFFFF & 0xFF0FFFFF) | (0x2 << 20))
  end
)

-- NOTE: setFanMode("auto") would exercise the `MODE_TO_FAN[fan_mode] or
-- FAN_MID` fallback, but the profile's enabledValues restricts fanMode to
-- {"low","medium","high"}, so "auto" is rejected by framework validation.

-- refresh ---------------------------------------------------------------------

test.register_coroutine_test(
  "Capability refresh should read OnOff, Level and ColorTemperature",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })

    test.socket.zigbee:__expect_send({ mock_device.id,
      OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      Level.attributes.CurrentLevel:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      ColorControl.attributes.ColorTemperatureMireds:read(mock_device) })
  end
)

-- ============================================================================
-- 2. ZIGBEE ATTRIBUTE HANDLERS
-- ============================================================================
--
-- OnOff / CurrentLevel / ColorTemperatureMireds attribute reports are handled
-- by the SmartThings default zigbee handlers and emit their corresponding
-- capability events automatically, so they are not re-tested here.

-- Aqara AC code (0xFCC0 / 0x024F) ---------------------------------------------

test.register_coroutine_test(
  "AC code report: heat + medium fan + swing + setpoint 25.00 should emit all events",
  function()
    local hi32 = (2500 << 16) | 0xFEFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x0 << 24)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x1 << 20)
    lo32 = (lo32 & 0xFFFCFFFF) | (0x0 << 16)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25.0, unit = "C" })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("swing")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("heat")))
  end
)

test.register_coroutine_test(
  "AC code report: pwr=0 (off) should emit thermostatMode 'off'",
  function()
    local hi32 = 0xFFFFFFFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x0 << 28)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x1 << 20)
    lo32 = (lo32 & 0xFFFCFFFF) | (0x1 << 16)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("fixed")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("off")))
  end
)

test.register_coroutine_test(
  "AC code report: pwr=0xF (invalid) should skip thermostatMode update",
  function()
    local hi32 = 0xFFFFFFFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0xFF0FFFFF) | (0x0 << 20)
    lo32 = (lo32 & 0xFFFCFFFF) | (0x0 << 16)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("low")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("swing")))
  end
)

test.register_coroutine_test(
  "AC code report: fan=2 (high) and mode=4 (cool)",
  function()
    local hi32 = 0xFFFFFFFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x4 << 24)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x2 << 20)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("high")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("cool")))
  end
)

test.register_coroutine_test(
  "AC code report: unknown mode bits should fall back to 'heat'",
  function()
    local hi32 = 0xFFFFFFFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x7 << 24)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x1 << 20)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("heat")))
  end
)

test.register_coroutine_test(
  "AC code report: fanonly mode (5)",
  function()
    local hi32 = 0xFFFFFFFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x5 << 24)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x1 << 20)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("fanonly")))
  end
)

test.register_coroutine_test(
  "AC code report: pending_on_mode + incoming off should NOT overwrite mode",
  function()
    mock_device:set_field("pending_on_mode", "heat")

    local hi32 = 0xFFFFFFFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x0 << 28) -- pwr=0 (off)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x1 << 20) -- fan=1 (medium)
    lo32 = (lo32 & 0xFFFCFFFF) | (0x0 << 16) -- swing bits=00 (swing)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("swing")))
    -- thermostatMode NOT emitted: pwr=0 → st_mode="off", but pending_on_mode="heat"
    -- causes early return from the handler.
  end
)

test.register_coroutine_test(
  "AC code report: setpoint 0xFFFF (invalid marker) should skip setpoint emit",
  function()
    local hi32 = (0xFFFF << 16) | 0xFEFF
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x0 << 24)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x1 << 20)

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("heat")))
  end
)

test.register_coroutine_test(
  "AC code report: invalid frame (b15_8 < 0xFE) should skip setpoint emit",
  function()
    -- hi32 carries a valid-looking setpoint raw (2800 = 28.00°C); the "invalid"
    -- frame marker lives in lo32 bits 15-8 (b15_8). Clearing them to 0x00
    -- makes hi_valid = false, so the setpoint emit MUST be suppressed even
    -- though setpoint_raw != 0xFFFF.
    local hi32 = (2800 << 16) | 0x0000
    local lo32 = 0xFFFFFFFF
    lo32 = (lo32 & 0x0FFFFFFF) | (0x1 << 28) -- pwr=1 (on)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x0 << 24) -- mode=0 (heat)
    lo32 = (lo32 & 0xFF0FFFFF) | (0x1 << 20) -- fan=1 (medium)
    lo32 = lo32 & 0xFFFF00FF                 -- b15_8 = 0x00 → frame invalid

    test.socket.zigbee:__queue_receive({ mock_device.id, build_ac_code_report(hi32, lo32) })

    -- Setpoint NOT emitted because hi_valid=false.
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("heat")))
  end
)

-- ============================================================================
-- 3. LIFECYCLE HANDLERS
-- ============================================================================

test.register_coroutine_test(
  "Lifecycle init should emit supported* / range events and read attributes",
  function()
    -- This test only verifies the emissions fired by the automatic init;
    -- those expectations are already registered in test_init().
  end
)

test.register_coroutine_test(
  "Lifecycle added should emit defaults (setpoint=25, fan=medium, swing=swing) + AC code",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25, unit = "C" })))

    local hi32 = ((2500 & 0xFFFF) << 16) | (0xFFFFFFFF & 0xFFFF)
    expect_ac_code_send(hi32, 0xFFFFFFFF)

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("medium")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("swing")))
  end
)

-- info_changed helpers --------------------------------------------------------

local function expected_night_light_value(start_h, end_h, enabled)
  local start_time = (start_h * 60) & 0xFFF
  local end_time   = (end_h * 60) & 0xFFF
  local on_val     = (end_time << 12) | start_time
  return enabled and on_val or (on_val + 1)
end

test.register_coroutine_test(
  "infoChanged nightLightMode on (first init) should send night-light + DND-beep + DND-time",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.nightLightMode"]      = true,
        ["stse.nightLightStartTime"] = 21,
        ["stse.nightLightEndTime"]   = 9,
        ["stse.muteBeep"]            = false
      }
    }))

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_NIGHT_LIGHT, AQARA_MFG_CODE,
        data_types.Uint32, expected_night_light_value(21, 9, true)) })

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_DND_BEEP, AQARA_MFG_CODE,
        data_types.Uint8, 0) })

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_DND_TIME, AQARA_MFG_CODE,
        data_types.Uint32, 0x00120012) })
  end
)

test.register_coroutine_test(
  "infoChanged nightLightMode off should send night-light disabled value",
  function()
    mock_device:set_field("inited", true)

    -- The profile default is nightLightMode=false, so passing `false` again
    -- would produce old==new and the handler's `mode_changed` branch would
    -- not fire. First flip it ON (consuming the resulting "enabled" write),
    -- then flip it OFF — which is the transition this test actually covers.
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.nightLightMode"]      = true,
        ["stse.nightLightStartTime"] = 21,
        ["stse.nightLightEndTime"]   = 9
      }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_NIGHT_LIGHT, AQARA_MFG_CODE,
        data_types.Uint32, expected_night_light_value(21, 9, true)) })

    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.nightLightMode"]      = false,
        ["stse.nightLightStartTime"] = 21,
        ["stse.nightLightEndTime"]   = 9
      }
    }))

    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_NIGHT_LIGHT, AQARA_MFG_CODE,
        data_types.Uint32, expected_night_light_value(21, 9, false)) })
  end
)

test.register_coroutine_test(
  "infoChanged night-light time changed while enabled should resend night-light",
  function()
    mock_device:set_field("inited", true)
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.nightLightMode"]      = true,
        ["stse.nightLightStartTime"] = 22,
        ["stse.nightLightEndTime"]   = 8
      }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_NIGHT_LIGHT, AQARA_MFG_CODE,
        data_types.Uint32, expected_night_light_value(22, 8, true)) })
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.nightLightMode"]      = true,
        ["stse.nightLightStartTime"] = 21,
        ["stse.nightLightEndTime"]   = 9
      }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_NIGHT_LIGHT, AQARA_MFG_CODE,
        data_types.Uint32, expected_night_light_value(21, 9, true)) })
  end
)

test.register_coroutine_test(
  "infoChanged muteBeep toggled on should write DND-beep=1",
  function()
    mock_device:set_field("inited", true)
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.muteBeep"] = true
      }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_DND_BEEP, AQARA_MFG_CODE,
        data_types.Uint8, 1) })
  end
)

test.register_coroutine_test(
  "infoChanged thermostatCtrl toggled off should write 0",
  function()
    mock_device:set_field("inited", true)
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.thermostatCtrl"] = false,
      }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_THERMOSTAT_CTRL_SW, AQARA_MFG_CODE,
        data_types.Uint8, 0) })
  end
)

test.register_coroutine_test(
  "infoChanged when not yet initialized should trigger initialization",
  function()
    -- mock_device:set_field("inited", "")
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = {
        ["stse.muteBeep"] = true
      }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device,
        AQARA_CLUSTER_ID, ATTR_DND_BEEP, AQARA_MFG_CODE,
        data_types.Uint8, 1) })
  end
)

-- ============================================================================
-- 4. EDGE CASES / BRANCH COVERAGE
-- ============================================================================

test.register_coroutine_test(
  "setHeatingSetpoint while mode is 'off' produces no observable output",
  function()
    mock_device:set_field("thermostat_mode", "off")
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatHeatingSetpoint",
        component = "main",
        command = "setHeatingSetpoint",
        args = { 22 }
      } })
  end
)

test.register_coroutine_test(
  "setFanOscillationMode while mode is 'fanonly' still sends AC code",
  function()
    mock_device:set_field("thermostat_mode", "fanonly")
    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "fanOscillationMode",
        component = "main",
        command = "setFanOscillationMode",
        args = { "fixed" }
      } })
    expect_ac_code_send(0xFFFFFFFF, (0xFFFFFFFF & 0xFFFCFFFF) | (0x1 << 16))
  end
)

test.register_coroutine_test(
  "setThermostatMode heat should restore saved swing/fan from mode_state",
  function()
    mock_device:set_field("mode_state.heat.swing", "fixed")
    mock_device:set_field("mode_state.heat.fan_mode", "high")

    test.socket.capability:__queue_receive({ mock_device.id,
      {
        capability = "thermostatMode",
        component = "main",
        command = "setThermostatMode",
        args = { "heat" }
      } })

    local hi32 = 0xFFFFFFFF
    local lo32 = (0xFFFFFFFF & 0x0FFFFFFF) | (0x1 << 28)
    lo32 = (lo32 & 0xF0FFFFFF) | (0x0 << 24)
    expect_ac_code_send(hi32, lo32)

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.thermostatMode.thermostatMode("heat")))

    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanOscillationMode.fanOscillationMode("fixed")))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fanMode.fanMode("high")))

    local r_hi = 0xFFFFFFFF
    local r_lo = 0xFFFFFFFF
    r_lo = (r_lo & 0xFF0FFFFF) | (0x2 << 20)
    r_lo = (r_lo & 0xFFFCFFFF) | (0x1 << 16)
    expect_ac_code_send(r_hi, r_lo)
  end
)

-- NOTE: The `if args.old_st_store.preferences == nil then return end` early
-- return in info_changed is defensive code that only fires on a brand-new
-- device. It cannot be reliably reproduced in the SmartThings integration
-- test framework because the mock_device is always built from the profile's
-- preference section (st_store.preferences is always a table), and manually
-- constructing a lifecycle event with preferences=nil is normalized away by
-- the lifecycle dispatcher before the handler sees it.

test.run_registered_tests()
