-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local z_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local path = require "path"
local yaml = require "yaml"

local helpers = {}
local position = clusters.WindowCovering.attributes.CurrentPositionLiftPercentage

-- Use the requested delays: unqueued SDK mock timers never fire and hide expiry bugs.
local create_oneshot = test.timer.create_oneshot
test.timer.create_oneshot = function(seconds)
  if #test.timer.__oneshot_timers == 0 then
    test.timer.__create_and_queue_test_time_advance_timer(seconds, "oneshot")
  end
  return create_oneshot(seconds)
end

local function target(device)
  return assert(device or helpers.device, "create a feedback test device first")
end

function helpers.create(profile)
  local device = test.mock_device.build_test_zigbee_device({
    profile = t_utils.get_profile_definition(profile or "window-treatment-profile.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1, manufacturer = "_TZE200_cirjrpxe", model = "TS0301",
        server_clusters = { 0x0000, 0x0001, 0x0003, 0x0004, 0x0005, 0x0102, 0xEF00 },
        client_clusters = { 0x0019 },
      },
    },
  })
  helpers.device = helpers.device or device
  return device
end

-- Resolve the package's actual mapping; this checks packaging inputs, not cloud pairing.
function helpers.create_from_fingerprint()
  local caller_path = path.Path(debug.getinfo(1, "S").source:sub(2))
  local src_path = caller_path:get_dir_pos("src") and caller_path:to_dir("src") or path.Path("")
  local file = assert(io.open(src_path:parent():append("fingerprints.yml"):to_string()))
  local contents = file:read("a")
  file:close()
  -- The SDK YAML reader stops at empty separator lines in this simple mapping file.
  contents = contents:gsub("\n[ \t]*\n", "\n")
  local fingerprints = yaml.eval(contents)
  local selected
  for _, fingerprint in ipairs(fingerprints.zigbeeManufacturer) do
    if fingerprint.manufacturer == "_TZE200_cirjrpxe" and fingerprint.model == "TS0301" then
      assert(selected == nil, "ambiguous manufacturer/model mapping")
      selected = fingerprint
    end
  end
  assert(selected, "shared Zemismart fingerprint missing from the package")
  return helpers.create(selected.deviceProfileName .. ".yml"), selected
end

function helpers.expect_event(event, device)
  device = target(device)
  test.socket.capability:__expect_send(device:generate_test_message("main", event))
end

function helpers.expect_read(device)
  device = target(device)
  test.socket.zigbee:__expect_send({ device.id, position:read(device) })
end

function helpers.expect_motion(command, argument, device)
  device = target(device)
  local message = argument ~= nil and clusters.WindowCovering.server.commands[command](device, argument)
    or clusters.WindowCovering.server.commands[command](device)
  test.socket.zigbee:__expect_send({ device.id, message })
end

function helpers.command(capability, name, args, device)
  device = target(device)
  test.socket.capability:__queue_receive({ device.id, {
    capability = capability, component = "main", command = name, args = args or {},
  } })
end

function helpers.response(level, device)
  device = target(device)
  test.socket.zigbee:__queue_receive({ device.id, position:build_test_read_attr_response(device, level) })
end

function helpers.report(level, device)
  device = target(device)
  test.socket.zigbee:__queue_receive({ device.id, position:build_test_attr_report(device, level) })
end

function helpers.expect_static(level, device)
  helpers.expect_event(capabilities.windowShadeLevel.shadeLevel(level), device)
  local shade = capabilities.windowShade.windowShade
  helpers.expect_event(level == 0 and shade.closed()
    or level == 100 and shade.open() or shade.partially_open(), device)
end

function helpers.initialize_device(device)
  device = target(device)
  helpers.device = device
  test.mock_device.add_test_device(device)
  helpers.expect_event(capabilities.windowShadePreset.supportedCommands(
    { "presetPosition", "setPresetPosition" }, { visibility = { displayed = false } }), device)
  helpers.expect_event(capabilities.windowShadePreset.position(
    50, { visibility = { displayed = false } }), device)
end

function helpers.set_test_init(device)
  device = target(device)
  z_utils.prepare_zigbee_env_info()
  local init = function() helpers.initialize_device(device) end
  test.set_test_init_function(init)
  return init
end

function helpers.advance(seconds)
  test.mock_time.advance_time(seconds)
  test.wait_for_events()
end

-- Establish state through a real protocol response, not an implementation-private field.
function helpers.seed(level, device)
  helpers.response(level, device)
  helpers.expect_static(level, device)
  test.wait_for_events()
end

function helpers.step(step, level, device)
  helpers.command("statelessWindowShadeLevelStep", "stepShadeLevel", { step }, device)
  helpers.expect_motion("GoToLiftPercentage", level, device)
  test.wait_for_events()
end

function helpers.capture_callbacks(device)
  device = target(device)
  local original = device.thread.call_with_delay
  local callbacks = {}
  device.thread.call_with_delay = function(thread, seconds, callback, ...)
    callbacks[#callbacks + 1] = { seconds = seconds, callback = callback }
    return original(thread, seconds, callback, ...)
  end
  return callbacks, function() device.thread.call_with_delay = original end
end

return helpers
