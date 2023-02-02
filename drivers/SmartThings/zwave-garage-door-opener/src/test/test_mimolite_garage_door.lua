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
local Association = (require "st.zwave.CommandClass.Association")({ version = 2 })
local Basic = (require "st.zwave.CommandClass.Basic")({ version = 1 })
local Configuration = (require "st.zwave.CommandClass.Configuration")({ version = 1 })
local SensorBinary = (require "st.zwave.CommandClass.SensorBinary")({ version = 2 })
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })
local t_utils = require "integration_test.utils"

local garage_door_endpoints = {
  {
    command_classes = {
      {value = zw.ASSOCIATION},
      {value = zw.BASIC},
      {value = zw.CONFIGURATION},
      {value = zw.SENSOR_BINARY},
      {value = zw.SWITCH_BINARY}
    }
  }
}

local mock_garage_door = test.mock_device.build_test_zwave_device({
  profile = t_utils.get_profile_definition("base-garage-door.yml"),
  zwave_endpoints = garage_door_endpoints,
  zwave_manufacturer_id = 0x0084,
  zwave_product_type = 0x0453,
  zwave_product_id = 0x0111,
})

local function test_init()
  test.mock_device.add_test_device(mock_garage_door)
end

test.set_test_init_function(test_init)

test.register_message_test(
    "Basic reports value 0x00 should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Basic reports value 0xFF should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Basic set value 0x00 should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Basic set value 0xFF should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(Basic:Set({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Sensor binary reports value 0xFF should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({ sensor_value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.closed())
      }
    }
)

test.register_message_test(
    "Sensor binary reports value 0xFF should be handled as proper capabilities",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(SensorBinary:Report({ sensor_value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.open())
      }
    }
)

test.register_message_test(
    "Switch binary reports should be handled according to the contact state(close)",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0xFF })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.open())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.open())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({ current_value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.closing())
      }
    }
)

test.register_message_test(
    "Switch binary reports should be handled according to the contact state(open)",
    {
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(Basic:Report({ value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.closed())
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.contactSensor.contact.closed())
      },
      {
        channel = "zwave",
        direction = "receive",
        message = { mock_garage_door.id, zw_test_utils.zwave_test_build_receive_command(SwitchBinary:Report({ current_value = 0x00 })) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_garage_door:generate_test_message("main", capabilities.doorControl.door.opening())
      }
    }
)

test.register_coroutine_test(
    "Door control open commands should generate correct zwave commands",
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
              Basic:Set({ value = 0xFF })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_garage_door,
              Basic:Get({})
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
              Basic:Set({ value = 0x00 })
          )
      )
      test.wait_for_events()
      test.mock_time.advance_time(1)
      test.socket.zwave:__expect_send(
          zw_test_utils.zwave_test_build_send_command(
              mock_garage_door,
              Basic:Get({})
          )
      )
    end
)

test.register_coroutine_test(
    "doConfigure lifecycle event should generate the correct commands",
    function ()
      test.socket.zwave:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({mock_garage_door.id, "doConfigure"})
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_garage_door,
          Configuration:Set({parameter_number = 11, size = 1, configuration_value = 25})
      ))
      test.socket.zwave:__expect_send(zw_test_utils.zwave_test_build_send_command(
          mock_garage_door,
          Association:Set({grouping_identifier = 3, node_ids = {}})
      ))
      mock_garage_door:expect_metadata_update({ provisioning_state = "PROVISIONED" })
    end
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
      channel = "zwave",
      direction = "send",
      message = zw_test_utils.zwave_test_build_send_command(
        mock_garage_door,
        Basic:Get({})
      )
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)
test.run_registered_tests()
