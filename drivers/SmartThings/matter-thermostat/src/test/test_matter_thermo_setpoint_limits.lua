--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat-humidity-fan.yml"),
  manufacturer_info = {
    vendor_id = 0x0000,
    product_id = 0x0000,
  },
  endpoints = {
    {
      endpoint_id = 0,
      clusters = {
        {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
      },
      device_types = {
        device_type_id = 0x0016, device_type_revision = 1, -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=35, -- Heat, Cool, and Auto features.
        },
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ThermostatRunningState,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.PowerSource.attributes.BatPercentRemaining,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local cached_heating_setpoint = capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 24.44, unit = "C" })
local cached_cooling_setpoint = capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 26.67, unit = "C" })

local function configure(device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  local read_limits = clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:read()
  read_limits:merge(clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:read())
  read_limits:merge(clusters.Thermostat.attributes.AbsMinCoolSetpointLimit:read())
  read_limits:merge(clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit:read())
  read_limits:merge(clusters.Thermostat.attributes.MinSetpointDeadBand:read())
  test.socket.matter:__expect_send({device.id, read_limits})
  mock_device:expect_metadata_update({ profile = "thermostat-nostate" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  test.wait_for_events()
  --Populate setpoint limits
  test.socket.matter:__queue_receive({
    device.id,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:build_test_report_data(device, 1, 1000)
  })
  test.socket.matter:__queue_receive({
    device.id,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:build_test_report_data(device, 1, 3222)
  })
  test.socket.matter:__queue_receive({
    device.id,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit:build_test_report_data(device, 1, 1000) --10.0 celcius
  })
  test.socket.matter:__queue_receive({
    device.id,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit:build_test_report_data(device, 1, 3222) --32.22 celcius
  })
  test.socket.matter:__queue_receive({
    device.id,
    clusters.Thermostat.attributes.MinSetpointDeadBand:build_test_report_data(device, 1, 16) --1.6 celcius
  })

  --populate cached setpoint values. This would normally happen due to subscription setup.
  test.socket.matter:__queue_receive({
    device.id,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint:build_test_report_data(mock_device, 1, 2444) --24.44 celcius
  })
  test.socket.matter:__queue_receive({
    device.id,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint:build_test_report_data(mock_device, 1, 2667) --26.67 celcius
  })
  test.socket.capability:__expect_send(
    device:generate_test_message("main", cached_heating_setpoint)
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", cached_cooling_setpoint)
  )
  test.wait_for_events()
end

test.register_coroutine_test(
  "Heat setpoint lower than min",
  function()
    configure(mock_device)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 9 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", cached_heating_setpoint)
    )
  end
)

test.register_coroutine_test(
  "Cool setpoint lower than min",
  function()
    configure(mock_device)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 9 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", cached_cooling_setpoint)
    )
  end
)

test.register_coroutine_test(
  "Heat setpoint higher than max",
  function()
    configure(mock_device)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 33 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", cached_heating_setpoint)
    )
  end
)

test.register_coroutine_test(
  "Cool setpoint higher than max",
  function()
    configure(mock_device)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 33 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", cached_cooling_setpoint)
    )
  end
)

test.register_coroutine_test(
  "Heat setpoint inside deadband",
  function()
    configure(mock_device)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatHeatingSetpoint", component = "main", command = "setHeatingSetpoint", args = { 26 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", cached_heating_setpoint)
    )
  end
)

test.register_coroutine_test(
  "Cool setpoint inside deadband",
  function()
    configure(mock_device)
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 25 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", cached_cooling_setpoint)
    )
  end
)

test.run_registered_tests()
