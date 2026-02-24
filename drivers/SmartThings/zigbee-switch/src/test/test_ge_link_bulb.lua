-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local OnOff = clusters.OnOff
local Level = clusters.Level

local mock_device = test.mock_device.build_test_zigbee_device(
  { profile = t_utils.get_profile_definition("ge-link-bulb.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "GE_Appliances",
        model = "ZLL Light",
        server_clusters = { 0x0006, 0x0008 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Capability 'switchLevel' command 'setLevel' on should be handled",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57 } } })

    test.socket.zigbee:__expect_send({ mock_device.id, Level.server.commands.MoveToLevelWithOnOff(mock_device, 144, 20) })

    test.wait_for_events()
    test.mock_time.advance_time(2)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Handle infochanged",
  function()
    local updates = {
      preferences = {
        dimOnOff = 1,
        dimRate = 50
      }
    }
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnOffTransitionTime:write(mock_device, 50) })
  end
)

test.register_coroutine_test(
  "Handle infochanged",
  function()
    local updates = {
      preferences = {
        dimOnOff = 0
      }
    }
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
  end
)

test.register_coroutine_test(
  "Capability 'switchLevel' command 'setLevel' with dimRate preference should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")

    local updates = {
      preferences = {
        dimOnOff = 1,
        dimRate = 50
      }
    }
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnOffTransitionTime:write(mock_device, 50) })

    test.wait_for_events()
    test.mock_time.advance_time(1)

    test.socket.capability:__queue_receive({ mock_device.id, { capability = "switchLevel", component = "main", command = "setLevel", args = { 57 } } })

    test.socket.zigbee:__expect_send({ mock_device.id, Level.server.commands.MoveToLevelWithOnOff(mock_device, 144, 50) })

    test.wait_for_events()
    test.mock_time.advance_time(5)

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
  end
)

test.register_coroutine_test(
  "Configure should configure all necessary attributes and refresh device",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    test.socket.zigbee:__set_channel_ordering("relaxed")

    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, OnOff.ID)
    })
    test.socket.zigbee:__expect_send({
      mock_device.id,
      zigbee_test_utils.build_bind_request(mock_device, zigbee_test_utils.mock_hub_eui, Level.ID)
    })

    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        OnOff.attributes.OnOff:configure_reporting(mock_device, 0, 300, 1)
      }
    )
    test.socket.zigbee:__expect_send(
      {
        mock_device.id,
        Level.attributes.CurrentLevel:configure_reporting(mock_device, 1, 3600, 1)
      }
    )

    test.socket.zigbee:__expect_send({ mock_device.id, OnOff.attributes.OnOff:read(mock_device) })
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.CurrentLevel:read(mock_device) })
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "Handle infoChanged when dimOnOff changes from 1 to 0 should write transition time 0",
  function()
    -- First: change dimOnOff from default 0 to 1 (triggers write with dimRate=20)
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { dimOnOff = 1 }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnOffTransitionTime:write(mock_device, 20) })
    test.wait_for_events()
    -- Now: change dimOnOff from 1 to 0 (driver old=1, new=0 -> writes 0)
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { dimOnOff = 0 }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnOffTransitionTime:write(mock_device, 0) })
  end
)

test.register_coroutine_test(
  "Handle infoChanged when dimRate changes while dimOnOff is 1 should write new dimRate",
  function()
    -- First: change dimOnOff from default 0 to 1 (triggers write with dimRate=20)
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { dimOnOff = 1 }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnOffTransitionTime:write(mock_device, 20) })
    test.wait_for_events()
    -- Now: change dimRate while dimOnOff stays 1 (driver old={dimOnOff=1,dimRate=20}, new={dimOnOff=1,dimRate=50})
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({
      preferences = { dimOnOff = 1, dimRate = 50 }
    }))
    test.socket.zigbee:__expect_send({ mock_device.id, Level.attributes.OnOffTransitionTime:write(mock_device, 50) })
  end
)

test.run_registered_tests()
