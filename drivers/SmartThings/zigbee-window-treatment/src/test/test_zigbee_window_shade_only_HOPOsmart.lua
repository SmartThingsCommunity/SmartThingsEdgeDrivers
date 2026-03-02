-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"

local PRIVATE_CLUSTER_ID = 0xFCC8
local MFG_CODE = 0x1235

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("window-shade-only.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "HOPOsmart",
          model = "A2230011",
          server_clusters = {0x0000, 0xFCC8}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "lifecycle - added test",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

	local read_0x0000_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE)
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0000_messge})
  end
)

test.register_message_test(
    "Handle Window shade open command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShade", component = "main", command = "open", args = {}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, clusters.WindowCovering.server.commands.UpOrOpen(mock_device) }
      }
    }
)

test.register_message_test(
    "Handle Window shade close command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_device.id,
          {
            capability = "windowShade", component = "main", command = "close", args = {}
          }
        }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          clusters.WindowCovering.server.commands.DownOrClose(mock_device)
        }
      }
    }
)

test.register_message_test(
    "Handle Window shade pause command",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "windowShade", component = "main", command = "pause", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = {
          mock_device.id,
          clusters.WindowCovering.server.commands.Stop(mock_device)
        }
      }
    }
)

test.register_coroutine_test(
  "Device reported 0 and driver emit windowShade.open",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.windowShade.windowShade.open()))
  end
)

test.register_coroutine_test(
  "Device reported 1 and driver emit windowShade.opening",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.windowShade.windowShade.opening()))
  end
)

test.register_coroutine_test(
  "Device reported 2 and driver emit windowShade.closed",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 2 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.windowShade.windowShade.closed()))
  end
)

test.register_coroutine_test(
  "Device reported 3 and driver emit windowShade.closeing",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 3 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.windowShade.windowShade.closing()))
  end
)

test.register_coroutine_test(
  "Device reported 4 and driver emit windowShade.partially_open",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 4 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.windowShade.windowShade.partially_open()))
  end
)

test.run_registered_tests()
