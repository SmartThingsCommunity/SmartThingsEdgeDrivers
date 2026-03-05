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

local PRIVATE_CLUSTER_ID = 0xFCC9
local MFG_CODE = 0x1235

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("projector-screen-VWSDSTUST120H.yml"),
      fingerprinted_endpoint_id = 0x01,
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "VIVIDSTORM",
          model = "VWSDSTUST120H",
          server_clusters = {0x0000, 0x0102, 0xFCC9}
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
  "capability - refresh",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })

    local read_0x0000_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE)
    local read_0x0001_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0001, MFG_CODE)
	test.socket.zigbee:__expect_send({mock_device.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0000_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0001_messge})
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "lifecycle - added test",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
	test.socket.capability:__expect_send(mock_device:generate_test_message("hardwareFault", capabilities.hardwareFault.hardwareFault.clear()))

	local read_0x0000_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0000, MFG_CODE)
    local read_0x0001_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID, 0x0001, MFG_CODE)
	test.socket.zigbee:__expect_send({mock_device.id,
        clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:read(mock_device)
    })
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0000_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_0x0001_messge})
  end,
  {
     min_api_version = 19
  }
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
    },
    {
       min_api_version = 19
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
    },
    {
       min_api_version = 19
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
    },
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
  "Handle Setlimit Delete upper limit",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mode", component = "main",  command ="setMode" , args = {"Delete upper limit"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 0)
    })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle Setlimit Set the upper limit",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mode", component = "main",  command ="setMode" , args = {"Set the upper limit"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 1)
    })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle Setlimit Delete lower limit",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mode", component = "main",  command ="setMode" , args = {"Delete lower limit"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 2)
    })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Handle Setlimit Set the lower limit",
  function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mode", component = "main",  command ="setMode" , args = {"Set the lower limit"}}
    })
    test.socket.zigbee:__expect_send({ mock_device.id,
      cluster_base.write_manufacturer_specific_attribute(mock_device, PRIVATE_CLUSTER_ID,
        0x0000, MFG_CODE, data_types.Uint8, 3)
    })
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported mode 0 and driver emit Delete upper limit",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.mode.mode("Delete upper limit")))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported mode 1 and driver emit Set the upper limit",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.mode.mode("Set the upper limit")))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported mode 2 and driver emit Delete lower limit",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 2 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.mode.mode("Delete lower limit")))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported mode 3 and driver emit Set the lower limit",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint8.ID, 3 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.mode.mode("Set the lower limit")))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported hardwareFault 0 and driver emit capabilities.hardwareFault.hardwareFault.clear()",
  function()
    local attr_report_data = {
      { 0x0001, data_types.Uint8.ID, 0 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("hardwareFault",
      capabilities.hardwareFault.hardwareFault.clear()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported hardwareFault 1 and driver emit capabilities.hardwareFault.hardwareFault.detected()",
  function()
    local attr_report_data = {
      { 0x0001, data_types.Uint8.ID, 1 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, PRIVATE_CLUSTER_ID, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("hardwareFault",
      capabilities.hardwareFault.hardwareFault.detected()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
    "WindowCovering CurrentPositionLiftPercentage report 5 emit closing",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(5, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 5)
        }
      )
      test.mock_time.advance_time(5)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
    end,
    {
       min_api_version = 19
    }
)

test.register_coroutine_test(
    "WindowCovering CurrentPositionLiftPercentage report 0 emit closed",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zigbee:__queue_receive(
        {
          mock_device.id,
          clusters.WindowCovering.attributes.CurrentPositionLiftPercentage:build_test_attr_report(mock_device, 0)
        }
      )
      test.mock_time.advance_time(5)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
      )
      test.wait_for_events()
    end,
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
