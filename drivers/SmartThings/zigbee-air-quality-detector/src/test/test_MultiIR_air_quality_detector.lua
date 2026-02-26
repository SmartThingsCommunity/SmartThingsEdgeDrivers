-- Copyright 2025 SmartThings
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

-- Mock out globals
local test = require "integration_test"
local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"
local SinglePrecisionFloat = require "st.zigbee.data_types.SinglePrecisionFloat"

local profile_def = t_utils.get_profile_definition("air-quality-detector-MultiIR.yml")
local MFG_CODE = 0x1235

local mock_device = test.mock_device.build_test_zigbee_device(
{
  label = "air quality detector",
  profile = profile_def,
  zigbee_endpoints = {
    [1] = {
      id = 1,
      manufacturer = "MultiIR",
      model = "PMT1006S-SGM-ZTN",
      server_clusters = { 0x0000, 0x0402,0x0405,0xFCC1, 0xFCC2,0xFCC3,0xFCC5}
    }
  }
})

zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "capability - refresh",
  function()
    test.socket.capability:__queue_receive({ mock_device.id,
      { capability = "refresh", component = "main", command = "refresh", args = {} } })
    local read_RelativeHumidity_messge = clusters.RelativeHumidity.attributes.MeasuredValue:read(mock_device)
    local read_TemperatureMeasurement_messge = clusters.TemperatureMeasurement.attributes.MeasuredValue:read(mock_device)
    local read_pm2_5_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, 0xFCC1, 0x0000, MFG_CODE)
    local read_pm1_0_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, 0xFCC1, 0x0001, MFG_CODE)
    local read_pm10_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, 0xFCC1, 0x0002, MFG_CODE)
    local read_ch2o_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, 0xFCC2, 0x0000, MFG_CODE)
    local read_tvoc_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, 0xFCC2, 0x0001, MFG_CODE)
    local read_carbonDioxide_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, 0xFCC3, 0x0000, MFG_CODE)
    local read_AQI_messge = cluster_base.read_manufacturer_specific_attribute(mock_device, 0xFCC5, 0x0000, MFG_CODE)

    test.socket.zigbee:__expect_send({mock_device.id, read_RelativeHumidity_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_TemperatureMeasurement_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_pm2_5_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_pm1_0_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_pm10_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_ch2o_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_tvoc_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_carbonDioxide_messge})
    test.socket.zigbee:__expect_send({mock_device.id, read_AQI_messge})
  end,
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Relative humidity reports should generate correct messages",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.RelativeHumidity.attributes.MeasuredValue:build_test_attr_report(mock_device, 40*100)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 40 }))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_message_test(
  "Temperature reports should generate correct messages",
  {
    {
      channel = "zigbee",
      direction = "receive",
      message = {
        mock_device.id,
        clusters.TemperatureMeasurement.attributes.MeasuredValue:build_test_attr_report(mock_device, 2500)
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25.0, unit = "C"}))
    }
  },
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported carbonDioxide and driver emit carbonDioxide and carbonDioxideHealthConcern",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint16.ID, 1400 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCC3, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.carbonDioxideMeasurement.carbonDioxide({value = 1400, unit = "ppm"})))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.carbonDioxideHealthConcern.carbonDioxideHealthConcern({value = "good"})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported pm2.5 and driver emit pm2.5 and fineDustHealthConcern",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint16.ID, 74 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCC1, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fineDustSensor.fineDustLevel({value = 74 })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.fineDustHealthConcern.fineDustHealthConcern.good()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported pm1.0 and driver emit pm1.0 and veryFineDustHealthConcern",
  function()
    local attr_report_data = {
      { 0x0001, data_types.Uint16.ID, 69 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCC1, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.veryFineDustSensor.veryFineDustLevel({value = 69 })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.veryFineDustHealthConcern.veryFineDustHealthConcern.good()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported pm10 and driver emit pm10 and dustHealthConcern",
  function()
    local attr_report_data = {
      { 0x0002, data_types.Uint16.ID, 69 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCC1, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.dustSensor.dustLevel({value = 69 })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
     capabilities.dustHealthConcern.dustHealthConcern.good()))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported ch2o and driver emit ch2o",
  function()
    local attr_report_data = {
      { 0x0000, data_types.SinglePrecisionFloat.ID, SinglePrecisionFloat(0, 9, 0.953125) }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCC2, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.formaldehydeMeasurement.formaldehydeLevel({value = 1000.0, unit = "mg/m^3"})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported tvoc and driver emit tvoc",
  function()
    local attr_report_data = {
      { 0x0001, data_types.SinglePrecisionFloat.ID, SinglePrecisionFloat(0, 9, 0.953125) }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCC2, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.tvocMeasurement.tvocLevel({value = 1000.0, unit = "ug/m3"})))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.tvocHealthConcern.tvocHealthConcern({value = "unhealthy"})))
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "Device reported AQI and driver emit airQualityHealthConcern",
  function()
    local attr_report_data = {
      { 0x0000, data_types.Uint16.ID, 50 }
    }
    test.socket.zigbee:__queue_receive({
      mock_device.id,
      zigbee_test_utils.build_attribute_report(mock_device, 0xFCC5, attr_report_data, MFG_CODE)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.airQualityHealthConcern.airQualityHealthConcern({value = "good"})))
  end,
  {
     min_api_version = 19
  }
)

test.run_registered_tests()
