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
local capabilities = require "st.capabilities"
local zw = require "st.zwave"
local zw_test_utils = require "integration_test.zwave_test_utils"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 7 })
local Meter = (require "st.zwave.CommandClass.Meter")({ version = 3 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local t_utils = require "integration_test.utils"

local KILO_PASCAL_PER_INCH_OF_MERCURY = 3.386389

-- supported command classes
local switch_endpoints = {
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SENSOR_BINARY },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.SENSOR_ALARM },
      { value = zw.NOTIFICATION },
      { value = zw.BATTERY },
      { value = zw.METER },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SENSOR_BINARY },
      { value = zw.SENSOR_ALARM },
      { value = zw.NOTIFICATION },
      { value = zw.MULTI_CHANNEL }
    }
  },
  {
    command_classes = {
      { value = zw.BASIC },
      { value = zw.SENSOR_MULTILEVEL },
      { value = zw.BATTERY },
      { value = zw.METER },
      { value = zw.MULTI_CHANNEL }
    }
  }
}

local mock_parent = test.mock_device.build_test_zwave_device({
  label = "Z-Wave Switch Multichannel",
  profile = t_utils.get_profile_definition("multichannel-generic-sensor.yml"),
  zwave_endpoints = switch_endpoints
})

local mock_child = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("generic-sensor.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 1)
})

local mock_child_2 = test.mock_device.build_test_child_device({
  profile = t_utils.get_profile_definition("generic-sensor.yml"),
  parent_device_id = mock_parent.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(mock_parent)
  test.mock_device.add_test_device(mock_child)
  test.mock_device.add_test_device(mock_child_2)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "SensorMultilevel report (parent) atmospheric pressure type should be handled as atmosphericPressure",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.ATMOSPHERIC_PRESSURE,
                sensor_value = 101.3,
                scale = SensorMultilevel.scale.atmospheric_pressure.KILOPASCALS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 101.3, unit = "kPa" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) atmospheric pressure type should be handled as atmosphericPressure",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.ATMOSPHERIC_PRESSURE,
                sensor_value = 101.3,
                scale = SensorMultilevel.scale.atmospheric_pressure.KILOPASCALS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 101.3, unit = "kPa" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) barometric pressure type should be handled as atmosphericPressure",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.ATMOSPHERIC_PRESSURE,
                sensor_value = 30.13,
                scale = SensorMultilevel.scale.atmospheric_pressure.INCHES_OF_MERCURY
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 30.13 * KILO_PASCAL_PER_INCH_OF_MERCURY, unit = "kPa" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) barometric pressure type should be handled as atmosphericPressure",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.BAROMETRIC_PRESSURE,
                sensor_value = 30.13,
                scale = SensorMultilevel.scale.atmospheric_pressure.INCHES_OF_MERCURY
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.atmosphericPressureMeasurement.atmosphericPressure({ value = 30.13 * KILO_PASCAL_PER_INCH_OF_MERCURY, unit = "kPa" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) body weight type should be handled as bodyWeightMeasurement",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.WEIGHT,
                sensor_value = 60
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.bodyWeightMeasurement.bodyWeightMeasurement({ value = 60, unit = "kg" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) body weight type should be handled as bodyWeightMeasurement",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.WEIGHT,
                sensor_value = 60
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.bodyWeightMeasurement.bodyWeightMeasurement({ value = 60, unit = "kg" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) body weight type should be handled as bodyWeightMeasurement",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.WEIGHT,
                sensor_value = 120,
                scale = SensorMultilevel.scale.weight.POUNDS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.bodyWeightMeasurement.bodyWeightMeasurement({ value = 120, unit = "lbs" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) body weight type should be handled as bodyWeightMeasurement",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.WEIGHT,
                sensor_value = 120,
                scale = SensorMultilevel.scale.weight.POUNDS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.bodyWeightMeasurement.bodyWeightMeasurement({ value = 120, unit = "lbs" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) luminance type should be handled as illuminance",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
                sensor_value = 700,
                scale = SensorMultilevel.scale.luminance.LUX
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 700, unit = "lux" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) luminance type should be handled as illuminance",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.LUMINANCE,
                sensor_value = 700,
                scale = SensorMultilevel.scale.luminance.LUX
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.illuminanceMeasurement.illuminance({ value = 700, unit = "lux" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) humidity should be handled as humidity",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
                sensor_value = 70
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 70 }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) humidity should be handled as humidity",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
                sensor_value = 70
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 70 }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) temperature should be handled as temperature",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                sensor_value = 30,
                scale = SensorMultilevel.scale.temperature.CELSIUS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 30, unit = "C" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) temperature should be handled as temperature",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                sensor_value = 30,
                scale = SensorMultilevel.scale.temperature.CELSIUS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 30, unit = "C" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) temperature should be handled as temperature",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                sensor_value = 70,
                scale = SensorMultilevel.scale.temperature.FAHRENHEIT
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 70, unit = "F" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) temperature should be handled as temperature",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                sensor_value = 70,
                scale = SensorMultilevel.scale.temperature.FAHRENHEIT
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 70, unit = "F" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (parent) voltage should be handled as voltage",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.VOLTAGE,
                sensor_value = 50,
                scale = SensorMultilevel.scale.voltage.MILLIVOLTS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.voltageMeasurement.voltage({ value = 0.005, unit = "V" }))
      }
    }
)

