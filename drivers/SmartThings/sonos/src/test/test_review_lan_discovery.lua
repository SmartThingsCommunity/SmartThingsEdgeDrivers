-- Use case 3: SSDP discovery timing.
local helpers = require "test.review_lan_helpers"
local test = require "integration_test"
local mock_devices_api = require "integration_test.mock_devices_api"

local ctx = helpers.new_context({ no_device = true, rescan_timer = true })
test.set_test_init_function(ctx.init)

test.register_coroutine_test("SSDP reply from an unknown player creates a LAN device", function()
  mock_devices_api.__expect_create_device({
    type = "LAN",
    deviceNetworkId = helpers.MAC,
    label = "Kitchen",
    profileReference = "sonos-player",
    manufacturer = "Sonos",
    model = "Sonos One",
    vendorProvidedLabel = "sonos-one",
  })
  test.wait_until(function() return #ctx.ssdp:sent() > 0 end, { message = "the driver's M-SEARCH" })
  local search = ctx.ssdp:sent()[1]
  assert(search:find("M-SEARCH * HTTP/1.1", 1, true) and search:find("ST: " .. helpers.SEARCH_TERM, 1, true), search)
  ctx.ssdp:reply(helpers.ssdp_reply(), { from_host = helpers.PLAYER_IP, from_port = 1900 })
  test.wait_for_events()
  test.wait_until(function() return ctx.rest:connection_count() >= 2 end, { message = "REST info + groups" })
  test.wait_for_events()
end)

test.register_coroutine_test("an SSDP reply whose source IP differs from its LOCATION is ignored", function()
  test.wait_until(function() return #ctx.ssdp:sent() > 0 end, { message = "the driver's M-SEARCH" })
  ctx.ssdp:reply(helpers.ssdp_reply(), { from_host = "192.168.1.99", from_port = 1900 })
  test.wait_for_events()
  test.wait_for_events()
  assert(ctx.rest:connection_count() == 0, "no REST request for a spoofed reply")
end)

test.register_coroutine_test("the persistent SSDP task re-searches every 10 minutes", function()
  test.wait_until(function() return #ctx.ssdp:sent() > 0 end, { message = "the driver's M-SEARCH" })
  local before = #ctx.ssdp:sent()
  test.wait_until(function() return #ctx.ssdp:sent() > before end, { message = "a periodic M-SEARCH", max_turns = 2000 })
end)

test.run_registered_tests()
