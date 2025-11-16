local test = require "integration_test"
local cluster_base = require "st.zigbee.cluster_base"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local capabilities = require "st.capabilities"
local data_types = require "st.zigbee.data_types"

local PresenceSensor = capabilities.presenceSensor
local MovementSensor = capabilities["stse.movementSensor"]
test.add_package_capability("movementSensor.yaml")

local PRIVATE_CLUSTER_ID = 0xFCC0
local PRIVATE_ATTRIBUTE_ID = 0x0009
local MFG_CODE = 0x115F

local MONITORING_MODE = 0x0144
local RESET_MODE = 0x0157


local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("aqara-presence-sensor-fp1.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "aqara",
        model = "lumi.motion.ac01",
        server_clusters = { PRIVATE_CLUSTER_ID }
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
  "lifecycle - doConfigure test",
  function()
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    -- private protocol enable
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, PRIVATE_ATTRIBUTE_ID, MFG_CODE,
        data_types.Uint8, 1) })
    -- init
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, MONITORING_MODE, MFG_CODE,
        data_types.Uint8, 0) })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, RESET_MODE, MFG_CODE,
        data_types.Uint8, 1) })

    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end
)

test.register_coroutine_test(
  "preference - Sensitivity",
  function()
    local updates = {
      preferences = {
        ["stse.sensitivity"] = 2
      }
    }
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x010C, MFG_CODE,
        data_types.Uint8, updates.preferences["stse.sensitivity"]) })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    -- No events should be emitted
    updates.preferences["stse.sensitivity"] = 3
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x010C, MFG_CODE,
        data_types.Uint8, updates.preferences["stse.sensitivity"]) })
  end
)

test.register_coroutine_test(
  "preference - Reset Presence",
  function()
    local updates = {
      preferences = {
        ["stse.resetPresence"] = true
      }
    }
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, RESET_MODE, MFG_CODE,
        data_types.Uint8, 0x01) })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    -- No events should be emitted
    updates.preferences["stse.resetPresence"] = false
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, RESET_MODE, MFG_CODE,
        data_types.Uint8, 0x01) })
  end
)

test.register_coroutine_test(
  "preference - Approach Distance",
  function()
    local updates = {
      preferences = {
        ["stse.approachDistance"] = 1
      }
    }
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0146, MFG_CODE,
        data_types.Uint8, updates.preferences["stse.approachDistance"]) })
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    -- No events should be emitted
    updates.preferences["stse.approachDistance"] = 0
    test.wait_for_events()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0146, MFG_CODE,
        data_types.Uint8, updates.preferences["stse.approachDistance"]) })
  end
)

test.register_coroutine_test(
  "presence monitor - present",
  function()
    local attr_report_data = {
      { 0x0142, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      PresenceSensor.presence("present")))
  end
)

test.register_coroutine_test(
  "presence monitor - not present",
  function()
    local attr_report_data = {
      { 0x0142, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      PresenceSensor.presence("not present")))
  end
)

test.register_coroutine_test(
  "movement monitor - enter",
  function()
    local attr_report_data = {
      { 0x0143, data_types.Uint8.ID, 0x00 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("enter")))
    local movement_timer = 1
    test.timer.__create_and_queue_test_time_advance_timer(movement_timer, "oneshot")
    test.mock_time.advance_time(movement_timer)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("noMovement")))
  end
)

test.register_coroutine_test(
  "movement monitor - leave",
  function()
    local attr_report_data = {
      { 0x0143, data_types.Uint8.ID, 0x01 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("leave")))
    local movement_timer = 1
    test.timer.__create_and_queue_test_time_advance_timer(movement_timer, "oneshot")
    test.mock_time.advance_time(movement_timer)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("noMovement")))
  end
)

test.register_coroutine_test(
  "movement monitor - approaching",
  function()
    local attr_report_data = {
      { 0x0143, data_types.Uint8.ID, 0x06 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("approaching")))
    local movement_timer = 1
    test.timer.__create_and_queue_test_time_advance_timer(movement_timer, "oneshot")
    test.mock_time.advance_time(movement_timer)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("noMovement")))
  end
)

test.register_coroutine_test(
  "movement monitor - goingAway",
  function()
    local attr_report_data = {
      { 0x0143, data_types.Uint8.ID, 0x07 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("goingAway")))
    local movement_timer = 1
    test.timer.__create_and_queue_test_time_advance_timer(movement_timer, "oneshot")
    test.mock_time.advance_time(movement_timer)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      MovementSensor.movement("noMovement")))
  end
)

test.run_registered_tests()
