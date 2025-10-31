-- Copyright 2024 SmartThings
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
test.set_rpc_version(0)
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"
local clusters = require "st.matter.clusters"

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("room-air-conditioner.yml"),
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
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
      }
    }
  }
})

local mock_device_configure = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("room-air-conditioner.yml"),
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
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 63},
        {cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 63},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER", feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0072, device_type_revision = 1} -- Room Air Conditioner
      }
    }
  }
})

local mock_device_nostate = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("room-air-conditioner-fan-heating-cooling-nostate.yml"),
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
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER", feature_map = 0},
        {cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER", feature_map = 63},
        {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER", feature_map = 0},
      },
      device_types = {
        {device_type_id = 0x0072, device_type_revision = 1} -- Room Air Conditioner
      }
    }
  }
})

local function test_init()
  local subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.thermostatMode.ID] = {
      clusters.Thermostat.attributes.SystemMode,
      clusters.Thermostat.attributes.ControlSequenceOfOperation
    },
    [capabilities.thermostatOperatingState.ID] = {
      clusters.Thermostat.attributes.ThermostatRunningState
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
      clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
      clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit
    },
    [capabilities.airConditionerFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    },
    [capabilities.windMode.ID] = {
      clusters.FanControl.attributes.WindSupport,
      clusters.FanControl.attributes.WindSetting
    },
  }
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device)
      else
        subscribe_request:merge(attribute:subscribe(mock_device))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local function test_init_configure()
  local subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.relativeHumidityMeasurement.ID] = {
      clusters.RelativeHumidityMeasurement.attributes.MeasuredValue
    },
    [capabilities.thermostatMode.ID] = {
      clusters.Thermostat.attributes.SystemMode,
      clusters.Thermostat.attributes.ControlSequenceOfOperation
    },
    [capabilities.thermostatOperatingState.ID] = {
      clusters.Thermostat.attributes.ThermostatRunningState
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
      clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
      clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit
    },
    [capabilities.airConditionerFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    },
    [capabilities.windMode.ID] = {
      clusters.FanControl.attributes.WindSupport,
      clusters.FanControl.attributes.WindSetting
    },
  }
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device_configure)
      else
        subscribe_request:merge(attribute:subscribe(mock_device_configure))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device_configure.id, subscribe_request})

  local read_setpoint_deadband = clusters.Thermostat.attributes.MinSetpointDeadBand:read()
  test.socket.matter:__expect_send({mock_device_configure.id, read_setpoint_deadband})

  test.mock_device.add_test_device(mock_device_configure)
end

local function test_init_nostate()
  local subscribed_attributes = {
    [capabilities.switch.ID] = {
      clusters.OnOff.attributes.OnOff
    },
    [capabilities.temperatureMeasurement.ID] = {
      clusters.Thermostat.attributes.LocalTemperature,
      clusters.TemperatureMeasurement.attributes.MeasuredValue,
      clusters.TemperatureMeasurement.attributes.MinMeasuredValue,
      clusters.TemperatureMeasurement.attributes.MaxMeasuredValue
    },
    [capabilities.thermostatMode.ID] = {
      clusters.Thermostat.attributes.SystemMode,
      clusters.Thermostat.attributes.ControlSequenceOfOperation
    },
    [capabilities.thermostatCoolingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedCoolingSetpoint,
      clusters.Thermostat.attributes.AbsMinCoolSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxCoolSetpointLimit
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      clusters.Thermostat.attributes.OccupiedHeatingSetpoint,
      clusters.Thermostat.attributes.AbsMinHeatSetpointLimit,
      clusters.Thermostat.attributes.AbsMaxHeatSetpointLimit
    },
    [capabilities.airConditionerFanMode.ID] = {
      clusters.FanControl.attributes.FanModeSequence,
      clusters.FanControl.attributes.FanMode
    },
    [capabilities.fanSpeedPercent.ID] = {
      clusters.FanControl.attributes.PercentCurrent
    },
  }
  local subscribe_request = nil
  for _, attributes in pairs(subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(mock_device_nostate)
      else
        subscribe_request:merge(attribute:subscribe(mock_device_nostate))
      end
    end
  end
  test.socket.matter:__expect_send({mock_device_nostate.id, subscribe_request})

  local read_setpoint_deadband = clusters.Thermostat.attributes.MinSetpointDeadBand:read()
  test.socket.matter:__expect_send({mock_device_nostate.id, read_setpoint_deadband})

  test.mock_device.add_test_device(mock_device_nostate)
end

test.register_coroutine_test(
  "Test profile change on init for Room AC device type",
  function()
    mock_device_configure:set_field("__BATTERY_SUPPORT", "NO_BATTERY") -- since we're assuming this would have happened during device_added in this case.
    test.socket.device_lifecycle:__queue_receive({ mock_device_configure.id, "doConfigure" })
    mock_device_configure:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device_configure.id,
        clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_configure, 1, {uint32(0x29)})
      }
    )
    mock_device_configure:expect_metadata_update({ profile = "room-air-conditioner" })
  end,
  { test_init = test_init_configure }
)

