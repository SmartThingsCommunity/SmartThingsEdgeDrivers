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
local BarrierOperator = (require "st.zwave.CommandClass.BarrierOperator")({ version = 1 })
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 8 })
local SensorMultilevel = (require "st.zwave.CommandClass.SensorMultilevel")({ version = 11 })
local t_utils = require "integration_test.utils"
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 4 })

local GDO_CONFIG_PARAM_NO_UNATTENDED_WAIT = 1
local GDO_CONFIG_PARAM_NO_ACTIVATION_TIME = 2
local GDO_CONFIG_PARAM_NO_OPEN_TIMEOUT = 3
local GDO_CONFIG_PARAM_NO_CLOSE_TIMEOUT = 4
local GDO_CONFIG_PARAM_NO_SHAKE_SENSE = 5
local GDO_CONFIG_PARAM_NO_APP_RETRY = 6

local garage_door_endpoints = {
  {
    command_classes = {
      {value = zw.BARRIER_OPERATOR},
      {value = zw.CONFIGURATION},
      {value = zw.SENSOR_MULTILEVEL},
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_garage_door = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("eco-zw-gdo-profile.yml"),
  zwave_endpoints = garage_door_endpoints,
  zwave_manufacturer_id = 0x014A,
  zwave_product_type = 0x0007,
  zwave_product_id = 0x4731,
})

local function test_init()
  test.mock_device.add_test_device(mock_garage_door)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "BarrierOperator reports value 0x00 should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(BarrierOperator:Report({ state = BarrierOperator.state.CLOSED })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.closed())
      }
    }
)

test.register_message_test(
        "BarrierOperator reports value 0xFF should be handled as proper capabilities",
        {
            {
                channel = "zwave",
                direction = "receive",
                message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(BarrierOperator:Report({ state = BarrierOperator.state.OPEN })) }
            },
            {
                channel = "capability",
                direction = "send",
                message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.open())
            }
        }
)

test.register_message_test(
  "Refresh command should prompt correct response",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_garage_door.id, { capability = "refresh", component = "main", command = "refresh", args = {} } }
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_garage_door, BarrierOperator:Get({}))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_garage_door, Notification:Get({
                                                            v1_alarm_type = 0,
                                                            notification_type = Notification.notification_type.SYSTEM,
                                                            event = 0}))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_garage_door, Notification:Get({
                                                            v1_alarm_type = 0,
                                                            notification_type = Notification.notification_type.ACCESS_CONTROL,
                                                            event = 0}))
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_garage_door, SensorMultilevel:Get({}))
    }
  },
  {
    test_init = test_init,
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "doConfigure lifecycle event should generate the correct commands",
  {
    {
      channel = "device_lifecycle",
      direction = "receive",
      message = { mock_garage_door.id, "added" },
    },
    {
      channel = "capability",
      direction = "send",
      message = { mock_garage_door.id, {attribute_id="battery", capability_id="battery", component_id="sensor", state={value=100}}}
    },
    {
      channel = "capability",
      direction = "send",
      message = { mock_garage_door.id, {attribute_id="tamper", capability_id="tamperAlert", component_id="sensor", state={value="clear"}}}
    },
    {
      channel = "capability",
      direction = "send",
      message = { mock_garage_door.id, {attribute_id="contact", capability_id="contactSensor", component_id="sensor", state={value="closed"}}}
    },
    {
      channel = "capability",
      direction = "send",
      message = { mock_garage_door.id, {attribute_id="door", capability_id="doorControl", component_id="main", state={value="closed"}}}
    },
    {
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(mock_garage_door, BarrierOperator:Get({}))
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
    "Multi-level sensor reports for celcius should be handled as temperature capability",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
                                                                                        sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                                                                                        scale = 0,
                                                                                        sensor_value = 12.2999999,
                                                                                      })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 12.2999999, unit = 'C'}))
      }
    }
)

test.register_message_test(
        "Multi-level sensor reports fahrenheight should be handled as temperature capability",
        {
          {
              channel = "zwave",
              direction = "receive",
              message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(SensorMultilevel:Report({
                                                                                              sensor_type = SensorMultilevel.sensor_type.TEMPERATURE,
                                                                                              scale = 1,
                                                                                              sensor_value = 45.6
                                                                                            })) }
          },
          {
              channel = "capability",
              direction = "send",
              message = mock_garage_door:generate_test_message("main", capabilities.temperatureMeasurement.temperature({value = 45.6, unit = 'F'}))
          }
        }
)

test.register_coroutine_test(
    "doConfigure lifecycle event should generate the correct commands",
    function ()
      local updated_params = {}
      updated_params[GDO_CONFIG_PARAM_NO_UNATTENDED_WAIT] = {parameter = mock_garage_door.preferences.closeWaitPeriodSec}
      updated_params[GDO_CONFIG_PARAM_NO_ACTIVATION_TIME] = {parameter = mock_garage_door.preferences.activationTimeMS}
      updated_params[GDO_CONFIG_PARAM_NO_OPEN_TIMEOUT] = {parameter = mock_garage_door.preferences.doorOpenTimeoutSec}
      updated_params[GDO_CONFIG_PARAM_NO_CLOSE_TIMEOUT] = {parameter = mock_garage_door.preferences.doorCloseTimeoutSec}
      updated_params[GDO_CONFIG_PARAM_NO_SHAKE_SENSE] = {parameter = mock_garage_door.preferences.shakeSensitivity}
      updated_params[GDO_CONFIG_PARAM_NO_APP_RETRY] = {parameter = mock_garage_door.preferences.applicationLevelRetries}

      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_garage_door.id, "doConfigure"})
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_garage_door,
          Configuration:BulkSetV2({parameter_offset = 1,
          size = 2,
          handshake = false,
          default = false,
          parameters = updated_params})
      ))
      mock_garage_door:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
)

test.register_coroutine_test(
    "Door control commands should generate correct zwave commands",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_garage_door.id,
            { capability = "doorControl", command = "open", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_garage_door,
              BarrierOperator:Set({ target_value = BarrierOperator.state.OPEN })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_garage_door,
              BarrierOperator:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "Door control close commands should generate correct zwave commands",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.capability:__queue_receive(
          {
            mock_garage_door.id,
            { capability = "doorControl", command = "close", args = {} }
          }
      )
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_garage_door,
                  BarrierOperator:Set({ target_value = BarrierOperator.state.CLOSED })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_garage_door,
                  BarrierOperator:Get({})
          )
      )
    end
  )

test.register_coroutine_test(
  "Open commands should generate correct zwave commands",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__queue_receive({mock_garage_door.id,
                      BarrierOperator:Set({ target_value = BarrierOperator.state.OPEN
                    })}
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
    end
  )

  test.register_coroutine_test(
  "Close commands should generate correct zwave commands",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(1, "oneshot")
      test.socket.zwave:__queue_receive({mock_garage_door.id,
                      BarrierOperator:Set({ target_value = BarrierOperator.state.CLOSED
                    })}
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
    end
  )

test.run_registered_tests()
