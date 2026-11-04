-- Use case 2: websocket closed by the device / player unreachable, driver goes offline and reconnects.
local helpers = require "test.review_lan_helpers"
local test = require "integration_test"
local mock_devices_api = require "integration_test.mock_devices_api"

local ctx = helpers.new_context()
test.set_test_init_function(ctx.init)

local function history() return mock_devices_api.__get_device_status_history(ctx.device.id) end

local function count_subscribes(conn, which)
  local n = 0
  local sent = conn:connection(which):sent()
  local frames = helpers.decode_client_frames(sent:sub(sent:find("\r\n\r\n", 1, true) + 4))
  for _, f in ipairs(frames) do
    if f.payload:find('"subscribe"', 1, true) then n = n + 1 end
  end
  return n
end

test.register_coroutine_test("TCP close by the player: offline, then reconnects and resubscribes", function()
  ctx.bring_up()
  assert(ctx.ws:connection_count() == 1)
  mock_devices_api.__clear_device_status_history()

  ctx.ws:close_connection()
  test.wait_until(function() return ctx.ws:connection_count() == 2 and ctx.is_online() end,
    { message = "a second websocket connection and the device online again", max_turns = 200 })
  test.wait_for_events()

  local h = history()
  assert(h[1] == false and h[#h] == true, "expected offline then online, got ")
  assert(count_subscribes(ctx.ws, 2) == 7, "subscriptions re-sent on the new connection")
end)

test.register_coroutine_test("WebSocket Close frame from the player: offline, then reconnects", function()
  ctx.bring_up()
  mock_devices_api.__clear_device_status_history()
  ctx.ws:queue_bytes(helpers.ws_close(1001, "going away"))
  -- Per RFC 6455 the driver echoes the Close and then the server drops the TCP connection.
  test.wait_until(function()
    local sent = ctx.ws:connection(1):sent()
    local frames = helpers.decode_client_frames(sent:sub(sent:find("\r\n\r\n", 1, true) + 4))
    for _, f in ipairs(frames) do if f.opcode == 0x8 then return true end end
  end, { message = "the driver's Close echo" })
  ctx.ws:close_connection()
  test.wait_until(function() return ctx.ws:connection_count() == 2 and ctx.is_online() end,
    { message = "reconnect after Close frame", max_turns = 200 })
  test.wait_for_events()
  assert(mock_devices_api.__count_device_status_calls(ctx.device.id, false) >= 1, "was marked offline")
  -- the driver answers a Close frame with its own (masked) Close frame
  local sent = ctx.ws:connection(1):sent()
  local frames = helpers.decode_client_frames(sent:sub(sent:find("\r\n\r\n", 1, true) + 4))
  local saw_close
  for _, f in ipairs(frames) do if f.opcode == 0x8 then saw_close = true end end
  assert(saw_close, "driver did not echo a Close frame")
end)

test.register_coroutine_test("player unreachable: stays offline with connects refused, recovers when it returns", function()
  ctx.bring_up()
  mock_devices_api.__clear_device_status_history()
  ctx.scenario:fail_connects(math.huge, "connection refused")
  ctx.ws:close_connection()
  test.wait_until(function() return ctx.is_online() == false end, { message = "offline", max_turns = 100 })
  -- let the backoff loop try (and fail) a few times
  for _ = 1, 5 do
    test.mock_time.advance_time(30)
    test.wait_for_events()
  end
  assert(ctx.is_online() == false, "still offline while refusing connections")
  assert(ctx.ws:connection_count() == 1, "no new websocket connection while refused")
  ctx.scenario:clear_connect_failures()
  for _ = 1, 4 do
    test.mock_time.advance_time(30)
    test.wait_for_events()
    if ctx.is_online() then break end
  end
  test.wait_until(ctx.is_online, { message = "online again after the player returns", max_turns = 200 })
  assert(ctx.ws:connection_count() == 2)
end)

test.run_registered_tests()
