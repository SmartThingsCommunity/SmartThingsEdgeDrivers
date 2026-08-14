local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

-- Use proper UUID format for Hue resource IDs
local CONTACT_RID = "ffffffff-1111-1111-1111-111111111111"
local TAMPER_RID = "ffffffff-2222-2222-2222-222222222222"
local POWER_RID = "ffffffff-3333-3333-3333-333333333333"
local CONTACT_DEVICE_ID = "gggggggg-gggg-gggg-gggg-gggggggggggg"

-- Contact sensor fixture WITH SSE enabled
local mock_bridge, mock_sensor, get_bridge_server, base_test_init, get_sse_connection =
  hue_test_helpers.build_paired_bridge_and_child(
    CONTACT_RID,
    {
      id = CONTACT_RID,
      hue_provided_name = "Hue Contact Sensor",
      hue_device_id = CONTACT_DEVICE_ID,
      contact_report = { state = "contact" },  -- "contact" = closed
      contact_enabled = true,
      tamper_reports = { { state = "not_tampered" } },
      tamper_id = TAMPER_RID,
      power_state = { battery_level = 90 },
      power_id = POWER_RID,
      sensor_list = {
        id = "contact",
        power_id = "device_power",
        tamper_id = "tamper"
      }
    },
    "contact-sensor.yml",
    "contact",
    function(mock_device)
      -- Register expectations for events during init lifecycle (from refresh)
      -- Use relaxed ordering since these can arrive in any order
      test.socket.capability:__set_channel_ordering("relaxed")
      
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.contactSensor.contact.closed())
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      )
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.battery.battery(90))
      )
    end,
    nil,  -- No device template overrides
    { enable_sse = true }
  )

test.set_test_init_function(base_test_init)

--- Helper to connect SSE stream for contact sensor
local function connect_sse_for_contact_sensor()
  local sse, rest = hue_test_helpers.identify_sse_and_rest_connections(
    hue_test_helpers.BRIDGE_IP, 443, get_sse_connection, get_bridge_server
  )
  
  -- Drain the contact sensor's injected refresh REST calls (6 total)
  -- 1. GET device info (for services list)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = CONTACT_DEVICE_ID,
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "contact", rid = CONTACT_RID },
        { rtype = "tamper", rid = TAMPER_RID },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  
  -- 2. GET zigbee_connectivity status
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { owner = { rid = CONTACT_DEVICE_ID }, status = "connected" } },
  })
  
  -- 3. GET device info again (for sensor services)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = CONTACT_DEVICE_ID,
      metadata = { name = "Hue Contact Sensor" },
      services = { 
        { rtype = "zigbee_connectivity", rid = "zigbee-rid-1" },
        { rtype = "contact", rid = CONTACT_RID },
        { rtype = "tamper", rid = TAMPER_RID },
        { rtype = "device_power", rid = POWER_RID }
      }
    } },
  })
  
  -- 4. GET contact data
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = CONTACT_RID,
      type = "contact",
      contact_report = { state = "contact" },
      enabled = true
    } },
  })
  
  -- 5. GET tamper data
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = TAMPER_RID,
      type = "tamper",
      tamper_reports = { { state = "not_tampered" } }
    } },
  })
  
  -- 6. GET device_power data (battery)
  rest:queue_http_response(200, {}, {
    errors = {},
    data = { { 
      id = POWER_RID,
      type = "device_power",
      power_state = { battery_level = 90 }
    } },
  })
  
  test.wait_for_events()
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. CONTACT_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/zigbee_connectivity/zigbee-rid-1")
  rest:assert_http_request_received("GET", "/clip/v2/resource/device/" .. CONTACT_DEVICE_ID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/contact/" .. CONTACT_RID)
  rest:assert_http_request_received("GET", "/clip/v2/resource/tamper/" .. TAMPER_RID)
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
  "SSE connection establishes successfully for contact sensor",
  function()
    local sse, rest = connect_sse_for_contact_sensor()
    
    -- If we got here without errors, SSE connection was established
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE contact open event",
  function()
    local sse = connect_sse_for_contact_sensor()
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "contact",
            id = CONTACT_RID,
            contact_report = {
              state = "no_contact"
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE contact closed event",
  function()
    local sse = connect_sse_for_contact_sensor()
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.closed())
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "contact",
            id = CONTACT_RID,
            contact_report = {
              state = "contact"
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE tamper detected event",
  function()
    local sse = connect_sse_for_contact_sensor()
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "contact",
            id = CONTACT_RID,
            tamper_reports = {
              { state = "tampered" }
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE tamper clear event",
  function()
    local sse = connect_sse_for_contact_sensor()
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "contact",
            id = CONTACT_RID,
            tamper_reports = {
              { state = "not_tampered" }
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE combined update with battery",
  function()
    local sse = connect_sse_for_contact_sensor()
    
    -- Use relaxed ordering since multiple attributes can arrive in any order
    test.socket.capability:__set_channel_ordering("relaxed")
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
    )
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.battery.battery(45))
    )
    
    sse:queue_sse_event({
      {
        type = "update",
        data = {
          {
            type = "contact",
            id = CONTACT_RID,
            power_state = {
              battery_level = 45
            },
            contact_report = {
              state = "no_contact"
            }
          }
        },
      },
    })
    
    test.wait_for_events()
  end
)

test.run_registered_tests()