test.register_message_test(
    "SensorMultilevel report (child 2) voltage should be handled as voltage",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.VOLTAGE,
                sensor_value = 50,
                scale = SensorMultilevel.scale.voltage.MILLIVOLTS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.voltageMeasurement.voltage({ value = 0.005, unit = "V" }))
      }
    }
)

test.register_message_test(
    "Power meter report (parent) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report({
                meter_value = 50,
                scale = Meter.scale.electric_meter.WATTS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.powerMeter.power({ value = 50, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Power meter report (child 2) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report({
                meter_value = 50,
                scale = Meter.scale.electric_meter.WATTS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.powerMeter.power({ value = 50, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Power meter report (SENSOR_MULTILEVEL) (parent) voltage should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.POWER,
                sensor_value = 50,
                scale = SensorMultilevel.scale.power.WATTS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.powerMeter.power({ value = 50, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Power meter report (SENSOR_MULTILEVEL) (child 2) voltage should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorMultilevel:Report({
                sensor_type = SensorMultilevel.sensor_type.POWER,
                sensor_value = 50,
                scale = SensorMultilevel.scale.power.WATTS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.powerMeter.power({ value = 50, unit = "W" }))
      }
    }
)

test.register_message_test(
    "Energy meter report (parent) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report({
                meter_value = 50,
                scale = Meter.scale.electric_meter.KILOWATT_HOURS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.energyMeter.energy({ value = 50, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Energy meter report (child 2) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report({
                meter_value = 50,
                scale = Meter.scale.electric_meter.KILOWATT_HOURS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.energyMeter.energy({ value = 50, unit = "kWh" }))
      }
    }
)

test.register_message_test(
    "Energy meter report (parent) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report({
                meter_value = 50,
                scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.energyMeter.energy({ value = 50, unit = "kVAh" }))
      }
    }
)

test.register_message_test(
    "Energy meter report (child 2) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Meter:Report({
                meter_value = 50,
                scale = Meter.scale.electric_meter.KILOVOLT_AMPERE_HOURS
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.energyMeter.energy({ value = 50, unit = "kVAh" }))
      }
    }
)

test.register_message_test(
    "Energy meter (parent) capability resetEnergyMeter command should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_parent.id, { capability = "energyMeter", command = "resetEnergyMeter", args = {} } }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Reset({}))
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }))
      }
    }
)

test.register_message_test(
    "Energy meter (child 2) capability resetEnergyMeter command should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_child_2.id, { capability = "energyMeter", command = "resetEnergyMeter", args = {} } }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Reset({}, { dst_channels = { 2 } }))
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = Meter.scale.electric_meter.KILOWATT_HOURS }, { dst_channels = { 2 } }))
      }
    }
)

