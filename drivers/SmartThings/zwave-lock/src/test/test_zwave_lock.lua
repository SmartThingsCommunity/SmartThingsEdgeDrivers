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
local json = require "dkjson"
--- @type st.zwave.constants
local constants = require "st.zwave.constants"
--- @type st.zwave.CommandClass.DoorLock
local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({ version = 3 })
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Alarm
local Alarm = (require "st.zwave.CommandClass.Alarm")({ version = 1 })
local t_utils = require "integration_test.utils"
local zw_test_utils = require "integration_test.zwave_test_utils"

-- supported comand classes
local zwave_lock_endpoints = {
  {
    command_classes = {
      {value = zw.BATTERY},
      {value = DoorLock},
      {value = zw.USER_CODE},
      {value = zw.NOTIFICATION}
    }
  }
}

local mock_device = test.mock_device.build_test_zwave_device(
        {
          profile = t_utils.get_profile_definition("base-lock-tamper.yml"),
          zwave_endpoints = zwave_lock_endpoints
        }
)

local function test_init()
  test.mock_device.add_test_device(mock_device)
end
test.set_test_init_function(test_init)

local expect_reload_all_codes_messages = function()
  test.socket.capability:__expect_send(mock_device:generate_test_message("main",
          capabilities.lockCodes.lockCodes(json.encode({} ), { visibility = { displayed = false } })
  ))
  test.socket.zwave:__expect_send( UserCode:UsersNumberGet({}):build_test_tx(mock_device.id) )
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.scanCodes("Scanning", { visibility = { displayed = false } })))
  test.socket.zwave:__expect_send( UserCode:Get({ user_identifier = 1 }):build_test_tx(mock_device.id) )
end

test.register_coroutine_test(
  "When the device is added it should be set up and start reading codes",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })

    expect_reload_all_codes_messages()
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        DoorLock:OperationGet({})
      )
    )
    test.socket.zwave:__expect_send(
      zw_test_utils.zwave_test_build_send_command(
        mock_device,
        Battery:Get({})
      )
    )
    -- test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.clear()))
  end
)

test.register_coroutine_test(
  "Door Lock Operation Reports should be handled",
  function()
    test.socket.zwave:__queue_receive({mock_device.id,
                                        DoorLock:OperationReport({door_lock_mode = DoorLock.door_lock_mode.DOOR_SECURED})
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lock.lock.locked()))
  end
)

test.register_message_test(
  "Battery percentage report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, Battery:Report({ battery_level = 0x63 }) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(99))
    }
  }
)

test.register_message_test(
  "Lock notification reporting should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  Notification:Report({
                    notification_type = Notification.notification_type.ACCESS_CONTROL,
                    event = Notification.event.access_control.MANUAL_LOCK_OPERATION
                  })
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "manual" } }))
    }
  }
)

test.register_message_test(
  "Code set reports should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  UserCode:Report({
                    user_identifier = 2,
                    user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS
                  })
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
              capabilities.lockCodes.lockCodes(json.encode({["2"] = "Code 2"}), { visibility = { displayed = false } }) )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("2 set",
              { data = { codeName = "Code 2"}, state_change = true }))
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_message_test(
  "Alarm tamper events should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id,
                  Notification:Report({
                    notification_type = Notification.notification_type.ACCESS_CONTROL,
                    event = Notification.event.access_control.KEYPAD_TEMPORARY_DISABLED
                  })
      }
    },

    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    }
  }
)

test.register_coroutine_test(
  "Sending the lock command should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(4.2, "oneshot")
    test.socket.capability:__queue_receive({mock_device.id,
                                            { capability = "lock", component = "main", command = "lock", args = {} }
    })
    test.socket.zwave:__expect_send(DoorLock:OperationSet({door_lock_mode = DoorLock.door_lock_mode.DOOR_SECURED}):build_test_tx(mock_device.id))
    test.wait_for_events()
    test.mock_time.advance_time(4.2)
    test.socket.zwave:__expect_send(DoorLock:OperationGet({}):build_test_tx(mock_device.id))
  end
)

test.register_message_test(
  "Max user code number report should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, UserCode:UsersNumberReport({ supported_users = 16 }) }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(16, { visibility = { displayed = false } }))
    }
  }
)

test.register_coroutine_test(
  "Reloading all codes of an unconfigured lock should generate correct attribute checks",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "reloadAllCodes", args = {} } })
    expect_reload_all_codes_messages()
  end
)

