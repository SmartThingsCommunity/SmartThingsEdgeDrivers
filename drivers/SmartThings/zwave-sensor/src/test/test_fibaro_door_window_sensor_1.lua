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
local t_utils = require "integration_test.utils"

local Association = (require "st.zwave.CommandClass.Association")({ version = 1 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 2 })
local SensorAlarm = (require "st.zwave.CommandClass.SensorAlarm")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 1 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 2 })

local fibaro_door_window_sensor1_endpoints = {
  {
    command_classes = {
      { value = zw.ASSOCIATION },
      { value = zw.BASIC },
      { value = zw.BATTERY },
      { value = zw.SENSOR_ALARM },
      { value = zw.SENSOR_BINARY },
      { value = zw.SENSOR_MULTILEVEL }
    }
  }
}

local mock_fibaro_door_window_sensor1 = test.mock_device.build_test_zwave_device({
    profile = t_utils.get_profile_definition("contact-battery-tamperalert-temperature.yml"),
    zwave_endpoints = fibaro_door_window_sensor1_endpoints,
    zwave_manufacturer_id = 0x010F,
    zwave_product_type = 0x0501,
    zwave_product_id = 0x1002
})

test.mock_device.add_test_device(mock_fibaro_door_window_sensor1)

local function test_init()
    test.mock_device.add_test_device(mock_fibaro_door_window_sensor1)
end

test.set_test_init_function(test_init)

test.register_message_test(
  "Device should be polled with refresh right after inclusion",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor1.id, "added" }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor1,
        Battery:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor1,
        SensorBinary:Get({})
      )
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor1,
        SensorAlarm:Get({})
      )
    },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
    -- },
    -- {
    --   channel = "capability",
    --   direction = "send",
    --   message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.contactSensor.contact.open())
    -- }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
    "Device should be configured",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_fibaro_door_window_sensor1.id, "doConfigure"})
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=1, configuration_value=0, size=2})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=2, configuration_value=1, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=3, configuration_value=0, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=5, configuration_value=255, size=2})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=7, configuration_value=255, size=2})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=9, configuration_value=0, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=10, configuration_value=1, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=12, configuration_value=4, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=13, configuration_value=0, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Configuration:Set({parameter_number=14, configuration_value=0, size=1})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Association:Set({grouping_identifier = 2, node_ids = {}})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
          mock_fibaro_door_window_sensor1,
          Association:Set({grouping_identifier = 3, node_ids = {}})
        )
      )
      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
        mock_fibaro_door_window_sensor1,
        Association:Remove({grouping_identifier = 1, node_ids = {}})
      ))
      mock_fibaro_door_window_sensor1:expect_metadata_update({provisioning_state = "PROVISIONED"})
    end
)

test.register_message_test(
 "Battery report should be handled",
 {
   {
       channel = "zwave",
       direction = "receive",
       message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(Battery:Report({ battery_level = 0x63 })) }
   },
   {
       channel = "capability",
       direction = "send",
       message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.battery.battery(99))
   }
 }
)

test.register_message_test(
 "SensorAlarm report (tamper detected) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
       sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
       sensor_state = SensorAlarm.sensor_state.ALARM }))
     }
   },
   {
     channel = "capability",
     direction = "send",
     message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
   }
 }
)

test.register_message_test(
 "SensorAlarm report (tamper clear) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(SensorAlarm:Report({
       sensor_type = SensorAlarm.sensor_type.GENERAL_PURPOSE_ALARM,
       sensor_state = SensorAlarm.sensor_state.NO_ALARM }))
     }
   },
   {
     channel = "capability",
     direction = "send",
     message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.tamperAlert.tamper.clear())
   }
 }
)

test.register_message_test(
  "Basic report (contact / open) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF }))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.contactSensor.contact.open())
    }
  }
)

test.register_message_test(
  "Basic report (contact / closed) should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0x00 }))}
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.contactSensor.contact.closed())
    }
  }
)


test.register_message_test(
 "SensorBinary report (contact / open) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
       sensor_value = SensorBinary.sensor_value.DETECTED_AN_EVENT }))
     }
   },
   {
     channel = "capability",
     direction = "send",
     message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.contactSensor.contact.open())
   }
 }
)

test.register_message_test(
 "SensorBinary report (contact / closed) should be handled",
 {
   {
     channel = "zwave",
     direction = "receive",
     message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({
       sensor_value = SensorBinary.sensor_value.IDLE }))
     }
   },
   {
     channel = "capability",
     direction = "send",
     message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.contactSensor.contact.closed())
   }
 }
)

test.register_message_test(
  "Temperature reports should be handled (unit: C)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.CELSIUS,
        sensor_value = 21.5 }))
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 21.5, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Temperature reports should be handled (unit: F)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_fibaro_door_window_sensor1.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
        scale = SensorMultilevel.scale.temperature.FAHRENHEIT,
        sensor_value = 70.7 })) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_fibaro_door_window_sensor1:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 70.7, unit = 'F' }))
    }
  }
)

test.run_registered_tests()
