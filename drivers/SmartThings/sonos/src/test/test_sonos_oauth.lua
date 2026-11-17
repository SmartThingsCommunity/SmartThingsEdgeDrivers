-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

--- How the Sonos driver authenticates to a player: which API key it uses, when it sends the
--- hub's OAuth token and when it asks for one, and what it does when a player turns it away.
---
--- A player is reached with one of two API keys (S1 and S2/OAuth). The hub's environment channel
--- reports whether the Sonos account is linked (`endpointAppInfo`) and delivers the OAuth token
--- (`sonosOAuthToken`) as augmented driver store updates; the driver asks the hub for a token with
--- `st.security`'s `get_secret`, which the tests replace to record those requests. A player that
--- needs authorization answers with a Sonos `ERROR_NOT_AUTHORIZED` global error.

-- These tests use the integration test framework's LAN support, new in lua_libs API version 23.
-- With older lua_libs, skip the file rather than fail loading it.
if require("version").api < 23 then return end

local test = require "integration_test"
local capabilities = require "st.capabilities"
local json = require "st.json"
local helpers = require "test.sonos_test_helpers"
local http = require "integration_test.connection_scenario_http"
local mock_devices_api = test.mock_devices_api

-- The API keys sonos_test_helpers supplies for the driver's `app_key` module.
local S1_KEY = "test-s1-key"
local OAUTH_KEY = "test-oauth-key"

local GROUPS_PATH = "/api/v1/households/" .. helpers.HOUSEHOLD .. "/groups"

local fixture = helpers.new_fixture()

-- What the driver asked the hub's security API for: `{ kind = secret_kind, time = os.time() }`.
local secret_requests
-- Whether the hub's security API accepts a request; set it to false to make the driver's requests fail.
local secrets_available

local function test_init(init_opts)
  secret_requests, secrets_available = {}, true
  -- `st.security` is a stub in the test environment; give it the one function the driver calls.
  _G._envlibrequire("security").get_secret = function(kwargs_json)
    table.insert(secret_requests, { kind = json.decode(kwargs_json).secret_kind, time = os.time() })
    if secrets_available then return {} end
    return nil, "the hub refused the request"
  end
  fixture.test_init(init_opts)
end
test.set_test_init_function(test_init)

--#region The hub's account-linking state

--- Deliver an update of the hub's augmented driver store to the driver.
local function upsert(key, value)
  local data = json.encode(value)
  test.socket.environment_update:__queue_receive({
    "augmentDriverStore",
    { kind = "Upsert", payload = { data_key = key, data_value = { data:byte(1, -1) } } },
  })
  test.wait_for_events()
end

--- The hub removes an entry of the augmented driver store.
local function delete(key)
  test.socket.environment_update:__queue_receive({
    "augmentDriverStore",
    { kind = "Delete", payload = { data_key = key, data_value = {} } },
  })
  test.wait_for_events()
end

--- The linked Sonos account's state: "connected" or "disconnected".
local function set_account_state(state)
  upsert("endpointAppInfo", { state = state })
end

--- The OAuth token the hub delivers, valid for `lifetime` seconds (default an hour).
local function deliver_token(lifetime, access_token)
  -- The hub's os.time() is a whole number of seconds, but mock time is fractional once the driver
  -- has slept for a randomized backoff, and the token refresher's `%d` formatting of the time to
  -- the token's expiry fails on that. Deliver the token on a whole second, as on a hub.
  if os.time() % 1 ~= 0 then test.let_time_pass(math.ceil(os.time()) - os.time()) end
  upsert("sonosOAuthToken", {
    accessToken = access_token or "tok-1",
    expiresAt = (os.time() + (lifetime or 3600)) * 1000,
  })
end

--- Link the account the way a user does: the hub reports it connected, and then delivers a token
--- (the driver asks for one as soon as it sees the account connected).
local function link_account(lifetime, access_token)
  set_account_state("connected")
  deliver_token(lifetime, access_token)
end

--- An account that was linked before: the hub has its token, and reports the account connected.
--- The driver has a valid token from the start, so it doesn't ask for one.
local function have_linked_account(lifetime, access_token)
  deliver_token(lifetime, access_token)
  set_account_state("connected")
