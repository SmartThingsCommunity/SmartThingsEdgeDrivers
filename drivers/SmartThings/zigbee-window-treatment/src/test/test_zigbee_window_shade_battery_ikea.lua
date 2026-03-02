-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local WindowCovering = clusters.WindowCovering

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("window-treatment-battery.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "IKEA of Sweden",
        model = "KADRILJ roller blind",
        server_clusters = {0x000, 0x0001, 0x0003, 0x0004, 0x0005}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed=false}}))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.windowShadePreset.position(50, {visibility = {displayed=false}}))
  )
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "State transition from opening to partially open",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 100)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    )
  end
)

test.register_coroutine_test(
  "State transition to unknown",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 255)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.unknown())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    )
  end
)

test.register_coroutine_test(
  "State transition from opening to partially open",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 0)
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    )
  end
)

test.register_coroutine_test(
  "State transition from opening to partially open",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 1)
      }
    )
    test.socket.capability:__expect_send(
        {
          mock_device.id,
          {
            capability_id = "windowShadeLevel", component_id = "main",
            attribute_id = "shadeLevel", state = { value = 99 }
          }
        }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    test.mock_time.advance_time(2)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "State transition from opening to closing",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 10)
      }
    )
    test.socket.capability:__expect_send(
        {
          mock_device.id,
          {
            capability_id = "windowShadeLevel", component_id = "main",
            attribute_id = "shadeLevel", state = { value = 90 }
          }
        }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    test.mock_time.advance_time(2)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
    test.wait_for_events()
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 15)
    })
    test.socket.capability:__expect_send({
      mock_device.id,
      {
        capability_id = "windowShadeLevel", component_id = "main",
        attribute_id = "shadeLevel", state = { value = 85 }
      }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
    test.mock_time.advance_time(3)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "windowShadePreset capability should be handled",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "setPresetPosition", args = {30}}
      }
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.windowShadePreset.position(30)))
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadePreset", component = "main", command = "presetPosition", args = {} }
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 100 - 30)
    })
  end
)

test.register_coroutine_test(
  "SetShadeLevel command handler",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        { capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 50 }}
      }
    )
    test.socket.zigbee:__expect_send({
      mock_device.id,
      WindowCovering.server.commands.GoToLiftPercentage(mock_device, 50)
    })
  end
)

test.register_coroutine_test(
  "Cancel existing set-status timer when a new partial level report arrives",
  function()
    -- First attr: level 90 sets T1
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 10)
    })
    test.socket.capability:__expect_send({
      mock_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 90 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    -- Second attr arrives before T1 fires: should cancel T1 and create T2
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 15)
    })
    test.socket.capability:__expect_send({
      mock_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 85 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
    -- T2 fires; T1 was cancelled so only partially_open from T2
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Timer callback emits closed when shade reaches level 0",
  function()
    -- First attr starts partial movement and arms a 1-second status timer
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 10)
    })
    test.socket.capability:__expect_send({
      mock_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 90 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    -- Second attr reports fully closed (level=0); goes through elseif branch, T1 still pending
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 100)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(0))
    )
    -- T1 fires; get_latest_state returns 0 so the callback emits closed()
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Timer callback emits open when shade reaches level 100",
  function()
    -- First attr starts partial movement and arms a 1-second status timer
    test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 10)
    })
    test.socket.capability:__expect_send({
      mock_device.id,
      { capability_id = "windowShadeLevel", component_id = "main", attribute_id = "shadeLevel", state = { value = 90 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
    -- Second attr reports fully open (level=100); goes through elseif branch, T1 still pending
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 0)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShadeLevel.shadeLevel(100))
    )
    -- T1 fires; get_latest_state returns 100 so the callback emits open()
    test.mock_time.advance_time(1)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
    test.wait_for_events()
  end
)

test.run_registered_tests()
