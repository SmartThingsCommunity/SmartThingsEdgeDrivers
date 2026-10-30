-- Use case 3b: an already-added player is rediscovered at a new IP.
local helpers = require "test.review_lan_helpers"
local test = require "integration_test"
local capabilities = require "st.capabilities"

local NEW_IP = "192.168.1.60"
local ctx = helpers.new_context({ rescan_timer = true })
local scenario2, rest2, ws2 = helpers.create_scenario(NEW_IP)
helpers.register_standard_expectations(rest2, ws2, { ip = NEW_IP })

test.set_test_init_function(function()
  ctx.init()
  scenario2:activate()
end)

local function rediscover()
  ctx.bring_up()
  local searches = #ctx.ssdp:sent()
  test.wait_until(function() return #ctx.ssdp:sent() > searches end,
    { message = "the 10 minute SSDP rescan", max_turns = 200 })
  ctx.ssdp:reply(helpers.ssdp_reply({ ip = NEW_IP }), { from_host = NEW_IP, from_port = 1900 })
  test.wait_until(function() return rest2:connection_count() >= 2 end,
    { message = "REST info + groups at the new IP", max_turns = 100 })
end

test.register_coroutine_test("rediscovery at a new IP queries the new address", function()
  rediscover()
  assert(rest2:connection_count() >= 2)
end)

-- Characterises the driver's behaviour: nothing reconnects by itself after the old socket drops (the
-- stopped SonosConnection has no keepalive), but the next refresh command re-opens the websocket
-- at the new IP.
test.register_coroutine_test("after rediscovery at a new IP, a refresh command opens the websocket there", function()
  rediscover()
  ctx.ws:close_connection()
  test.wait_for_events()
  test.wait_for_events()
  assert(not ws2:was_opened(), "driver reconnected by itself (behaviour changed?)")
  test.socket.capability:__queue_receive({ ctx.device.id,
    { capability = "refresh", command = "refresh", args = {}, component = "main" } })
  test.wait_until(function() return ws2:was_opened() end,
    { message = "a websocket connection to the new IP after refresh", max_turns = 200 })
  test.wait_until(ctx.is_online, { message = "online" })
end)

test.run_registered_tests()
