local helpers = require "test.review_lan_helpers"
local test = require "integration_test"
local capabilities = require "st.capabilities"
local mock_lan_socket = require "integration_test.mock_lan_socket"
local mock_devices_api = require "integration_test.mock_devices_api"

local scenario, rest, ws = helpers.create_scenario()
helpers.register_standard_expectations(rest, ws)
local mock_device = helpers.mock_device()
local ssdp_peer

test.set_test_init_function(function()
  scenario:activate()
  ssdp_peer = mock_lan_socket.udp_peer("239.255.255.250", 1900)
  test.mock_device.add_test_device(mock_device)
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.mediaPlayback.supportedPlaybackCommands({"play", "pause", "stop"})))
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
    capabilities.mediaTrackControl.supportedTrackControlCommands({"nextTrack", "previousTrack"})))
end)

local function expect_discovery_events()
  local function ev(c) test.socket.capability:__expect_send(mock_device:generate_test_message("main", c)) end
  ev(capabilities["stus.softwareGeneration"].generation("2"))
  ev(capabilities.mediaGroup.groupRole("ungrouped"))
  ev(capabilities.mediaGroup.groupPrimaryDeviceId(helpers.PLAYER_ID))
end

test.register_coroutine_test("bringup", function()
  expect_discovery_events()
  test.wait_until(function() return #ssdp_peer:sent() > 0 end, { message = "M-SEARCH" })
  print(ssdp_peer:sent()[1])
  ssdp_peer:reply(helpers.ssdp_reply(), { from_host = helpers.PLAYER_IP, from_port = 1900 })
  test.wait_until(function() return mock_devices_api.__is_device_online(mock_device.id) end, {message = "online", max_turns = 200})
end)

test.run_registered_tests()
