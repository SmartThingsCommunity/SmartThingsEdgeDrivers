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
local uint32 = require "st.matter.data_types.Uint32"

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
        {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
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
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "BOTH"},
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    }
  }
})

local function test_init()
  local cluster_subscribe_list = {
    clusters.Thermostat.attributes.LocalTemperature,
    clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
    clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
    clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit,
    clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
    clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit,
    clusters.Thermostat.attributes.SystemMode,
    clusters.Thermostat.attributes.ThermostatRunningState,
    clusters.Thermostat.attributes.ControlSequenceOfOperation,
    clusters.PowerSource.attributes.BatPercentRemaining,
    clusters.TemperatureMeasurement.attributes.MeasuredValue,
    clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
    clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
  }
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  local read_setpoint_deadband = clusters.Thermostat.attributes.MinSetpointDeadBand:read()
  test.socket.matter:__expect_send({mock_device.id, read_setpoint_deadband})

  test.mock_device.add_test_device(mock_device)

  test.set_rpc_version(5)
end
test.set_test_init_function(test_init)

local cached_heating_setpoint = capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 24.44, unit = "C" }, {state_change = true})
local cached_cooling_setpoint = capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 26.67, unit = "C" }, {state_change = true})

local function configure(device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })

  local read_attribute_list_req = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device.id, read_attribute_list_req})

  test.wait_for_events()

  test.socket.matter:__queue_receive({mock_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(0x0C)})})
  mock_device:expect_metadata_update({ profile = "thermostat-nostate" })

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
    device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 5.00, maximum = 40.00, step = 0.1 }, unit = "C" }))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = 24.44, unit = "C" }))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = 5.00, maximum = 40.00, step = 0.1 }, unit = "C" }))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpoint({ value = 26.67, unit = "C" }))
  )
end

test.register_coroutine_test(
  "Heat setpoint lower than min",
  function()
    configure(mock_device)
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:build_test_report_data(mock_device, 1, 1000)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:build_test_report_data(mock_device, 1, 3222)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 10.00, maximum = 32.22, step = 0.1 }, unit = "C" }))
    )
    test.wait_for_events()
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
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMinCoolSetpointLimit:build_test_report_data(mock_device, 1, 1000)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit:build_test_report_data(mock_device, 1, 3222)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = 10.00, maximum = 32.22, step = 0.1 }, unit = "C" }))
    )
    test.wait_for_events()
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
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:build_test_report_data(mock_device, 1, 1000)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:build_test_report_data(mock_device, 1, 3222)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 10.00, maximum = 32.22, step = 0.1 }, unit = "C" }))
    )
    test.wait_for_events()
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
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMinCoolSetpointLimit:build_test_report_data(mock_device, 1, 1000)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit:build_test_report_data(mock_device, 1, 3222)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = 10.00, maximum = 32.22, step = 0.1 }, unit = "C" }))
    )
    test.wait_for_events()
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
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.MinSetpointDeadBand:build_test_report_data(mock_device, 1, 16) --1.6 celcius
    })
    test.wait_for_events()
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
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.MinSetpointDeadBand:build_test_report_data(mock_device, 1, 16) --1.6 celcius
    })
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "thermostatCoolingSetpoint", component = "main", command = "setCoolingSetpoint", args = { 25 } }
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", cached_cooling_setpoint)
    )
  end
)

test.register_coroutine_test(
  "Set MIN_SETPOINT_DEADBAND_CHECKED flag on MinSetpointDeadBand attribute handler",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Thermostat.attributes.MinSetpointDeadBand:build_test_report_data(mock_device, 1, 16) --1.6 celcius
    })
    test.wait_for_events()
    local min_setpoint_deadband_checked = mock_device:get_field("MIN_SETPOINT_DEADBAND_CHECKED")
    assert(min_setpoint_deadband_checked == true, "min_setpoint_deadband_checked is True")
  end
)

test.register_message_test(
  "Min and max heating setpoint attributes set capability constraint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.AbsMinCoolSetpointLimit:build_test_report_data(mock_device, 1, 1000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit:build_test_report_data(mock_device, 1, 3222)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatCoolingSetpoint.coolingSetpointRange({ value = { minimum = 10.00, maximum = 32.22, step = 0.1 }, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Min and max cooling setpoint attributes set capability constraint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.AbsMinHeatSetpointLimit:build_test_report_data(mock_device, 1, 1000)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit:build_test_report_data(mock_device, 1, 3222)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.thermostatHeatingSetpoint.heatingSetpointRange({ value = { minimum = 10.00, maximum = 32.22, step = 0.1 }, unit = "C" }))
    }
  }
)

test.register_message_test(
  "Min and max temperature attributes set capability constraint",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MinMeasuredValue:build_test_report_data(mock_device, 1, 500)
      }
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MaxMeasuredValue:build_test_report_data(mock_device, 1, 3900)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperatureRange({ value = { minimum = 5.00, maximum = 39.00 }, unit = "C" }))
    }
  }
)

test.run_registered_tests()
