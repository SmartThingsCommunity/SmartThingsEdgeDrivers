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
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local utils = require "st.utils"
local dkjson = require "dkjson"

local clusters = require "st.matter.clusters"

test.set_rpc_version(8)

local mock_device_basic = test.mock_device.build_test_matter_device({
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

local mock_device_no_state = test.mock_device.build_test_matter_device({
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

local function initialize_mock_device(generic_mock_device, generic_subscribed_attributes)
  local subscribe_request = nil
  for _, attributes in pairs(generic_subscribed_attributes) do
    for _, attribute in ipairs(attributes) do
      if subscribe_request == nil then
        subscribe_request = attribute:subscribe(generic_mock_device)
      else
        subscribe_request:merge(attribute:subscribe(generic_mock_device))
      end
    end
  end
  test.socket.matter:__expect_send({generic_mock_device.id, subscribe_request})
  test.mock_device.add_test_device(generic_mock_device)
  return subscribe_request
end

local subscribe_request_basic
local function test_init_basic()
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
  subscribe_request_basic = initialize_mock_device(mock_device_basic, subscribed_attributes)
  local read_setpoint_deadband = clusters.Thermostat.attributes.MinSetpointDeadBand:read()
  test.socket.matter:__expect_send({mock_device_basic.id, read_setpoint_deadband})
end

local subscribed_attributes_no_state = {
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

local subscribe_request_no_state = nil
for _, attributes in pairs(subscribed_attributes_no_state) do
  for _, attribute in ipairs(attributes) do
    if subscribe_request_no_state == nil then
      subscribe_request_no_state = attribute:subscribe(mock_device_no_state)
    else
      subscribe_request_no_state:merge(attribute:subscribe(mock_device_no_state))
    end
  end
end


local function test_init_no_state()
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

  -- initially, device onboards WITH thermostatOperatingState, the test below will
  -- check if it is removed correctly when switching to modular profile. This is done
  -- to test that cases where the modular profile is different from the static profile
  -- work correctly, and thermostatOperatingState is simple to remove in these
  -- test cases via the device field
  initialize_mock_device(mock_device_no_state, subscribed_attributes)
  local read_setpoint_deadband = clusters.Thermostat.attributes.MinSetpointDeadBand:read()
  test.socket.matter:__expect_send({mock_device_no_state.id, read_setpoint_deadband})
end

-- run the profile configuration tests
local function test_room_ac_device_type_update_modular_profile(generic_mock_device, expected_metadata, subscribe_request)
  test.socket.device_lifecycle:__queue_receive({generic_mock_device.id, "doConfigure"})
  generic_mock_device:expect_metadata_update(expected_metadata)
  generic_mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local device_info_copy = utils.deep_copy(generic_mock_device.raw_st_data)
  device_info_copy.profile.id = "room-air-conditioner-modular"
  local device_info_json = dkjson.encode(device_info_copy)
  test.socket.device_lifecycle:__queue_receive({ generic_mock_device.id, "infoChanged", device_info_json })
  test.socket.matter:__expect_send({generic_mock_device.id, subscribe_request})
end

local expected_metadata_basic= {
  optional_component_capabilities={
    {
      "main",
      {
        "relativeHumidityMeasurement",
        "airConditionerFanMode",
        "fanSpeedPercent",
        "windMode",
        "thermostatHeatingSetpoint",
        "thermostatCoolingSetpoint",
        "thermostatOperatingState"
      },
    }
  },
  profile="room-air-conditioner-modular",
}

test.register_coroutine_test(
  "Device with modular profile should enable correct optional capabilities - basic",
  function()
    mock_device_basic:set_field("__BATTERY_SUPPORT", "NO_BATTERY") -- since we're assuming this would have happened during device_added in this case.
    mock_device_basic:set_field("__THERMOSTAT_RUNNING_STATE_SUPPORT", true) -- since we're assuming this would have happened during device_added in this case.
    test_room_ac_device_type_update_modular_profile(mock_device_basic, expected_metadata_basic, subscribe_request_basic)
  end,
  { test_init = test_init_basic }
)

local expected_metadata_no_state = {
  optional_component_capabilities={
    {
      "main",
      {
        "relativeHumidityMeasurement",
        "airConditionerFanMode",
        "fanSpeedPercent",
        "windMode",
        "thermostatHeatingSetpoint",
        "thermostatCoolingSetpoint",
      },
    }
  },
  profile="room-air-conditioner-modular",
}

test.register_coroutine_test(
  "Device with modular profile should enable correct optional capabilities - no thermo state",
  function()
    mock_device_no_state:set_field("__BATTERY_SUPPORT", "NO_BATTERY") -- since we're assuming this would have happened during device_added in this case.
    mock_device_no_state:set_field("__THERMOSTAT_RUNNING_STATE_SUPPORT", false) -- since we're assuming this would have happened during device_added in this case.
    test_room_ac_device_type_update_modular_profile(mock_device_no_state, expected_metadata_no_state, subscribe_request_no_state)
  end,
  { test_init = test_init_no_state }
)
test.run_registered_tests()
