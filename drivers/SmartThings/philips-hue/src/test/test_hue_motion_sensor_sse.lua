local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

-- Use proper UUID format for Hue resource IDs
local MOTION_RID = "dddddddd-1111-1111-1111-111111111111"
local TEMP_RID = "dddddddd-2222-2222-2222-222222222222"
local LIGHT_RID = "dddddddd-3333-3333-3333-333333333333"
local POWER_RID = "dddddddd-4444-4444-4444-444444444444"
local MOTION_DEVICE_ID = "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"

-- Motion sensor fixture WITH SSE enabled
local mock_bridge, mock_sensor, get_bridge_server, base_test_init, get_sse_connection =
  hue_test_helpers.build_paired_bridge_and_child(
    MOTION_RID,
    {
      id = MOTION_RID,
      hue_provided_name = "Hue Motion Sensor",
      hue_device_id = MOTION_DEVICE_ID,
      motion = { motion = false, motion_valid = true },
      motion_enabled = true,
      temperature = { temperature = 20.0, temperature_valid = true },
      temperature_id = TEMP_RID,
      temperature_enabled = true,
      light = { light_level = 30000, light_level_valid = true }, -- ~1000 lux
      light_level_id = LIGHT_RID,
      light_level_enabled = true,
      power_state = { battery_level = 95 },
      power_id = POWER_RID,
      sensor_list = {
        id = "motion",
        power_id = "device_power",
        temperature_id = "temperature",
        light_level_id = "light_level"
      }
    },
    "motion-sensor.yml",
    "motion",
    function(mock_device)
      -- Register expectations for events during init lifecycle (from refresh)
      -- Use relaxed ordering since these can arrive in any order
      test.socket.capability:__set_channel_ordering("relaxed")
      
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 20.0, unit = "C" }))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(1000))
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.battery.battery(95))
      )
    end,
    nil,  -- No device template overrides
    { enable_sse = true }
  )

test.set_test_init_function(base_test_init)

--- Helper to connect SSE stream for motion sensor
local function connect_sse_for_motion_sensor()
  local sse, rest = hue_test_helpers.identify_sse_and_rest_connections(
    hue_test_helpers.BRIDGE_IP, 443, get_sse_connection, get_bridge_server
  )
  
  -- Drain the motion sensor's injected refresh REST calls (7 total)
  -- 1. GET device info (for services list)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = MOTION_DEVICE_ID,
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "motion", rid = MOTION_RID },
        { rtype = "temperature", rid = TEMP_RID },
        { rtype = "light_level", rid = LIGHT_RID },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  
  -- 2. GET zigbee_connectivity status
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = MOTION_DEVICE_ID }, status = "connected" } },
  })
  
  -- 3. GET device info again (for sensor services)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = MOTION_DEVICE_ID,
      metadata = { name = "Hue Motion Sensor" },
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "motion", rid = MOTION_RID },
        { rtype = "temperature", rid = TEMP_RID },
        { rtype = "light_level", rid = LIGHT_RID },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  
  -- 4. GET motion data
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = MOTION_RID,
      type = "motion",
      motion = { motion = false, motion_valid = true },
      enabled = true
    } },
  })
  
  -- 5. GET temperature data
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = TEMP_RID,
      type = "temperature",
      temperature = { temperature = 20.0, temperature_valid = true },
      enabled = true
    } },
  })
  
  -- 6. GET light_level data
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = LIGHT_RID,
      type = "light_level",
      light = { light_level = 30000, light_level_valid = true }, -- ~1000 lux
      enabled = true
    } },
  })
  
  -- 7. GET device_power data (battery)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = POWER_RID,
      type = "device_power",
      power_state = { battery_level = 95 }
    } },
  })
  
  test.wait_for_events()
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. MOTION_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/zigbee_connectivity/zigbee-rid-1")
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. MOTION_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/motion/" .. MOTION_RID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/temperature/" .. TEMP_RID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/light_level/" .. LIGHT_RID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/device_power/" .. POWER_RID)
  
  -- Answer SSE handshake
  sse:assert_http_request_received("GET", "/eventstream/clip/v2", {
    headers = { accept = "text/event-stream" },
  })
  sse:queue_sse_headers(200)
  test.wait_for_events()
  
  -- Answer onopen connectivity poll
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = "unrelated-device" }, status = "connected" } },
  })
  test.wait_for_events()
  rest:assert_http_request_received("GET", "/clip/v2/resource/zigbee_connectivity")
  test.wait_for_events()
  
  return sse, rest
end

test.register_coroutine_test(
  "SSE connection establishes successfully for motion sensor",
  function()
    local sse, rest = connect_sse_for_motion_sensor()
    
    -- If we got here without errors, SSE connection was established
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE motion active event",
  function()
    local sse = connect_sse_for_motion_sensor()
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.active())
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "motion",
            id = MOTION_RID,
            motion = {
              motion = true,
              motion_valid = true
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE motion inactive event",
  function()
    local sse = connect_sse_for_motion_sensor()
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.motionSensor.motion.inactive())
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "motion",
            id = MOTION_RID,
            motion = {
              motion = false,
              motion_valid = true
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE temperature update event",
  function()
    local sse = connect_sse_for_motion_sensor()
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 22.5, unit = "C" }))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "temperature",
            id = TEMP_RID,
            temperature = {
              temperature = 22.5,
              temperature_valid = true
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE illuminance update event",
  function()
    local sse = connect_sse_for_motion_sensor()
    
    -- Hue light level formula: 10000*log10(lux) + 1
    -- For ~500 lux: light_level = 27000 → actual lux = round(10^((27000-1)/10000)) = 501
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance(501))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "light_level",
            id = LIGHT_RID,
            light = {
              light_level = 27000,
              light_level_valid = true
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE combined update with multiple attributes",
  function()
    local sse = connect_sse_for_motion_sensor()
    
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
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "motion",
            id = MOTION_RID,
            power_state = {
              battery_level = 50
            },
            motion = {
              motion = true,
              motion_valid = true
            },
            temperature = {
              temperature = 18.0,
              temperature_valid = true
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.run_registered_tests()
