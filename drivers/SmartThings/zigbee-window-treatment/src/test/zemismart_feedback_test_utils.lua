-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local z_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local confirmation = require "zemismart.position_confirmation"

local helpers = {}
local position = clusters.WindowCovering.attributes.CurrentPositionLiftPercentage
local battery_profiles = {}

-- Exercise actual requested delays, including simultaneous response/total/lease timers.
-- The SDK's default unqueued mock timer never fires, which would hide expiry defects.
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
  local definition = t_utils.get_profile_definition(profile or "window-treatment-profile.yml")
  local device = test.mock_device.build_test_zigbee_device({
    profile = definition,
    zigbee_endpoints = {
      [1] = {
        id = 1, manufacturer = "_TZE200_cirjrpxe", model = "TS0301",
        server_clusters = { 0x0000, 0x0001, 0x0003, 0x0004, 0x0005, 0x0102, 0xEF00 },
        client_clusters = { 0x0019 },
      },
    },
  })
  for _, component in pairs(definition.components) do
    for _, capability in pairs(component.capabilities) do
      if capability.id == "battery" then battery_profiles[device] = true end
    end
  end
  helpers.device = helpers.device or device
  return device
end

function helpers.expect_event(event, device)
  device = target(device)
  test.socket.capability:__expect_send(device:generate_test_message("main", event))
end

function helpers.expect_read(device)
  device = target(device)
  test.socket.zigbee:__expect_send({ device.id, position:read(device) })
end

function helpers.command(capability, name, args, device)
  device = target(device)
  test.socket.capability:__queue_receive({ device.id, {
    capability = capability, component = "main", command = name, args = args or {},
  } })
end

function helpers.response(level, sequence, endpoint, device)
  device = target(device)
  local message = position:build_test_read_attr_response(device, level)
  if sequence ~= nil then message.body.zcl_header.seqno.value = sequence end
  if endpoint ~= nil then message.address_header.src_endpoint.value = endpoint end
  test.socket.zigbee:__queue_receive({ device.id, message })
  return message
end

function helpers.report(level, sequence, endpoint, device)
  device = target(device)
  local message = position:build_test_attr_report(device, level)
  if sequence ~= nil then message.body.zcl_header.seqno.value = sequence end
  if endpoint ~= nil then message.address_header.src_endpoint.value = endpoint end
  test.socket.zigbee:__queue_receive({ device.id, message })
  return message
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
  if not battery_profiles[device] then
    helpers.expect_event(capabilities.windowShade.windowShade.unknown(), device)
    helpers.expect_read(device)
  end
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

-- Trust is established solely through two successful protocol reads, never set_field.
-- These synthetic messages test acceptance policy, not on-air TSN correlation.
function helpers.confirm(level, first_sequence, second_sequence, device)
  device = target(device)
  test.wait_for_events()
  if not device:get_field("_zemismartPositionCheck") then
    helpers.command("refresh", "refresh", nil, device)
    helpers.expect_read(device)
    test.wait_for_events()
  end
  helpers.response(level, first_sequence or 0x11, nil, device)
  test.wait_for_events()
  helpers.expect_read(device)
  helpers.advance(2)
  helpers.response(level, second_sequence or 0x12, nil, device)
  helpers.expect_static(level, device)
  test.wait_for_events()
  assert(confirmation.position_is_known(device), "two real read responses must establish trust")
end

return helpers
