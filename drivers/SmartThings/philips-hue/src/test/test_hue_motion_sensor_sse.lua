local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

-- Use proper UUID format for Hue resource IDs
local MOTION_RID = "dddddddd-1111-1111-1111-111111111111"
local TEMP_RID = "dddddddd-2222-2222-2222-222222222222"
local LIGHT_RID = "dddddddd-3333-3333-3333-333333333333"
local POWER_RID = "dddddddd-4444-4444-4444-444444444444"
local MOTION_DEVICE_ID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
local ZIGBEE_RID = "zigbee-rid-1"

-- Motion sensor fixture WITH SSE enabled
local mock_bridge, mock_sensor, get_bridge_server, base_test_init, get_sse_connection =
  hue_test_helpers.HueDeviceBuilder.new()
    :with_bridge()
    :with_motion(MOTION_RID, {
      battery = 95,
      motion = false,
      temperature = 20.0,
      light_level = 30000,  -- ~1000 lux
      device_id = MOTION_DEVICE_ID,
      power_rid = POWER_RID,
      temperature_rid = TEMP_RID,
      light_level_rid = LIGHT_RID,
    })
    :enable_sse()
    :start()

-- Set up ConnectionScenario for this host:port
local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(base_test_init, scenario)

-- 1. GET device info (reusable: may be called multiple times during refresh)
hue_test_helpers.expect_device_info(rest, MOTION_DEVICE_ID, {
  { rtype = "zigbee_connectivity", rid = ZIGBEE_RID },
  { rtype = "motion", rid = MOTION_RID },
  { rtype = "temperature", rid = TEMP_RID },
  { rtype = "light_level", rid = LIGHT_RID },
  { rtype = "device_power", rid = POWER_RID }
}, {
  name = "Hue Motion Sensor",
  reusable = true
})

-- 2. GET zigbee connectivity
hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID)

-- 3. GET motion sensor info
hue_test_helpers.expect_motion_resource(rest, MOTION_RID, false)

-- 4. GET temperature info
hue_test_helpers.expect_temperature_resource(rest, TEMP_RID, 20.0)

-- 5. GET light level info
hue_test_helpers.expect_light_level_resource(rest, LIGHT_RID, 30000)

-- 6. GET device power
hue_test_helpers.expect_device_power(rest, POWER_RID, 95)

-- 7. SSE handshake and connectivity poll
hue_test_helpers.setup_sse_expectations(sse, rest)

test.register_coroutine_test(
  "SSE connection establishes successfully for motion sensor",
  function()
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE motion active event",
  function()
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.motion_event(MOTION_RID, true) })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE motion inactive event",
  function()
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.motion_event(MOTION_RID, false) })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE temperature update event",
  function()
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 22.5, unit = "C" }))
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.temperature_event(TEMP_RID, 22.5) })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE illuminance update event",
  function()
    -- Hue light level formula: 10000*log10(lux) + 1
    -- For ~500 lux: light_level = 27000 → actual lux = round(10^((27000-1)/10000)) = 501
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(501))
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.light_level_event(LIGHT_RID, 27000) })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE combined update with multiple attributes",
  function()
    -- Use relaxed ordering since multiple attributes can arrive in any order
    test.socket.capability:__set_channel_ordering("relaxed")
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.battery.battery(50))
    )
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 18.0, unit = "C" }))
    )
    
    -- Motion sensors can send updates with multiple service types
    http.queue_sse_event(sse, { hue_test_helpers.motion_event(MOTION_RID, true, {
      battery_level = 50,
      temperature = 18.0
    }) })
    
    test.wait_for_events()
  end
)

test.run_registered_tests()
