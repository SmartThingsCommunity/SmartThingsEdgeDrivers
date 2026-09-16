-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"

-- Unit conversion utilities for sensor
local air_quality_sensor_utils = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.utils"
local air_quality_sensor_fields = require "sub_drivers.air_quality_sensor.air_quality_sensor_utils.fields"

local units = air_quality_sensor_fields.units

test.register_coroutine_test(
  "Unsupported unit conversion from PPT to MGM3 should return nil",
  function()
    local result = air_quality_sensor_utils.convert_value_to_unit(100, units.PPT, units.MGM3, capabilities.ozoneMeasurement.NAME)
    assert(result == nil, "Expected nil for unsupported PPT to MGM3 conversion, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "Unsupported unit conversion from PPB to UGM3 should return nil",
  function()
    local result = air_quality_sensor_utils.convert_value_to_unit(100, units.PPB, units.UGM3, capabilities.carbonMonoxideMeasurement.NAME)
    assert(result == nil, "Expected nil for unsupported PPB to UGM3 conversion, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "Unsupported unit conversion from NGM3 to PPM should return nil",
  function()
    local result = air_quality_sensor_utils.convert_value_to_unit(100, units.NGM3, units.PPM, capabilities.carbonMonoxideMeasurement.NAME)
    assert(result == nil, "Expected nil for unsupported NGM3 to PPM conversion, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "Supported unit conversion from PPM to PPB should return correct value",
  function()
    local result = air_quality_sensor_utils.convert_value_to_unit(100, units.PPM, units.PPB, capabilities.carbonMonoxideMeasurement.NAME)
    assert(result ~= nil, "Expected a value for supported PPM to PPB conversion")
    assert(result == 100000, "Expected 100000 for PPM to PPB conversion, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "Supported unit conversion from PPB to PPM should return correct value",
  function()
    local result = air_quality_sensor_utils.convert_value_to_unit(1000, units.PPB, units.PPM, capabilities.carbonMonoxideMeasurement.NAME)
    assert(result ~= nil, "Expected a value for supported PPB to PPM conversion")
    assert(result == 1, "Expected 1 for PPB to PPM conversion, got: " .. tostring(result))
  end
)

test.register_coroutine_test(
  "Unit conversion with non-numeric value should return nil",
  function()
    local result = air_quality_sensor_utils.convert_value_to_unit("not a number", units.PPM, units.PPB, capabilities.carbonMonoxideMeasurement.NAME)
    assert(result == nil, "Expected nil when value is not a number, got: " .. tostring(result))
  end
)

test.run_registered_tests()
