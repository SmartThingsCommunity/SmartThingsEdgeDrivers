--- The scans the driver makes once the bridge's event stream connects: the Zigbee connectivity of
--- its devices, followed by a (debounced) scan of its rooms and zones.

local test = require "integration_test"
local hue_test_helpers = require "test.hue_test_helpers"
local http = require "integration_test.connection_scenario_http"

local CONNECTIVITY_PATH = "/clip/v2/resource/zigbee_connectivity"
local ROOM_PATH = "/clip/v2/resource/room"

local fixtures = hue_test_helpers.HueDeviceBuilder.new()
  :with_bridge()
  :enable_sse()
  :start()

local scenario, conns = hue_test_helpers.create_hue_scenario({ sse = true })
local rest, sse = conns.rest, conns.sse

http.expect_sse_handshake(sse, "/eventstream/clip/v2", true)

local function base_test_init()
  fixtures.test_init()
  scenario:activate()
end
test.set_test_init_function(base_test_init)

local CONNECTED = { errors = {}, data = { { owner = { rid = "some-device" }, status = "connected" } } }
local EMPTY = { errors = {}, data = {} }
local FAILED = { errors = { { description = "internal error" } } }

-- The scans start as soon as the driver does, before the test body runs, so each test registers
-- the scan requests it answers itself in test_init, as deferred expectations; the body then answers
-- each attempt in turn. An attempt beyond the ones a test expects is an unexpected request, which
-- fails the test.
local scans

--- Wait for the driver's next scan request, answer it, and return the mock time it was made at.
local function answer_next(response)
  local req = scans:await({ max_turns = 500 })
  local made_at = os.time()
  req:respond(response)
  return made_at
end

--- test_init for a test that answers `times` connectivity scan requests itself.
local function answer_connectivity_scans(times)
  return function()
    base_test_init()
    scans = http.expect_request(rest, "GET", CONNECTIVITY_PATH, { defer = true, times = times })
  end
end

--- test_init for a test that answers `times` room scan requests itself, once the connectivity
--- scan succeeds. (Zone requests are answered by the scenario's defaults.)
local function answer_room_scans(times)
  return function()
    base_test_init()
    http.expect_request(rest, "GET", CONNECTIVITY_PATH, { body = CONNECTED })
    scans = http.expect_request(rest, "GET", ROOM_PATH, { defer = true, times = times })
  end
end

test.register_coroutine_test(
  "a failed connectivity scan is retried after a backoff, not immediately",
  function()
    local first = answer_next({ status = 500, body = FAILED })
    answer_next({ status = 500, body = FAILED })
    local third = answer_next({ body = CONNECTED })
    -- The driver's backoff starts at 0s (plus up to 0.5s of jitter) and grows from there.
    assert(third > first, string.format(
      "expected the driver to back off between attempts, but all three were made at t=%s", first))
  end,
  { test_init = answer_connectivity_scans(3) }
)

test.register_coroutine_test(
  "a failed room scan is retried after a backoff, not immediately",
  function()
    local first = answer_next({ status = 500, body = FAILED })
    answer_next({ status = 500, body = FAILED })
    local third = answer_next({ body = EMPTY })
    assert(third > first, string.format(
      "expected the driver to back off between attempts, but all three were made at t=%s", first))
  end,
  { test_init = answer_room_scans(3) }
)

test.run_registered_tests()