test.register_message_test(
    "Basic report (parent) 0x00 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0x00
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.dry())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = 2 }))
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Basic report (child 1) 0x00 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0x00
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.dry())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = 2 }))
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Basic report (child 2) 0x00 should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0x00
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.waterSensor.water.dry())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = 2 }))
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Basic report (parent) 0xFF should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0xFF
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.wet())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = 2 }))
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Basic report (child 1) 0xFF should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0xFF
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.wet())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = 2 }))
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Basic report (child 2) 0xFF should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Basic:Report({
                value = 0xFF
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.waterSensor.water.wet())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(mock_parent, Meter:Get({ scale = 2 }))
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "SensorBinary report (parent) DOOR_WINDOW - DETECTED_AN_EVENT should be handled as contact open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "SensorBinary report (child) DOOR_WINDOW - DETECTED_AN_EVENT should be handled as contact open",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "SensorBinary report (parent) DOOR_WINDOW - IDLE should be handled as contact closed",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
                sensor_value = SensorBinary.sensor_value.IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "SensorBinary report (child) DOOR_WINDOW - IDLE should be handled as contact closed",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.DOOR_WINDOW,
                sensor_value = SensorBinary.sensor_value.IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "SensorAlarm report (parent) GENERAL_PURPOSE_ALARM - ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "SensorAlarm report (child) GENERAL_PURPOSE_ALARM - ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      }
    }
)

test.register_message_test(
    "SensorAlarm report (parent) GENERAL_PURPOSE_ALARM - NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "SensorAlarm report (child) GENERAL_PURPOSE_ALARM - NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for home_security and access_control events (contactSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for home_security and access_control events (contactSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.WINDOW_DOOR_IS_OPEN
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.WINDOW_DOOR_IS_CLOSED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for home_security events (motionSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.MOTION_DETECTION_LOCATION_PROVIDED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.MOTION_DETECTION
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
    }
)

test.register_message_test(
    "Notification reports (child) for home_security events (motionSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION_LOCATION_PROVIDED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.INTRUSION
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.MOTION_DETECTION_LOCATION_PROVIDED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.MOTION_DETECTION
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.active())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
    }
)

test.register_message_test(
    "Notification reports (parent) for SMOKE events (smokeDetector) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.DETECTED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.DETECTED_LOCATION_PROVIDED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.ALARM_TEST
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.ALARM_SILENCED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.UNKNOWN_EVENT_STATE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for SMOKE events (smokeDetector) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.DETECTED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.DETECTED_LOCATION_PROVIDED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.ALARM_TEST
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.tested())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.ALARM_SILENCED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SMOKE,
                event = Notification.event.smoke.UNKNOWN_EVENT_STATE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "SensorBinary SMOKE report (parent) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.SMOKE,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "SensorBinary SMOKE report (child) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.SMOKE,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "SensorBinary SMOKE report (parent) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.SMOKE,
                sensor_value = SensorBinary.sensor_value.IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "SensorBinary SMOKE report (child) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.SMOKE,
                sensor_value = SensorBinary.sensor_value.IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "SensorAlarm SMOKE report (parent) ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "SensorAlarm SMOKE report (child) ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.detected())
      }
    }
)

test.register_message_test(
    "SensorAlarm SMOKE report (parent) NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "SensorAlarm SMOKE report (child) NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.SMOKE_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.smokeDetector.smoke.clear())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.TAMPERING_PRODUCT_COVER_REMOVED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.TAMPERING_INVALID_CODE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.TAMPERING_INVALID_CODE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.TAMPERING_PRODUCT_MOVED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.TAMPERING_PRODUCT_MOVED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Notification reports (child) for HOME_SECURITY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.HOME_SECURITY,
                event = Notification.event.home_security.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.motionSensor.motion.inactive())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Notification reports (parent) for SYSTEM events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SYSTEM,
                event = Notification.event.system.TAMPERING_PRODUCT_COVER_REMOVED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for SYSTEM events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SYSTEM,
                event = Notification.event.system.TAMPERING_PRODUCT_COVER_REMOVED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for SYSTEM events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SYSTEM,
                event = Notification.event.system.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for SYSTEM events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.SYSTEM,
                event = Notification.event.system.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for ACCESS_CONTROL events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.MANUALLY_ENTER_USER_ACCESS_CODE_EXCEEDS_CODE_LIMIT
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for ACCESS_CONTROL events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.MANUALLY_ENTER_USER_ACCESS_CODE_EXCEEDS_CODE_LIMIT
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for ACCESS_CONTROL events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Notification reports (child) for ACCESS_CONTROL events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.ACCESS_CONTROL,
                event = Notification.event.access_control.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Notification reports (parent) for EMERGENCY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.EMERGENCY,
                event = Notification.event.emergency.CONTACT_POLICE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for EMERGENCY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.EMERGENCY,
                event = Notification.event.emergency.CONTACT_POLICE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for EMERGENCY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.EMERGENCY,
                event = Notification.event.emergency.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for EMERGENCY events (tamperAlert) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.EMERGENCY,
                event = Notification.event.emergency.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "SensorBinary TAMPER report (parent) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.TAMPER,
                sensor_value = SensorBinary.sensor_value.IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "SensorBinary TAMPER report (child) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.TAMPER,
                sensor_value = SensorBinary.sensor_value.IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
      }
    }
)

