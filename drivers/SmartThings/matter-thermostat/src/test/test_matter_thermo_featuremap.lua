-- Copyright 2022 SmartThings
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
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=1, -- Heat feature only.
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"}
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    }
  }
})

local mock_device_simple = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat.yml"),
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
        {device_type_id = 0x0016, device_type_revision = 1}  -- RootNode
      }
    },
    {
      endpoint_id = 1,
      clusters = {
        {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = clusters.PowerSource.types.PowerSourceFeature.BATTERY},
        {
          cluster_id = clusters.Thermostat.ID,
          cluster_revision=5,
          cluster_type="SERVER",
          feature_map=2, -- Cool feature only.
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    }
  }
})

local mock_device_no_battery = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("thermostat.yml"),
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
          feature_map=2, -- Cool feature only.
        },
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
      }
    }
  }
})

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
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
  clusters.RelativeHumidityMeasurement.attributes.MeasuredValue,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.FanModeSequence,
  clusters.PowerSource.attributes.BatPercentRemaining,
}
local cluster_subscribe_list_simple = {
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
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
  clusters.PowerSource.attributes.BatPercentRemaining,
}
local cluster_subscribe_list_no_battery = {
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
  clusters.TemperatureMeasurement.attributes.MeasuredValue,
  clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
  clusters.TemperatureMeasurement.attributes.MaxMeasuredValue,
}

local function test_init()
  -- Set MIN_SETPOINT_DEADBAND_CHECKED bypass the setpoint limit read so it does not need
  -- to be checked in the init function.
  mock_device:set_field("MIN_SETPOINT_DEADBAND_CHECKED", 1, {persist = true})
  mock_device_simple:set_field("MIN_SETPOINT_DEADBAND_CHECKED", 1, {persist = true})
  mock_device_no_battery:set_field("MIN_SETPOINT_DEADBAND_CHECKED", 1, {persist = true})
  test.socket.matter:__set_channel_ordering("relaxed")
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  local subscribe_request_simple = cluster_subscribe_list_simple[1]:subscribe(mock_device_simple)
  for i, cluster in ipairs(cluster_subscribe_list_simple) do
    if i > 1 then
      subscribe_request_simple:merge(cluster:subscribe(mock_device_simple))
    end
  end
  local subscribe_request_no_battery = cluster_subscribe_list_no_battery[1]:subscribe(mock_device_no_battery)
  for i, cluster in ipairs(cluster_subscribe_list_no_battery) do
    if i > 1 then
      subscribe_request_no_battery:merge(cluster:subscribe(mock_device_no_battery))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.matter:__expect_send({mock_device_simple.id, subscribe_request_simple})
  test.socket.matter:__expect_send({mock_device_no_battery.id, subscribe_request_no_battery})
  test.mock_device.add_test_device(mock_device)
  test.mock_device.add_test_device(mock_device_simple)
  test.mock_device.add_test_device(mock_device_no_battery)

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  local read_req = clusters.Thermostat.attributes.ControlSequenceOfOperation:read()
  read_req:merge(clusters.FanControl.attributes.FanModeSequence:read())
  read_req:merge(clusters.FanControl.attributes.WindSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.FanControl.attributes.RockSupport:read())
  read_req:merge(clusters.PowerSource.attributes.AttributeList:read())
  read_req:merge(clusters.Thermostat.attributes.AttributeList:read())
  test.socket.matter:__expect_send({mock_device.id, read_req})
end
test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event due to cluster feature map",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
    --TODO why does provisiong state get added in the do configure event handle, but not the refres?)
    mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(12)})
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device, 1, {uint32(0x29)})
      }
    )
    mock_device:expect_metadata_update({ profile = "thermostat-humidity-fan-heating-only" })
end
)

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event due to cluster feature map",
  function()
    local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
    for i, cluster in ipairs(cluster_subscribe_list) do
      if i > 1 then
        subscribe_request:merge(cluster:subscribe(mock_device))
      end
    end
    test.socket.matter:__expect_send({mock_device.id, subscribe_request})

    -- profile name does not matter, we just check that the name is different in the info_changed handler
    local updates = {
      profile = {
        id = "new-profile"
      }
    }
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed(updates))
end
)

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event due to cluster feature map",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device_simple.id, "doConfigure" })
    mock_device_simple:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device_simple.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device_simple, 1, {uint32(12)})
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device_simple.id,
        clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_simple, 1, {uint32(12)})
      }
    )
    mock_device_simple:expect_metadata_update({ profile = "thermostat-cooling-only-nostate" })
end
)

test.register_coroutine_test(
  "Profile change on doConfigure lifecycle event no battery support",
  function()
    mock_device_no_battery:set_field("__BATTERY_SUPPORT", "NO_BATTERY") -- since we're assuming this would have happened during device_added in this case.
    test.socket.matter:__queue_receive(
      {
        mock_device_no_battery.id,
        clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_no_battery, 1, {uint32(12)})
      }
    )
    mock_device_no_battery:expect_metadata_update({ profile = "thermostat-cooling-only-nostate-nobattery" })
end
)

test.run_registered_tests()