test.register_coroutine_test(
  "Test profile change to profile without thermostatOperatingState on init for Room AC device type",
  function()
    mock_device_nostate:set_field("__BATTERY_SUPPORT", "NO_BATTERY") -- since we're assuming this would have happened during device_added in this case.
    test.socket.device_lifecycle:__queue_receive({ mock_device_nostate.id, "doConfigure" })
    mock_device_nostate:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device_nostate.id,
        clusters.Thermostat.attributes.AttributeList:build_test_report_data(mock_device_nostate, 1, {uint32(0)})
      }
    )
    mock_device_nostate:expect_metadata_update({ profile = "room-air-conditioner-fan-heating-cooling-nostate" })
  end,
  { test_init = test_init_nostate }
)

test.register_message_test(
  "Test fan speed commands",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.PercentCurrent:build_test_report_data(mock_device, 1, 10)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.fanSpeedPercent.percent(10))
    },
      {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "fanSpeedPercent", component = "main", command = "setPercent", args = { 50 } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.PercentSetting:write(mock_device, 1, 50)
      }
    }
  }
)

local supportedFanWind = {
  capabilities.windMode.windMode.noWind.NAME,
  capabilities.windMode.windMode.sleepWind.NAME,
  capabilities.windMode.windMode.naturalWind.NAME
}
test.register_message_test(
  "Test wind mode",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSupport:build_test_report_data(mock_device, 1, 0x03) -- NoWind,  SleepWind (0x0001), and NaturalWind (0x0002)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windMode.supportedWindModes(supportedFanWind, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:build_test_report_data(mock_device, 1, clusters.FanControl.types.WindSettingMask.SLEEP_WIND)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.windMode.windMode.sleepWind())
    },
    {
      channel = "capability",
      direction = "receive",
      message = {
        mock_device.id,
        { capability = "windMode", component = "main", command = "setWindMode", args = { "naturalWind" } }
      }
    },
    {
      channel = "matter",
      direction = "send",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.WindSetting:write(mock_device, 1, clusters.FanControl.types.WindSettingMask.NATURAL_WIND)
      }
    }
  }
)

test.register_message_test(
  "Test fan mode handler",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.OFF)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airConditionerFanMode.fanMode("off"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.LOW)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airConditionerFanMode.fanMode("low"))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.FanControl.attributes.FanMode:build_test_report_data(mock_device, 1, clusters.FanControl.attributes.FanMode.HIGH)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airConditionerFanMode.fanMode("high"))
    }
  }
)

local FanModeSequence = clusters.FanControl.attributes.FanModeSequence
test.register_message_test(
  "Room AC fan mode sequence reports should generate the appropriate supported modes",
  {
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, 1, FanModeSequence.OFF_ON)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airConditionerFanMode.supportedAcFanModes({"off", "high"}, {visibility={displayed=false}}))
    },
    {
      channel = "matter",
      direction = "receive",
      message = {
        mock_device.id,
        FanModeSequence:build_test_report_data(mock_device, 1, FanModeSequence.OFF_LOW_MED_HIGH_AUTO)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.airConditionerFanMode.supportedAcFanModes({"off", "low", "medium", "high", "auto"}, {visibility={displayed=false}}))
    }
  }
)

test.run_registered_tests()