test.register_message_test(
    "SensorBinary TAMPER report (parent) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.TAMPER,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "SensorBinary TAMPER report (child) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.TAMPER,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.LEAK_DETECTED_LOCATION_PROVIDED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.LEAK_DETECTED_LOCATION_PROVIDED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.LEAK_DETECTED
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.LEAK_DETECTED
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.STATE_IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.STATE_IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.UNKNOWN_EVENT_STATE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Notification reports (child) for WATER events (waterSensor) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.WATER,
                event = Notification.event.water.UNKNOWN_EVENT_STATE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "SensorBinary WATER report (parent) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.WATER,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "SensorBinary WATER report (child) DETECTED_AN_EVENT should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.WATER,
                sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "SensorBinary WATER report (parent) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.WATER,
                sensor_value = SensorBinary.sensor_value.IDLE
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "SensorBinary WATER report (child) IDLE should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorBinary:Report({
                sensor_type = SensorBinary.sensor_type.WATER,
                sensor_value = SensorBinary.sensor_value.IDLE
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "SensorAlarm WATER_LEAK_ALARM report (parent) ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "SensorAlarm WATER_LEAK_ALARM report (child) ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
                sensor_state = SensorAlarm.sensor_state.ALARM
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.wet())
      }
    }
)

test.register_message_test(
    "SensorAlarm WATER_LEAK_ALARM report (parent) NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "SensorAlarm WATER_LEAK_ALARM report (child) NO_ALARM should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              SensorAlarm:Report({
                sensor_type = SensorAlarm.sensor_type.WATER_LEAK_ALARM,
                sensor_state = SensorAlarm.sensor_state.NO_ALARM
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.waterSensor.water.dry())
      }
    }
)

test.register_message_test(
    "Battery report (parent) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Battery:Report({
                battery_level = 55
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.battery.battery(55))
      }
    }
)

test.register_message_test(
    "Battery report (child 2) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Battery:Report({
                battery_level = 55
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.battery.battery(55))
      }
    }
)

test.register_message_test(
    "Battery report (parent) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Battery:Report({
                battery_level = Battery.battery_level.BATTERY_LOW_WARNING
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.battery.battery(1))
      }
    }
)

test.register_message_test(
    "Battery report (child 2) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Battery:Report({
                battery_level = Battery.battery_level.BATTERY_LOW_WARNING
              }, {
                src_channel = 2
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child_2:generate_test_message("main", capabilities.battery.battery(1))
      }
    }
)

test.register_coroutine_test(
    "Notification reports (parent) for POWER_MANAGEMENT events (battery) should be handled",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
      test.socket.zwave:__queue_receive({
        mock_parent.id,
        zw_test_utils.zwave_test_build_receive_command(
            Notification:Report({
              notification_type = Notification.notification_type.POWER_MANAGEMENT,
              event = Notification.event.power_management.POWER_HAS_BEEN_APPLIED
            })
        )
      })
      test.wait_for_events()
      test.mock_time.advance_time(10)
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(mock_parent, Battery:Get({})))
    end
)

