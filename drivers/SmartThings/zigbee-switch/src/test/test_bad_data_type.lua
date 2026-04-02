-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local data_types = require "st.zigbee.data_types"
local OnOff = clusters.OnOff

local mock_device = test.mock_device.build_test_zigbee_device({
  profile = t_utils.get_profile_definition("basic-switch.yml"),
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "SONOFF",
      model = "01MINIZB",
      server_clusters = { 0x0006 },
    }
  }
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
end

test.set_test_init_function(test_init)

local bad_data_type_on_off = OnOff.attributes.OnOff:build_test_attr_report(mock_device, false)
bad_data_type_on_off.body.zcl_body.attr_records[1].data_type.value = data_types.Int8.ID
test.register_message_test(
  "Reported on off status should be handled: off",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device.id, bad_data_type_on_off }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.switch.switch.off())
    }
  },
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