test.register_message_test(
  "Requesting a user code should be handled",
  {
    {
      channel = "capability",
      direction = "receive",
      message = { mock_device.id, { capability = capabilities.lockCodes.ID, command = "requestCode", args = { 1 } } }
    },
    {
      channel = "zwave",
      direction = "send",
      message = UserCode:Get({user_identifier = 1}):build_test_tx(mock_device.id)
    }
  }
)

test.register_coroutine_test(
  "Deleting a user code should be handled",
  function()
    test.timer.__create_and_queue_test_time_advance_timer(4.2, "oneshot")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "deleteCode", args = { 1 } } })
    test.socket.zwave:__expect_send(UserCode:Set( {user_identifier = 1, user_id_status = UserCode.user_id_status.AVAILABLE}):build_test_tx(mock_device.id))
    test.wait_for_events()

    test.mock_time.advance_time(4.2)
    test.socket.zwave:__expect_send(UserCode:Get( {user_identifier = 1}):build_test_tx(mock_device.id))
  end
)

test.register_coroutine_test(
  "Setting a user code should result in the named code changed event firing",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "setCode", args = { 1, "1234", "test" } } })
    test.socket.zwave:__expect_send(UserCode:Set({user_identifier = 1, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}):build_test_tx(mock_device.id) )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({user_identifier = 1, user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}) })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
            capabilities.lockCodes.lockCodes(json.encode({["1"] = "test"}), { visibility = { displayed = false } })
    ))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
            capabilities.lockCodes.codeChanged("1 set", { data = { codeName = "test"}, state_change = true  }))
    )
  end
)

local function init_code_slot(slot_number, name, device)
  local lock_codes = device.persistent_store[constants.LOCK_CODES]
  if lock_codes == nil then
    lock_codes = {}
    device.persistent_store[constants.LOCK_CODES] = lock_codes
  end
  lock_codes[tostring(slot_number)] = name
end

test.register_coroutine_test(
  "Setting a user code name should be handled",
  function()
    init_code_slot(1, "initialName", mock_device)
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "nameSlot", args = { 1, "foo" } } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
            capabilities.lockCodes.lockCodes(json.encode({["1"] = "foo"} ), { visibility = { displayed = false } })
    ))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("1 renamed",
            {state_change = true})))
  end
)

test.register_coroutine_test(
  "Calling updateCodes should send properly spaced commands",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zwave:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "updateCodes", args = {{code1 = "1234", code2 = "2345", code3 = "3456", code4 = ""}}}})
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(UserCode:Set({user_identifier = 1, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}):build_test_tx(mock_device.id))
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(UserCode:Set({user_identifier = 2, user_code = "2345", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}):build_test_tx(mock_device.id))
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(UserCode:Set({user_identifier = 3, user_code = "3456", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}):build_test_tx(mock_device.id))
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(UserCode:Set({user_identifier = 4, user_id_status = UserCode.user_id_status.AVAILABLE}):build_test_tx(mock_device.id))
    test.mock_time.advance_time(2)
    test.socket.zwave:__expect_send(UserCode:Get({user_identifier = 4}):build_test_tx(mock_device.id))
    test.wait_for_events()
  end
)

test.register_message_test(
  "Master code programming event should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = { mock_device.id, Notification:Report({
        notification_type = Notification.notification_type.ACCESS_CONTROL,
        event = Notification.event.access_control.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION
      })}
    },

    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("0 set", { data = { codeName = "Master Code"}, state_change = true  })
      )
    }
  }
)

test.register_message_test(
  "The lock reporting a single code has been set should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        UserCode:Report({ user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS, user_identifier = 1})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
              capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1"}), { visibility = { displayed = false } }) )
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("1 set", { data = { codeName = "Code 1"}, state_change = true  }))
    }
  },
  {
    inner_block_ordering = "relaxed"
  }
)

test.register_coroutine_test(
  "The lock reporting a code has been deleted should be handled",
  function()
    init_code_slot(1, "Code 1", mock_device)
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        UserCode:Report({user_identifier = 1, user_id_status = UserCode.user_id_status.AVAILABLE})
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("1 deleted", { data = { codeName = "Code 1"}, state_change = true  })
      )
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
            capabilities.lockCodes.lockCodes(json.encode({} ), { visibility = { displayed = false } })
    ))
  end
)