test.register_coroutine_test(
    "Notification reports (child) for POWER_MANAGEMENT events (battery) should be handled",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(10, "oneshot")
      test.socket.zwave:__queue_receive({
        mock_parent.id,
        zw_test_utils.zwave_test_build_receive_command(
            Notification:Report({
              notification_type = Notification.notification_type.POWER_MANAGEMENT,
              event = Notification.event.power_management.POWER_HAS_BEEN_APPLIED
            }, {
              src_channel = 1
            })
        )
      })
      test.wait_for_events()
      test.mock_time.advance_time(10)
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(mock_parent, Battery:Get({})))
    end
)

test.register_message_test(
    "Notification reports (parent) for POWER_MANAGEMENT events (battery) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.POWER_MANAGEMENT,
                event = Notification.event.power_management.REPLACE_BATTERY_SOON
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.battery.battery(1))
      }
    }
)

test.register_message_test(
    "Notification reports (child) for POWER_MANAGEMENT events (battery) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.POWER_MANAGEMENT,
                event = Notification.event.power_management.REPLACE_BATTERY_SOON
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.battery.battery(1))
      }
    }
)

test.register_message_test(
    "Notification reports (parent) for POWER_MANAGEMENT events (battery) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.POWER_MANAGEMENT,
                event = Notification.event.power_management.REPLACE_BATTERY_NOW
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_parent:generate_test_message("main", capabilities.battery.battery(0))
      }
    }
)

test.register_message_test(
    "Notification reports (child) for POWER_MANAGEMENT events (battery) should be handled",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = {
          mock_parent.id,
          zw_test_utils.zwave_test_build_receive_command(
              Notification:Report({
                notification_type = Notification.notification_type.POWER_MANAGEMENT,
                event = Notification.event.power_management.REPLACE_BATTERY_NOW
              }, {
                src_channel = 1
              })
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_child:generate_test_message("main", capabilities.battery.battery(0))
      }
    }
)

test.register_message_test(
    "Refresh capability command should refresh device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_parent.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Battery:Get({})
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.SMOKE })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.WATER })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.DOOR_WINDOW })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.WEIGHT, scale = 0 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY, scale = 0 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE, scale = 0 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.VOLTAGE, scale = 0 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = 1 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.BAROMETRIC_PRESSURE, scale = 0 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 2 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 0 })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Battery:Get({}, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.SMOKE }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.WATER }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.DOOR_WINDOW }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.WEIGHT, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.VOLTAGE, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = 1 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.BAROMETRIC_PRESSURE, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 2 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Battery:Get({}, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.SMOKE }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.WATER }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.DOOR_WINDOW }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.WEIGHT, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.VOLTAGE, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = 1 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.BAROMETRIC_PRESSURE, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 2 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 0 }, { dst_channels = { 2 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Refresh capability command should refresh device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_child.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Battery:Get({}, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.SMOKE }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.WATER }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.DOOR_WINDOW }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.WEIGHT, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.VOLTAGE, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = 1 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.BAROMETRIC_PRESSURE, scale = 0 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 2 }, { dst_channels = { 1 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 0 }, { dst_channels = { 1 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.register_message_test(
    "Refresh capability command should refresh device",
    {
      {
        channel = "capability",
        direction = "receive",
        message = {
          mock_child_2.id,
          { capability = "refresh", command = "refresh", args = {} }
        }
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Battery:Get({}, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.SMOKE }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.MOTION }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.WATER }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorBinary:Get({ sensor_type = SensorBinary.sensor_type.DOOR_WINDOW }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.WEIGHT, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.TEMPERATURE, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.VOLTAGE, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.LUMINANCE, scale = 1 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            SensorMultilevel:Get({ sensor_type = SensorMultilevel.sensor_type.BAROMETRIC_PRESSURE, scale = 0 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 2 }, { dst_channels = { 2 } })
        )
      },
      {
        channel = "zwave",
        direction = "send",
        message = zw_test_utils.zwave_test_build_send_command(
            mock_parent,
            Meter:Get({ scale = 0 }, { dst_channels = { 2 } })
        )
      }
    },
    {
      inner_block_ordering = "relaxed"
    }
)

test.run_registered_tests()