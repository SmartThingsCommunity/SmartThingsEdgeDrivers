-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local t_utils = require "integration_test.utils"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local PRIVATE_CLUSTER_ID = 0xFC00

local mock_device = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("light-color-temp-time-restore.yml"),
    fingerprinted_endpoint_id = 0x01,
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "FIRSTLED",
        model = "DC2DC12MiV1",
        server_clusters = { 0x0006, 0x0008, 0x0300 }
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

-- ====================== Preferences ======================
test.register_coroutine_test("infoChanged - outputMode 0", function()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = { outputMode = "0" }}))
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_attribute(mock_device,
      data_types.ClusterId(PRIVATE_CLUSTER_ID),
      data_types.AttributeId(0x0000),
      data_types.validate_or_build_type(0, data_types.Uint8, "payload"))
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - powerOnMode 0", function()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = { powerOnMode = "0" }}))
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_attribute(mock_device,
      data_types.ClusterId(PRIVATE_CLUSTER_ID),
      data_types.AttributeId(0x0001),
      data_types.validate_or_build_type(0, data_types.Uint8, "payload"))
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - ledDriveCurrent 100", function()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = { ledDriveCurrent = "100" }}))
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_attribute(mock_device,
      data_types.ClusterId(PRIVATE_CLUSTER_ID),
      data_types.AttributeId(0x0002),
      data_types.validate_or_build_type(100, data_types.Uint16, "payload"))
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - dimTransitionTime 2000", function()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = { dimTransitionTime = "2000" }}))
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_attribute(mock_device,
      data_types.ClusterId(PRIVATE_CLUSTER_ID),
      data_types.AttributeId(0x0003),
      data_types.validate_or_build_type(2000, data_types.Uint16, "payload"))
  })
  end,
  {
    min_api_version = 19
  }
)

test.register_coroutine_test("infoChanged - colorTempTransitionTime 2000", function()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ preferences = { colorTempTransitionTime = "2000" }}))
  test.socket.zigbee:__expect_send({ mock_device.id,
    cluster_base.write_attribute(mock_device,
      data_types.ClusterId(PRIVATE_CLUSTER_ID),
      data_types.AttributeId(0x0004),
      data_types.validate_or_build_type(2000, data_types.Uint16, "payload"))
  })
  end,
  {
    min_api_version = 19
  }
)

test.run_registered_tests()
