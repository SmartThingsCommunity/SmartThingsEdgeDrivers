-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- Mock out globals
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local DoorLock = clusters.DoorLock

local mock_device = test.mock_device.build_test_zigbee_device({ profile = t_utils.get_profile_definition("base-lock.yml"), zigbee_endpoints ={ [1] = {id = 1, manufacturer ="ASSA ABLOY iRevo", model ="iZBModule01", server_clusters = {}} } })

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end

test.set_test_init_function(test_init)

test.register_message_test(
    "Max user code number report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device,
                                                                                                           16) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(30))
      }
    },
    {
       min_api_version = 19
    }
)

test.run_registered_tests()