test.register_coroutine_test(
  "The lock reporting that all codes have been deleted should be handled",
  function()
    init_code_slot(1, "Code 1", mock_device)
    init_code_slot(2, "Code 2", mock_device)
    init_code_slot(3, "Code 3", mock_device)
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        Notification:Report({
          notification_type = Notification.notification_type.ACCESS_CONTROL,
          event = Notification.event.access_control.ALL_USER_CODES_DELETED
        })
      }
    )

    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("1 deleted", { data = { codeName = "Code 1"}, state_change = true  })
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("2 deleted", { data = { codeName = "Code 2"}, state_change = true  })
      )
    )

    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("3 deleted", { data = { codeName = "Code 3"}, state_change = true  })
      )
    )
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({} ), { visibility = { displayed = false } })
    ))
  end
)

test.register_coroutine_test(
  "The lock reporting unlock via code should include the code info in the report",
  function()
    init_code_slot(1, "Code 1", mock_device)
    test.socket.zwave:__queue_receive(
      {
        mock_device.id,
        Notification:Report({
          notification_type = Notification.notification_type.ACCESS_CONTROL,
          event = Notification.event.access_control.KEYPAD_UNLOCK_OPERATION,
          event_parameter = ""
        })
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
              capabilities.lock.lock.unlocked({ data = { method = "keypad", codeId = "1", codeName = "Code 1" } })
      )
    )
  end
)

test.register_coroutine_test(
  "Getting all lock codes should advance as expected",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "reloadAllCodes", args = {} } })
    expect_reload_all_codes_messages()
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, UserCode:UsersNumberReport({ supported_users = 4 }) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(4, { visibility = { displayed = false } })))
    for i = 1, 4 do
      if (i ~= 1) then
        test.socket.zwave:__expect_send(UserCode:Get({user_identifier = i}):build_test_tx(mock_device.id))
      end
      test.socket.zwave:__queue_receive({mock_device.id, UserCode:Report({
        user_identifier = i,
        user_id_status = UserCode.user_id_status.AVAILABLE
      })})
      test.socket.capability:__expect_send(
              mock_device:generate_test_message("main",
                      capabilities.lockCodes.codeChanged(i.." unset", { state_change = true })
              )
      )
    end
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
            capabilities.lockCodes.scanCodes("Complete", { visibility = { displayed = false } })
    ))
  end
)

test.register_message_test(
  "Lock alarm reporting should be handled",
  {
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 22, alarm_level = 1})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({data={method="manual"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 9})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unknown())
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 19, alarm_level = 3})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({data={method="keypad", codeName = "Code 3", codeId="3"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 18, alarm_level=0})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({data={method="keypad", codeName = "Master Code", codeId="0"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 21, alarm_level = 2})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({data={method="manual"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 21, alarm_level = 1})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({data={method="keypad"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 23})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unknown({data={method="command"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 24})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({data={method="command"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 25})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unlocked({data={method="command"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 26})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.unknown({data={method="auto"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 27})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({data={method="auto"}}))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 32})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lockCodes.lockCodes(json.encode({}), { visibility = { displayed = false } }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 13, alarm_level = 5})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lockCodes.lockCodes(json.encode({["5"] = "Code 5"}), { visibility = { displayed = false } }))
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("5 set", {data={codeName="Code 5"}, state_change = true }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 34, alarm_level = 2})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("2 failed", { state_change = true }))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 161})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.tamperAlert.tamper.detected())
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 168})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(1))
    },
    {
      channel = "zwave",
      direction = "receive",
      message = {
        mock_device.id,
        Alarm:Report({alarm_type = 169})
      }
    },
    {
      channel = "capability",
      direction = "send",
      message = mock_device:generate_test_message("main", capabilities.battery.battery(0))
    }
  }
)

test.register_coroutine_test(
  "Setting a user code should result in the named code changed event firing when notified via Notification CC",
  function()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "setCode", args = { 1, "1234", "test" } } })
    test.socket.zwave:__expect_send(UserCode:Set({user_identifier = 1, user_code = "1234", user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}):build_test_tx(mock_device.id) )
    test.wait_for_events()
    test.socket.zwave:__queue_receive({mock_device.id, Notification:Report({
      notification_type = Notification.notification_type.ACCESS_CONTROL,
      event = Notification.event.access_control.NEW_USER_CODE_ADDED,
      v1_alarm_level = 1,
      event_parameter = ""
    }) })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
            capabilities.lockCodes.lockCodes(json.encode({["1"] = "test"}), { visibility = { displayed = false } })
    ))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
            capabilities.lockCodes.codeChanged("1 set", { data = { codeName = "test"}, state_change = true  }))
    )
  end
)

test.run_registered_tests()
