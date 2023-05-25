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
local test_utils = require "integration_test.utils"
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4})
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 5 })
local t_utils = require "integration_test.utils"

local multi_switch_endpoints = {
  {
    command_classes = {
      {value = zw.SENSOR_MULTILEVEL},
    }
  }
}

local parent_profile = test_utils.get_profile_definition("dawon-wall-smart-switch.yml")
local child_profile = test_utils.get_profile_definition("child-switch.yml")

local base_parent = test.mock_device.build_test_zwave_device({
  label = "Dawon Wall Smart Switch",
  profile = parent_profile,
  zwave_endpoints = multi_switch_endpoints,
  zwave_manufacturer_id = 0x018C,
  zwave_product_type = 0x0061,
  zwave_product_id = 0x0001
})

local mock_multi_switch = test.mock_device.build_test_zwave_device({
  profile = parent_profile,
  zwave_endpoints = multi_switch_endpoints,
  zwave_manufacturer_id = 0x018C,
  zwave_product_type = 0x0061,
  zwave_product_id = 0x0001
})

local mock_child = test.mock_device.build_test_child_device({
  profile = child_profile,
  parent_device_id = mock_multi_switch.id,
  parent_assigned_child_key = string.format("%02X", 2)
})

local function test_init()
  test.mock_device.add_test_device(base_parent)
  test.mock_device.add_test_device(mock_multi_switch)
  test.mock_device.add_test_device(mock_child)  
end
test.set_test_init_function(test_init)

test.register_message_test(
  "SensorMultilevel relative humidity sensor type should generate proper capability for main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_multi_switch.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY,
          sensor_value = 22 }))
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = { 0 }
        }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_multi_switch:generate_test_message("main", capabilities.relativeHumidityMeasurement.humidity({ value = 22 }))
    }
  }
)

test.register_message_test(
  "SensorMultilevel temperature sensor type should generate proper capability for main component",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_multi_switch.id,
        zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
          sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
          sensor_value = 25 }))
        },
        {
          encap = zw.ENCAP.AUTO,
          src_channel = 0,
          dst_channels = { 0 }
        }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_multi_switch:generate_test_message("main", capabilities.temperatureMeasurement.temperature({ value = 25, unit = 'C' }))
    }
  }
)

test.register_message_test(
  "Notification report should generate switch capability on to proper component (switch1)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_child.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report({
            notification_type = Notification.notification_type.POWER_MANAGEMENT,
            event = Notification.event.power_management.AC_MAINS_RE_CONNECTED
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 1,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.switch.switch.on())
    }
  }
)

test.register_message_test(
  "Notification report should generate switch capability off to proper component (switch1)",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_child.id,
        zw_test_utils.zwave_test_build_receive_command(
          Notification:Report({
            notification_type = Notification.notification_type.POWER_MANAGEMENT,
            event = Notification.event.power_management.AC_MAINS_DISCONNECTED
          },
          {
            encap = zw.ENCAP.AUTO,
            src_channel = 1,
            dst_channels = { 0 }
          })
        )
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_child:generate_test_message("main", capabilities.switch.switch.off())
    }
  }
)

test.register_coroutine_test(
    "infoChanged() and doConfigure() should send the SET command for Configuation value",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle():__queue_receive(mock_multi_switch:generate_info_changed(
          {
              preferences = {
                reportingInterval = 10
              }
          }
      ))
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_multi_switch,
              Configuration:Set({parameter_number = 1, size = 2, configuration_value = 10 * 60})
          )
      )
    end
)

test.register_coroutine_test(
    "added lifecycle event should create children in parent device",
    function()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ base_parent.id, "added" })
      base_parent:expect_device_create({
        type = "EDGE_CHILD",
        label = "Dawon Wall Smart Switch",
        profile = "child-switch",
        parent_device_id = base_parent.id,
        parent_assigned_child_key = "01"
      })

      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              base_parent,
              SensorMultilevel:Get(
                {sensor_type = SensorMultilevel.sensor_type.TEMPERATURE}
        )
      )
        )

      test.socket.zwave:__expect_send(
        zw_test_utils.zwave_test_build_send_command(
            base_parent,
            SensorMultilevel:Get({sensor_type = SensorMultilevel.sensor_type.RELATIVE_HUMIDITY}
      )
        )
      )
  
    end
)

test.run_registered_tests()
