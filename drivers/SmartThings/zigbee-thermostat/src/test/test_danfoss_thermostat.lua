local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local PowerConfiguration = clusters.PowerConfiguration
local Thermostat = clusters.Thermostat

local mock_device_danfoss = test.mock_device.build_test_zigbee_device(
  {
    profile = t_utils.get_profile_definition("thermostat-popp-danfoss.yml"),
    zigbee_endpoints = {
      [1] = {
        id = 1,
        manufacturer = "Danfoss",
        model = "eTRV0100",
        server_clusters = {0x0001, 0x0201, 0x0402}
      }
    }
  }
)

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device_danfoss)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Heating setpoint reports are handled Danfoss",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device_danfoss.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device_danfoss, 2500) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_danfoss:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 25.0, unit = "C" }))
    }
  }
)

test.register_coroutine_test(
  "Temperature reporting should create the appropriate events Danfoss",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device_danfoss.id, Thermostat.attributes.LocalTemperature:build_test_attr_report(mock_device_danfoss, 2100) })
    test.socket.capability:__expect_send(mock_device_danfoss:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.0, unit = "C"})))
  end
)

test.register_coroutine_test(
  "Thermostat heating setpoint reporting should create the appropriate events Danfoss",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device_danfoss.id, Thermostat.attributes.OccupiedHeatingSetpoint:build_test_attr_report(mock_device_danfoss, 2100) })
    test.socket.capability:__expect_send(mock_device_danfoss:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 21.0, unit = "C"})))
  end
)

test.register_coroutine_test(
  "Thermostat cooling setpoint reporting should not create setpoint events, the mode is not supported Danfoss",
  function ()
    test.socket.zigbee:__queue_receive({ mock_device_danfoss.id, Thermostat.attributes.OccupiedCoolingSetpoint:build_test_attr_report(mock_device_danfoss, 2100) })
  end
)

test.register_coroutine_test(
  "Battery reports test cases",
  function()
    local battery_test_map = {
      ["Danfoss"] = {
        [34] = 100,
        [32] = 100,
        [30] = 75,
        [28] = 50,
        [26] = 25,
        [24] = 0,
        [15] = 0
      }
    }

    for voltage, batt_perc in pairs(battery_test_map[mock_device_danfoss:get_manufacturer()]) do
      test.socket.zigbee:__queue_receive({ mock_device_danfoss.id, PowerConfiguration.attributes.BatteryVoltage:build_test_attr_report(mock_device_danfoss, voltage) })
      test.socket.capability:__expect_send( mock_device_danfoss:generate_test_message("main", capabilities.battery.battery(batt_perc)) )
      test.wait_for_events()
    end
  end
)

test.register_message_test(
  "Battery percentage report should be handled Danfoss",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = { mock_device_danfoss.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device_danfoss, 55) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device_danfoss:generate_test_message("main", capabilities.battery.battery(28))
    }
  }
)

test.run_registered_tests()