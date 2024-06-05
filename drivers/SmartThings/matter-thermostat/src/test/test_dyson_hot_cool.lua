local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"

local clusters = require "st.matter.clusters"

-- dyson device
-- local mock_device_dyson = test.mock_device.build_test_matter_device({
--   profile = t_utils.get_profile_definition("thermostat-humidity.yml"),
--   manufacturer_info = {
--     vendor_id = 0x0000,
--     product_id = 0x0000,
--   },
--   endpoints = {
--     {
--       endpoint_id = 0,
--       clusters = {
--         {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
--       },
--       device_types = {
--         {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
--       }
--     },
--     {
--       endpoint_id = 1,
--       clusters = {
--         {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER"},
--       },
--     },
--     {
--       endpoint_id = 2,
--       clusters = {
--         {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.CarbonMonoxideConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.CarbonDioxideConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.NitrogenDioxideConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.OzoneConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.FormaldehydeConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.Pm1ConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.Pm25ConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.Pm10ConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.RadonConcentrationMeasurement.ID, cluster_type = "SERVER"},
--         {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER"},
--       },
--       device_types = {
--         {device_type_id = 0x002C, device_type_revision = 1} -- Air Quality Sensor
--       }
--     },
--     {
--     endpoint_id = 3,
--     clusters = {
--       {cluster_id = clusters.TemperatureMeasurement.ID, cluster_type = "SERVER"},
--     },
--     device_types = {
--       {device_type_id = 0x0302, device_type_revision = 1} -- Temperature Sensor
--     }
--     },
--     {
--       endpoint_id = 4,
--       clusters = {
--         {cluster_id = clusters.RelativeHumidityMeasurement.ID, cluster_type = "SERVER"},
--       },
--       device_types = {
--         {device_type_id = 0x0307, device_type_revision = 1} -- Humidity Sensor
--       }
--     },
--     {
--       endpoint_id = 5,
--       clusters = {
--         {cluster_id = clusters.Thermostat.ID, cluster_type = "SERVER"},
--       },
--       device_types = {
--         {device_type_id = 0x0301, device_type_revision = 1} -- Thermostat
--       }
--     }
--   }
-- })

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("air-purifier-hepa-ac-wind.yml"),
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
        {cluster_id = clusters.FanControl.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.HepaFilterMonitoring.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.ActivatedCarbonFilterMonitoring.ID, cluster_type = "SERVER"},
      }
    },
    {
      endpoint_id = 2,
      clusters = {
        {cluster_id = clusters.AirQuality.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.RadonConcentrationMeasurement.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.ID, cluster_type = "SERVER"},
      },
      device_types = {
        {device_type_id = 0x002C, device_type_revision = 1} -- Air Quality Sensor
      }
    },
  }
})

local cluster_subscribe_list = {
  clusters.FanControl.attributes.FanModeSequence,
  clusters.FanControl.attributes.FanMode,
  clusters.FanControl.attributes.PercentCurrent,
  clusters.FanControl.attributes.WindSupport,
  clusters.FanControl.attributes.WindSetting,
  clusters.HepaFilterMonitoring.attributes.ChangeIndication,
  clusters.HepaFilterMonitoring.attributes.Condition,
  clusters.ActivatedCarbonFilterMonitoring.attributes.ChangeIndication,
  clusters.ActivatedCarbonFilterMonitoring.attributes.Condition,
  -- clusters.AirQuality.attributes.AirQuality,
  -- clusters.RadonConcentrationMeasurement.attributes.MeasuredValue,
  -- clusters.RadonConcentrationMeasurement.attributes.MeasurementUnit,
  -- clusters.RadonConcentrationMeasurement.attributes.LevelValue,
  -- clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasuredValue,
  -- clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.MeasurementUnit,
  -- clusters.TotalVolatileOrganicCompoundsConcentrationMeasurement.attributes.LevelValue,
}

local function test_init()
  local subscribe_request = cluster_subscribe_list[1]:subscribe(mock_device)
  for i, cluster in ipairs(cluster_subscribe_list) do
    if i > 1 then
      subscribe_request:merge(cluster:subscribe(mock_device))
    end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.mock_device.add_test_device(mock_device)
  mock_device:expect_metadata_update({ profile = "thermostat-humidity-fan-heating-only-nostate-nobattery-air-purifier-sensor" })
end

test.register_coroutine_test(
  "Dyson",
  function()
  end,
  { test_init = test_init }
)

test.run_registered_tests()