end

local function secret_kinds()
  local kinds = {}
  for _, request in ipairs(secret_requests) do table.insert(kinds, request.kind) end
  return kinds
end

--#endregion

--#region The player

--- The player answers a groups request that matches `request_headers` with a 401
--- ERROR_NOT_AUTHORIZED, as a player does that doesn't accept the credentials it was given.
--- Requests that don't match are answered as usual.
local function reject_groups_requests(request_headers)
  http.expect_request_for_test(fixture.rest, "GET", GROUPS_PATH, {
    status = 401,
    body = { _objectType = "globalError", errorCode = "ERROR_NOT_AUTHORIZED", reason = "no valid credentials" },
    request_headers = request_headers,
    reusable = true,
  })
end

local function reject_api_key(api_key)
  reject_groups_requests({ ["x-sonos-api-key"] = api_key })
end

--- A player that needs the hub's token: it turns away every groups request that doesn't carry one,
--- or, with `api_key`, those that use that key and don't carry one.
local function require_token(api_key)
  reject_groups_requests({
    ["x-sonos-api-key"] = api_key or function() return true end,
    authorization = function(value) return value == nil, "it carries a token" end,
  })
end

--- The player answers the driver's first SSDP search.
local function find_player()
  test.wait_until(function() return #fixture.ssdp:sent() > 0 end, { within = 10, message = "the driver's M-SEARCH" })
  fixture.ssdp:reply(helpers.ssdp_reply(), { from_host = helpers.PLAYER_IP })
end

--- The API key the driver sent in its latest websocket upgrade request.
local function websocket_api_key()
  local upgrade = http.parse_request(fixture.ws:connection():sent())
  return upgrade.headers["x-sonos-api-key"]
end

--- The values of a header on every groups request the driver sent.
local function groups_request_headers(name)
  local values = {}
  for _, request in ipairs(http.find_requests(fixture.rest, "GET", GROUPS_PATH)) do
    table.insert(values, request.headers[name] or false)
  end
  return values
end

--- Assert that every Sonos message the driver sent on its websocket carried `expected` as its authorization.
local function assert_ws_messages_authorized_with(expected)
  local messages = helpers.sent_ws_messages(fixture.ws)
  assert(#messages > 0, "expected the driver to have sent messages on its websocket")
  for _, message in ipairs(messages) do
    assert(message.header.authorization == expected, string.format("expected %s.%s to carry authorization %s, got %s",
      message.header.namespace, message.header.command, tostring(expected), tostring(message.header.authorization)))
  end
end

local function was_online_ever()
  for _, online in ipairs(mock_devices_api.__get_device_status_history(fixture.device.id)) do
    if online then return true end
  end
  return false
end

--#endregion

--#region API keys

test.register_coroutine_test(
  "a player that accepts only the S2 (OAuth) API key is connected to with that key",
  function()
    reject_api_key(S1_KEY)
    fixture.bring_up()
    assert(websocket_api_key() == OAUTH_KEY, "expected the websocket upgrade to use the OAuth key, got " .. tostring(websocket_api_key()))
    assert(#secret_requests == 0, "a player the driver can authenticate to needs no token")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a player that accepts only the S1 API key is connected to with that key",
  function()
    reject_api_key(OAUTH_KEY)
    fixture.bring_up()
    assert(websocket_api_key() == S1_KEY, "expected the websocket upgrade to use the S1 key, got " .. tostring(websocket_api_key()))
    assert(#secret_requests == 0, "a player the driver can authenticate to needs no token")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a valid token is sent with the OAuth key on every request, without probing the player for a working key",
  function()
    have_linked_account()
    fixture.bring_up()
    assert(websocket_api_key() == OAUTH_KEY, "expected the websocket upgrade to use the OAuth key, got " .. tostring(websocket_api_key()))
    local groups = http.find_requests(fixture.rest, "GET", GROUPS_PATH)
    assert(#groups > 0, "expected the driver to request the player's groups")
    for _, request in ipairs(groups) do
      assert(request.headers["x-sonos-api-key"] == OAUTH_KEY, "groups request with key " .. tostring(request.headers["x-sonos-api-key"]))
      assert(request.headers["authorization"] == "Bearer tok-1", "groups request with authorization " .. tostring(request.headers["authorization"]))
    end
    assert_ws_messages_authorized_with("Bearer tok-1")
    assert(#secret_requests == 0, "a valid token needs no new one")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "an S1 player is connected to with the S1 key, without trying the OAuth key",
  function()
    local info = helpers.player_info()
    info.device.swGen = 1
    http.expect_request_for_test(fixture.rest, "GET", "/api/v1/players/local/info", { body = info, reusable = true })

    fixture.expect_event(capabilities["stus.softwareGeneration"].generation("1"))
    fixture.expect_event(capabilities.mediaGroup.groupRole("ungrouped"))
    fixture.expect_event(capabilities.mediaGroup.groupPrimaryDeviceId(helpers.PLAYER_ID))
    find_player()
    test.wait_until(fixture.is_online, { within = 30, message = "the device online" })
    test.wait_for_events()

    assert(websocket_api_key() == S1_KEY, "expected the websocket upgrade to use the S1 key, got " .. tostring(websocket_api_key()))
    for _, value in ipairs(groups_request_headers("x-sonos-api-key")) do
      assert(value == S1_KEY, "groups request with key " .. tostring(value))
    end
  end,
  { min_api_version = 23 }
)

--#endregion

--#region A player that turns the driver away

--- A device whose player needs the hub's token stays offline while the driver has none, asks
--- the hub for one, and comes online using it once it arrives.
local function test_player_needing_a_token(name, arrange)
  test.register_coroutine_test(
    name,
    function()
      arrange()
      find_player()
      test.let_time_pass(120)

      assert(not was_online_ever(), "the device should not go online without credentials the player accepts")
      assert(fixture.ws:connection_count() == 0, "the driver should not open a websocket the player won't accept")
      assert(table.concat(secret_kinds(), ",") == "sonos_oauth",
        "expected the driver to ask for a token once, got: " .. table.concat(secret_kinds(), ","))

      fixture.expect_player_events()
      link_account(3600, "tok-new")
      test.wait_until(fixture.is_online, { within = 30, message = "the device online" })
      test.wait_for_events()
      assert(websocket_api_key() == OAUTH_KEY, "expected the websocket upgrade to use the OAuth key, got " .. tostring(websocket_api_key()))
      assert_ws_messages_authorized_with("Bearer tok-new")
    end,
    { min_api_version = 23 }
  )
end

-- With OAuth forced the driver uses only the OAuth key, even if the player would take the S1 key.
test_player_needing_a_token("a device whose account must be linked stays offline and asks for a token, and goes online once it has one",
  function()
    upsert("force_oauth", true)
    require_token(OAUTH_KEY)
  end)

test_player_needing_a_token("a player that rejects every API key keeps its device offline and asks for a token, and goes online once it has one",
  function() require_token() end)

test.register_coroutine_test(
  "a new player that turns the driver away gets its device once a token arrives",
  function()
    require_token()
    find_player()
    -- Creating a device for a player the driver can't authenticate to would be an unexpected
    -- create, which fails the test.
    test.let_time_pass(120)

    local created = mock_devices_api.__expect_create_device({
      type = "LAN",
      deviceNetworkId = helpers.MAC,
      label = "Kitchen",
      profileReference = "sonos-player",
      manufacturer = "Sonos",
      model = "Sonos One",
      vendorProvidedLabel = "sonos-one",
    }, {
      adopt = {
        profile = helpers.profile(),
        on_created = function(device)
          fixture.expect_init_events(device)
          fixture.expect_player_events(device)
        end,
      },
    })
    local searches = #fixture.ssdp:sent()
    link_account(3600, "tok-new")
    test.wait_until(function() return created.device ~= nil end, { within = 30, message = "the device being created" })
    test.wait_until(function() return #fixture.ssdp:sent() > searches end,
      { within = 30, message = "the new device's search for its player" })
    fixture.ssdp:reply(helpers.ssdp_reply(), { from_host = helpers.PLAYER_IP })
    test.wait_until(function() return fixture.is_online(created.device) end, { within = 30, message = "the new device online" })
    test.wait_for_events()
    assert(websocket_api_key() == OAUTH_KEY, "expected the websocket upgrade to use the OAuth key, got " .. tostring(websocket_api_key()))
  end,
  { min_api_version = 23, test_init = function() test_init({ no_device = true }) end }
)

--#endregion

--#region A player that revokes the driver's authorization on its websocket

--- The player tells the driver on its websocket that it is no longer authorized.
local function push_not_authorized()
  fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("globalError"), { errorCode = "ERROR_NOT_AUTHORIZED" }))
end

test.register_coroutine_test(
  "a player that revokes the websocket's authorization takes the device offline and asks for a token, and the driver reconnects when the player accepts it again",
  function()
    fixture.bring_up()
    mock_devices_api.__clear_device_status_history()

    push_not_authorized()
    test.wait_until(function() return fixture.ws:connection_count() == 2 and fixture.is_online() end,
      { within = 90, message = "a second websocket connection and the device online again" })
    test.wait_for_events()

    local history = mock_devices_api.__get_device_status_history(fixture.device.id)
    assert(history[1] == false and history[#history] == true,
      "expected the device to go offline and then online again, got " .. #history .. " status calls")
    assert(table.concat(secret_kinds(), ",") == "sonos_oauth",
      "expected the driver to ask for a token once, got: " .. table.concat(secret_kinds(), ","))
  end,
  { min_api_version = 23 }
)

-- However the player ends the driver's websocket, if it then turns the driver away on the
-- reconnect, the device stays offline and the driver asks for a token and waits for it.
local ways_to_lose_the_websocket = {
  { name = "revokes the websocket's authorization", lose = push_not_authorized },
  { name = "drops the websocket", lose = function() fixture.ws:close_connection() end },
}

for _, way in ipairs(ways_to_lose_the_websocket) do
  test.register_coroutine_test(
    "a player that " .. way.name .. " and turns the driver away on the reconnect keeps the device offline until a token arrives",
    function()
      fixture.bring_up()
      mock_devices_api.__clear_device_status_history()

      require_token()
      way.lose()
      test.wait_until(function() return fixture.is_online() == false end, { within = 10, message = "the device offline" })
      test.let_time_pass(120)
      assert(fixture.ws:connection_count() == 1, "the driver should not reconnect to a player that won't accept it")
      assert(fixture.is_online() == false, "the device should stay offline")
      assert(table.concat(secret_kinds(), ",") == "sonos_oauth",
        "expected the driver to ask for a token once, got: " .. table.concat(secret_kinds(), ","))

      link_account(3600, "tok-new")
      test.wait_until(function() return fixture.ws:connection_count() == 2 and fixture.is_online() end,
        { within = 90, message = "a second websocket connection and the device online again" })
      test.wait_for_events()
      assert(websocket_api_key() == OAUTH_KEY, "expected the new websocket upgrade to use the OAuth key, got " .. tostring(websocket_api_key()))
      local messages = helpers.sent_ws_messages(fixture.ws, 2)
      assert(#messages == 7, "expected the 7 subscriptions again on the new connection")
      for _, message in ipairs(messages) do
        assert(message.header.authorization == "Bearer tok-new", "subscription " .. message.header.namespace
          .. " carried authorization " .. tostring(message.header.authorization))
      end
    end,
    { min_api_version = 23 }
  )
end

test.register_coroutine_test(
  "a websocket error other than not-authorized leaves the device online",
  function()
    fixture.bring_up()
    mock_devices_api.__clear_device_status_history()

    fixture.ws:queue_bytes(helpers.ws_json(helpers.push_header("globalError"), { errorCode = "ERROR_RESOURCE_NOT_FOUND" }))
    test.let_time_pass(120)
    assert(#mock_devices_api.__get_device_status_history(fixture.device.id) == 0, "the device's status should not change")
    assert(fixture.ws:connection_count() == 1, "the driver should keep its websocket")
    assert(#secret_requests == 0, "the driver should not ask for a token")
  end,
  { min_api_version = 23 }
)

--#endregion

--#region A player whose REST API fails

-- Ways a player fails to answer a groups request that are not a rejection of the driver's credentials.
local failures = {
  { name = "a non-JSON error response", response = { status = 500, body = "internal error" } },
  { name = "a Sonos error other than not-authorized",
    response = { status = 500, body = { _objectType = "globalError", errorCode = "ERROR_INTERNAL" } } },
}

for _, failure in ipairs(failures) do
  test.register_coroutine_test(
    "a player that answers with " .. failure.name .. " is not taken for one that turned the driver away: its device stays offline and no token is requested, until the player recovers",
    function()
      local failing = true
      local spec = { reusable = true, request_headers = {
        ["x-sonos-api-key"] = function() return failing, "the player has recovered" end,
      } }
      for k, v in pairs(failure.response) do spec[k] = v end
      http.expect_request_for_test(fixture.rest, "GET", GROUPS_PATH, spec)

      find_player()
      test.let_time_pass(120)
      assert(not was_online_ever(), "the device should not go online while the player's groups request fails")
      assert(#secret_requests == 0, "a failing player is not a reason to ask for a token, got: " .. table.concat(secret_kinds(), ","))

      -- The driver tries again when the player answers a search of its own again.
      failing = false
      fixture.expect_player_events()
      fixture.ssdp:reply(helpers.ssdp_reply(), { from_host = helpers.PLAYER_IP })
      test.wait_until(fixture.is_online, { within = 30, message = "the device online" })
      test.wait_for_events()
      assert(#secret_requests == 0, "no token should have been requested, got: " .. table.concat(secret_kinds(), ","))
    end,
    { min_api_version = 23 }
  )
end

--#endregion

--#region Requesting and refreshing the token

local function assert_gaps_grow(requests, min_requests)
  assert(#requests >= min_requests, string.format("expected at least %d token requests, got %d", min_requests, #requests))
  local previous_gap
  for i = 2, min_requests do
    local gap = requests[i].time - requests[i - 1].time
    assert(previous_gap == nil or gap > previous_gap + 4, string.format(
      "expected each wait for a token to be longer than the last, but request %d came %.1fs after the one before it, which came %.1fs after its own predecessor",
      i, gap, previous_gap or 0))
    previous_gap = gap
  end
end

-- However the hub answers the request, a token that does not arrive is asked for again, waiting
-- longer each time.
for _, case in ipairs({ { name = "accepts the request", available = true }, { name = "refuses the request", available = false } }) do
  test.register_coroutine_test(
    "a driver that sees the account connected but gets no token asks again with growing delays when the hub " .. case.name,
    function()
      secrets_available = case.available
      set_account_state("connected")
      test.let_time_pass(600)
      assert(secret_requests[1].time == 0, "expected the first request as soon as the account was seen connected")
      assert_gaps_grow(secret_requests, 5)
      for _, request in ipairs(secret_requests) do
        assert(request.kind == "sonos_oauth", "unexpected kind of secret requested: " .. tostring(request.kind))
      end
    end,
    { min_api_version = 23 }
  )
end

test.register_coroutine_test(
  "a token that arrives ends the requests, and a new one is requested a minute before it expires",
  function()
    set_account_state("connected")
    test.let_time_pass(3)
    deliver_token(3600)
    local expires_at = os.time() + 3600
    test.let_time_pass(expires_at - 61 - os.time())
    assert(#secret_requests == 1, "expected no request while the token is valid, got " .. #secret_requests)
    test.let_time_pass(10)
    assert(#secret_requests == 2, "expected a request once the token was about to expire, got " .. #secret_requests)
    assert(secret_requests[2].time == expires_at - 60, string.format(
      "expected the request 60s before the token expires (at %d), but it came at %s", expires_at - 60, tostring(secret_requests[2].time)))
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a token that replaces the one the driver was waiting on sets the expiry it waits for",
  function()
    have_linked_account(7200, "tok-old")
    test.let_time_pass(100)
    deliver_token(3600, "tok-new")
    local expires_at = os.time() + 3600
    test.let_time_pass(expires_at - 61 - os.time())
    assert(#secret_requests == 0, "the driver should not ask for a token while the new one is valid")
    -- The first token would have been replaced at 7140s.
    test.let_time_pass(10)
    assert(#secret_requests == 1, "expected a request as the replacement token was about to expire, got " .. #secret_requests)
    assert(secret_requests[1].time == expires_at - 60, string.format(
      "expected the request 60s before the replacement token expires (at %d), but it came at %s", expires_at - 60, tostring(secret_requests[1].time)))
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "an account that is disconnected is not asked for a token, and its token is not used",
  function()
    have_linked_account(3600)
    set_account_state("disconnected")
    fixture.bring_up()
    -- Well past the token's expiry.
    test.let_time_pass(4000)
    assert(#secret_requests == 0, "no token should be requested for a disconnected account, got " .. #secret_requests)
    for _, value in ipairs(groups_request_headers("authorization")) do
      assert(value == false, "a disconnected account's token was sent: " .. tostring(value))
    end
    assert_ws_messages_authorized_with(nil)
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "an account the hub no longer has is not asked for a token, and its token is not used",
  function()
    have_linked_account(3600)
    delete("endpointAppInfo")
    fixture.bring_up()
    -- Well past the token's expiry.
    test.let_time_pass(4000)
    assert(#secret_requests == 0, "no token should be requested for an account the hub no longer has, got " .. #secret_requests)
    for _, value in ipairs(groups_request_headers("authorization")) do
      assert(value == false, "the token of an account the hub no longer has was sent: " .. tostring(value))
    end
    assert_ws_messages_authorized_with(nil)
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "an expired token is not used, and a new one is requested",
  function()
    test.let_time_pass(100)
    have_linked_account(-10)
    assert(#secret_requests == 1, "expected the driver to ask for a new token, got " .. #secret_requests)
    fixture.bring_up()
    for _, value in ipairs(groups_request_headers("authorization")) do
      assert(value == false, "an expired token was sent: " .. tostring(value))
    end
    assert_ws_messages_authorized_with(nil)
  end,
  { min_api_version = 23 }
)

--#endregion

--#region Capability commands

local function receive_play_command()
  test.socket.capability:__queue_receive({
    fixture.device.id,
    { capability = "mediaPlayback", command = "play", args = {}, component = "main" },
  })
end

--- The `playback.play` messages the driver has sent to the player.
local function play_messages()
  local found = {}
  for _, message in ipairs(helpers.sent_ws_messages(fixture.ws)) do
    if message.header.namespace == "playback" and message.header.command == "play" then table.insert(found, message) end
  end
  return found
end

test.register_coroutine_test(
  "a command carries the token",
  function()
    have_linked_account()
    fixture.bring_up()
    helpers.expect_ws_message(fixture.ws, "playback", "play", { header = { authorization = "Bearer tok-1" } })
    receive_play_command()
    test.wait_for_events()
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a command that arrives while the token is being requested waits for it, and is sent with it",
  function()
    set_account_state("connected")
    fixture.bring_up()
    receive_play_command()
    test.let_time_pass(20)
    assert(#play_messages() == 0, "the command should wait for the token")

    helpers.expect_ws_message(fixture.ws, "playback", "play", { header = { authorization = "Bearer tok-1" } })
    deliver_token()
    test.wait_for_events()
    assert(#play_messages() == 1, "expected the command to be sent once the token arrived")
  end,
  { min_api_version = 23 }
)

test.register_coroutine_test(
  "a command that arrives while the token is being requested is sent without it after 30 seconds if none arrives",
  function()
    set_account_state("connected")
    fixture.bring_up()
    receive_play_command()
    test.let_time_pass(29)
    assert(#play_messages() == 0, "the command should wait for the token")

    helpers.expect_ws_message(fixture.ws, "playback", "play")
    test.let_time_pass(2)
    local sent = play_messages()
    assert(#sent == 1, "expected the command to be sent after the wait for the token")
    assert(sent[1].header.authorization == nil, "no token was available, got authorization " .. tostring(sent[1].header.authorization))
  end,
  { min_api_version = 23 }
)

--#endregion

test.run_registered_tests()
