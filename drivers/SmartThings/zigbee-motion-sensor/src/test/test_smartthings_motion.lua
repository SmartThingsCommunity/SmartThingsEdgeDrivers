-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local PowerConfiguration = clusters.PowerConfiguration
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
      profile = t_utils.get_profile_definition("motion-temp-battery.yml"),
      zigbee_endpoints = {
        [1] = {
          id = 1,
          manufacturer = "SmartThings",
          model = "motionv4",
          server_clusters = {}
        }
      }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Battery Voltage test cases",
  function()
    local battery_test_map = {
      ["SmartThings"] = {
        [28] = 100,
        [27] = 100,
        [25] = 90,
        [24] = 90,
        [23] = 70,
        [21] = 50,
        [19] = 30,
        [18] = 30,
        [17] = 15,
        [16] = 1,
        [15] = 0
      }
    }

    for voltage, batt_perc in pairs(battery_test_map[mock_device:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_device.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device, voltage) })
      test.socket.capability:__expect_send( mock_device:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.run_registered_tests()
