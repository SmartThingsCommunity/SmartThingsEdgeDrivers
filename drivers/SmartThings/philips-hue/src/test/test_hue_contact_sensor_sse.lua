local test = require "integration_test"
local capabilities = require "st.capabilities"
local hue_test_helpers = require "test.hue_test_helpers"
local Fields = require "fields"

local http = require "integration_test.connection_scenario_http"

-- Use proper UUID format for Hue resource IDs
local CONTACT_RID = "ffffffff-1111-1111-1111-111111111111"
local TAMPER_RID = "ffffffff-2222-2222-2222-222222222222"
local POWER_RID = "ffffffff-3333-3333-3333-333333333333"
local CONTACT_DEVICE_ID = "gggggggg-gggg-gggg-gggg-gggggggggggg"
local ZIGBEE_RID = "zigbee-rid-1"

-- Contact sensor fixture WITH SSE enabled
local mock_bridge, mock_sensor, get_bridge_server, base_test_init, get_sse_connection =
  hue_test_helpers.HueDeviceBuilder.new()
    :with_bridge()
    :with_contact(CONTACT_RID, {
      battery = 90,
      contact_state = "contact",  -- "contact" = closed
      tamper = "not_tampered",
      device_id = CONTACT_DEVICE_ID,
      power_rid = POWER_RID,
      tamper_rid = TAMPER_RID,
    })
    :enable_sse()
    :start()

-- Set up ConnectionScenario for this host:port
local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

-- Setup test init with scenario activation
hue_test_helpers.setup_scenario_test_init(base_test_init, scenario)

-- 1. GET device info (reusable: may be called multiple times during refresh)
hue_test_helpers.expect_device_info(rest, CONTACT_DEVICE_ID, {
  { rtype = "zigbee_connectivity", rid = ZIGBEE_RID },
  { rtype = "contact", rid = CONTACT_RID },
  { rtype = "tamper", rid = TAMPER_RID },
  { rtype = "device_power", rid = POWER_RID }
}, {
  name = "Hue Contact Sensor",
  reusable = true
})

-- 2. GET zigbee connectivity
hue_test_helpers.expect_zigbee_connectivity(rest, ZIGBEE_RID)

-- 3. GET contact sensor info
hue_test_helpers.expect_contact_resource(rest, CONTACT_RID, "contact")

-- 4. GET tamper info
hue_test_helpers.expect_tamper_resource(rest, TAMPER_RID, "not_tampered")

-- 5. GET device power
hue_test_helpers.expect_device_power(rest, POWER_RID, 90)

-- 6. SSE handshake and connectivity poll
hue_test_helpers.setup_sse_expectations(sse, rest)

test.register_coroutine_test(
  "SSE connection establishes successfully for contact sensor",
  function()
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE contact open event",
  function()
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.contact_event(CONTACT_RID, "no_contact") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE contact closed event",
  function()
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.closed())
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.contact_event(CONTACT_RID, "contact") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE tamper detected event",
  function()
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.tamper_event(TAMPER_RID, "tampered") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE tamper clear event",
  function()
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.tamper_event(TAMPER_RID, "not_tampered") })
    
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "SSE combined update with battery",
  function()
    -- Use relaxed ordering since multiple attributes can arrive in any order
    test.socket.capability:__set_channel_ordering("relaxed")
    
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.contactSensor.contact.open())
    )
    test.socket.capability:__expect_send(
      mock_sensor:generate_test_message("main", capabilities.battery.battery(45))
    )
    
    http.queue_sse_event(sse, { hue_test_helpers.contact_event(CONTACT_RID, "no_contact", {
      battery_level = 45
    }) })
    
    test.wait_for_events()
  end
)

test.run_registered_tests()
