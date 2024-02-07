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

-- Mock out globals
local test = require "integration_test"
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock
local Alarm = clusters.Alarms
local capabilities = require "st.capabilities"

local DoorLockState = DoorLock.attributes.LockState
local OperationEventCode = DoorLock.types.OperationEventCode
local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType = DoorLock.types.DrlkUserType
local ProgrammingEventCode = DoorLock.types.ProgramEventCode

local json = require "dkjson"

local mock_device = test.mock_device.build_test_zigbee_device(
    { profile = t_utils.get_profile_definition("base-lock.yml") }
)
zigbee_test_utils.prepare_zigbee_env_info()
local function test_init()
  test.mock_device.add_test_device(mock_device)
  zigbee_test_utils.init_noop_health_check_timer()
end

test.set_test_init_function(test_init)

local expect_reload_all_codes_messages = function()
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device,
                                                                                                           true) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.MinPINCodeLength:read(mock_device) })
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:read(mock_device) })
  test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.scanCodes("Scanning", { visibility = { displayed = false } })))
  test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 0) })
end

test.register_coroutine_test(
    "Configure should configure all necessary attributes and begin reading codes",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.wait_for_events()

      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
      test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
                                                                                                 zigbee_test_utils.mock_hub_eui,
                                                                                                 PowerConfiguration.ID) })
      test.socket.zigbee:__expect_send({ mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:configure_reporting(mock_device,
                                                                                                                                         600,
                                                                                                                                         21600,
                                                                                                                                         1) })
      test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
                                                                                                 zigbee_test_utils.mock_hub_eui,
                                                                                                 DoorLock.ID) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.LockState:configure_reporting(mock_device,
                                                                                                                     0,
                                                                                                                     3600,
                                                                                                                     0) })
      test.socket.zigbee:__expect_send({ mock_device.id, zigbee_test_utils.build_bind_request(mock_device,
                                                                                                 zigbee_test_utils.mock_hub_eui,
                                                                                                 Alarm.ID) })
      test.socket.zigbee:__expect_send({ mock_device.id, Alarm.attributes.AlarmCount:configure_reporting(mock_device,
                                                                                                                   0,
                                                                                                                   21600,
                                                                                                                   0) })

      mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
      test.wait_for_events()

      test.mock_time.advance_time(2)
      expect_reload_all_codes_messages()

    end
)

test.register_coroutine_test(
    "Refresh should read expected attributes",
    function()
      test.socket.zigbee:__set_channel_ordering("relaxed")
      test.socket.capability:__queue_receive({mock_device.id, { capability = "refresh", component = "main", command = "refresh", args = {} }})

      test.socket.zigbee:__expect_send({mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:read(mock_device)})
      test.socket.zigbee:__expect_send({mock_device.id, DoorLock.attributes.LockState:read(mock_device)})
      test.socket.zigbee:__expect_send({mock_device.id, Alarm.attributes.AlarmCount:read(mock_device)})
    end
)

test.register_message_test(
    "Lock status reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.LockState:build_test_attr_report(mock_device,
                                                                                                DoorLockState.LOCKED) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked())
      }
    }
)

test.register_message_test(
    "Battery percentage report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, PowerConfiguration.attributes.BatteryPercentageRemaining:build_test_attr_report(mock_device,
                                                                                                                    55) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.battery.battery(28))
      }
    }
)

test.register_message_test(
    "Lock operation event reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                        mock_device,
                        0x02,
                        OperationEventCode.LOCK,
                        0x0000,
                        "",
                        0x0000,
                        "") }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lock.lock.locked({ data = { method = "manual" } }))
      }
    }
)

test.register_message_test(
    "Pin response reporting should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id,
                    DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
                        mock_device,
                        0x02,
                        DoorLockUserStatus.OCCUPIED_ENABLED,
                        DoorLockUserType.UNRESTRICTED,
                        "1234"
                    )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("2 set",
                                                                                       { data = { codeName = "Code 2" }, state_change = true }))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lockCodes.lockCodes(json.encode({["2"] = "Code 2"} ), { visibility = { displayed = false } }))
      }
    }
)

test.register_message_test(
    "Sending the lock command should be handled",
    {
      {
        channel = "capability",
        direction = "receive",
        message = { mock_device.id, { capability = "lock", component = "main", command = "lock", args = {} } }
      },
      {
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, DoorLock.server.commands.LockDoor(mock_device) }
      }
    }
)

test.register_message_test(
    "Min lock code length report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.MinPINCodeLength:build_test_attr_report(mock_device, 4) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = false }}))
      }
    }
)

test.register_message_test(
    "Max lock code length report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.MaxPINCodeLength:build_test_attr_report(mock_device, 4) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lockCodes.maxCodeLength(4, { visibility = { displayed = false }}))
      }
    }
)

test.register_message_test(
    "Max user code number report should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = { mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported:build_test_attr_report(mock_device,
                                                                                                           16) }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main", capabilities.lockCodes.maxCodes(16, { visibility = { displayed = false }}))
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
        channel = "zigbee",
        direction = "send",
        message = { mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1) }
      }
    }
)

test.register_coroutine_test(
    "Deleting a user code should be handled",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
      test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
                                          mock_device,
                                          0x01,
                                          DoorLockUserStatus.OCCUPIED_ENABLED,
                                          DoorLockUserType.UNRESTRICTED,
                                          "1234"
                                      ) })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("1 set",
                                                                                                 { data = { codeName = "Code 1" }, state_change = true })))
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode( {["1"] = "Code 1"} ), { visibility = { displayed = false }})
      ))
      test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "deleteCode", args = { 1 } } })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device,
                                                                                                               true) })
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 1) })
      test.wait_for_events()

      test.mock_time.advance_time(2)
      test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1) })
      test.socket.zigbee:__queue_receive({ mock_device.id,
                                           DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
                                               mock_device,
                                               0x01,
                                               DoorLockUserType.UNRESTRICTED,
                                               DoorLockUserStatus.AVAILABLE,
                                               "")})
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("1 deleted",
                                                                                                                 { data = { codeName = "Code 1"}, state_change = true })))
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({} ), { visibility = { displayed = false } })
      ))
    end
)

test.register_coroutine_test(
    "Setting a user code should result in the named code changed event firing",
    function()
      test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
      test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "setCode", args = { 1, "1234", "test" } } })
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            DoorLock.server.commands.SetPINCode(mock_device,
                                                   1,
                                                   DoorLockUserStatus.OCCUPIED_ENABLED,
                                                   DoorLockUserType.UNRESTRICTED,
                                                   "1234"
            )
          }
      )
      test.wait_for_events()

      test.mock_time.advance_time(4)
      test.socket.zigbee:__expect_send(
          {
            mock_device.id,
            DoorLock.server.commands.GetPINCode(mock_device, 1)
          }
      )

      test.wait_for_events()

      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
                mock_device,
                0x01,
                DoorLockUserStatus.OCCUPIED_ENABLED,
                DoorLockUserType.UNRESTRICTED,
                "1234"
            )
          }
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.codeChanged("1 set", { data = { codeName = "test" }, state_change = true })))
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({["1"] = "test"}), { visibility = { displayed = false } })))
    end
)

local function init_code_slot(slot_number, name, device)
  test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
  test.socket.capability:__queue_receive({ device.id, { capability = capabilities.lockCodes.ID, command = "setCode", args = { slot_number, "1234", name } } })
  test.socket.zigbee:__expect_send(
      {
        device.id,
        DoorLock.server.commands.SetPINCode(device,
                                               slot_number,
                                               DoorLockUserStatus.OCCUPIED_ENABLED,
                                               DoorLockUserType.UNRESTRICTED,
                                               "1234"
        )
      }
  )
  test.wait_for_events()
  test.mock_time.advance_time(4)
  test.socket.zigbee:__expect_send(
      {
        device.id,
        DoorLock.server.commands.GetPINCode(device, slot_number)
      }
  )
  test.wait_for_events()
  test.socket.zigbee:__queue_receive(
      {
        device.id,
        DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
            device,
            slot_number,
            DoorLockUserStatus.OCCUPIED_ENABLED,
            DoorLockUserType.UNRESTRICTED,
            "1234"
        )
      }
  )
  test.socket.capability:__expect_send(device:generate_test_message("main",
      capabilities.lockCodes.codeChanged(slot_number .. " set", { data = { codeName = name }, state_change = true }))
  )
end

test.register_coroutine_test(
    "Setting a user code name should be handled",
    function()
      init_code_slot(1, "initialName", mock_device)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({["1"] = "initialName"}), { visibility = { displayed = false } })))
      test.wait_for_events()

      test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "nameSlot", args = { 1, "foo" } } })
      test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("1 renamed", {state_change = true})))
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({["1"] = "foo"}), { visibility = { displayed = false } })))
    end
)

test.register_coroutine_test(
  "Setting a user code name via setCode should be handled",
  function()
    init_code_slot(1, "initialName", mock_device)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({["1"] = "initialName"}), { visibility = { displayed = false } })))
    test.wait_for_events()

    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "setCode", args = { 1, "", "foo"} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.lockCodes.codeChanged("1 renamed", {state_change = true})))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({["1"] = "foo"}), { visibility = { displayed = false } })))
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
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "updateCodes", args = {{code1 = "1234", code2 = "2345", code3 = "3456", code4 = ""}}}})
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
                                             1,
                                             DoorLockUserStatus.OCCUPIED_ENABLED,
                                             DoorLockUserType.UNRESTRICTED,
                                             "1234"
      )
    })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
                                             2,
                                             DoorLockUserStatus.OCCUPIED_ENABLED,
                                             DoorLockUserType.UNRESTRICTED,
                                             "2345"
      )
    })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.SetPINCode(mock_device,
                                             3,
                                             DoorLockUserStatus.OCCUPIED_ENABLED,
                                             DoorLockUserType.UNRESTRICTED,
                                             "3456"
      )
    })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 4)
    })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.GetPINCode(mock_device, 1)
    })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.GetPINCode(mock_device, 2)
    })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.GetPINCode(mock_device, 3)
    })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({
      mock_device.id,
      DoorLock.server.commands.GetPINCode(mock_device, 4)
    })
    test.wait_for_events()
  end
)

test.register_coroutine_test(
  "Setting all user codes should result in a code set event for each",
  function ()
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
    test.socket.zigbee:__set_channel_ordering("relaxed")
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "updateCodes", args = {{code1 = "1234", code2 = "2345", code3 = "3456", code4 = ""}}}})
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.server.commands.SetPINCode(mock_device, 1, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "1234")})
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1) })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.server.commands.SetPINCode(mock_device, 2, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "2345")})
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 2) })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({mock_device.id, DoorLock.server.commands.SetPINCode(mock_device, 3, DoorLockUserStatus.OCCUPIED_ENABLED, DoorLockUserType.UNRESTRICTED, "3456")})
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 3) })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 4) })
    test.mock_time.advance_time(2)
    test.socket.zigbee:__expect_send({ mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 4) })
    test.wait_for_events()
  end
)

test.register_message_test(
    "Master code programming event should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
              mock_device,
              0x00,
              ProgrammingEventCode.MASTER_CODE_CHANGED,
              0,
              "1234",
              DoorLockUserType.MASTER_USER,
              DoorLockUserStatus.OCCUPIED_ENABLED,
              0x0000,
              "data"
          )
        }
      },

      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
            capabilities.lockCodes.codeChanged("0 set", { data = { codeName = "Master Code"}, state_change = true })
        )
      }
    }
)

test.register_message_test(
    "The lock reporting a single code has been set should be handled",
    {
      {
        channel = "zigbee",
        direction = "receive",
        message = {
          mock_device.id,
          DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
              mock_device,
              0x0,
              ProgrammingEventCode.PIN_CODE_ADDED,
              1,
              "1234",
              DoorLockUserType.UNRESTRICTED,
              DoorLockUserStatus.OCCUPIED_ENABLED,
              0x0000,
              "data"
          )
        }
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
            capabilities.lockCodes.codeChanged("1 set", { data = { codeName = "Code 1"}, state_change = true }))
      },
      {
        channel = "capability",
        direction = "send",
        message = mock_device:generate_test_message("main",
            capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1"}), { visibility = { displayed = false } }))
      }
    }
)

test.register_coroutine_test(
    "The lock reporting a code has been deleted should be handled",
    function()
      init_code_slot(1, "Code 1", mock_device)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1"}), { visibility = { displayed = false } })))
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
                mock_device,
                0x0,
                ProgrammingEventCode.PIN_CODE_DELETED,
                1,
                "1234",
                DoorLockUserType.UNRESTRICTED,
                DoorLockUserStatus.AVAILABLE,
                0x0000,
                "data"
            )
          }
      )
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("1 deleted", { data = { codeName = "Code 1"}, state_change = true })
          )
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
          capabilities.lockCodes.lockCodes(json.encode({}), { visibility = { displayed = false } })))
    end
)

test.register_coroutine_test(
    "The lock reporting that all codes have been deleted should be handled",
    function()
      init_code_slot(1, "Code 1", mock_device)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
          capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1"}), { visibility = { displayed = false } })))
      init_code_slot(2, "Code 2", mock_device)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
          capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1", ["2"] = "Code 2"}), { visibility = { displayed = false } })))
      init_code_slot(3, "Code 3", mock_device)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
          capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1", ["2"] = "Code 2", ["3"] = "Code 3"}), { visibility = { displayed = false } })))

      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            DoorLock.client.commands.ProgrammingEventNotification.build_test_rx(
                mock_device,
                0x0,
                ProgrammingEventCode.PIN_CODE_DELETED,
                0xFF,
                "1234",
                DoorLockUserType.UNRESTRICTED,
                DoorLockUserStatus.AVAILABLE,
                0x0000,
                "data"
            )
          }
      )

      test.socket.capability:__set_channel_ordering("relaxed")
      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("1 deleted", { data = { codeName = "Code 1"}, state_change = true })
          )
      )

      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("2 deleted", { data = { codeName = "Code 2"}, state_change = true })
          )
      )

      test.socket.capability:__expect_send(
          mock_device:generate_test_message("main",
              capabilities.lockCodes.codeChanged("3 deleted", { data = { codeName = "Code 3"}, state_change = true })
          )
      )
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({}), { visibility = { displayed = false } })))
      test.wait_for_events()
    end
)

test.register_coroutine_test(
    "The lock reporting unlock via code should include the code info in the report",
    function()
      init_code_slot(1, "Code 1", mock_device)
      test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1"}), { visibility = { displayed = false } })))
      test.socket.zigbee:__queue_receive(
          {
            mock_device.id,
            DoorLock.client.commands.OperatingEventNotification.build_test_rx(
                mock_device,
                0x00, -- 0 = keypad
                OperationEventCode.UNLOCK,
                0x0001,
                "1234",
                0x0000,
                ""
            )
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
  "Lock state attribute reports (after the first) should be delayed if they come before event notifications ",
  function()
    init_code_slot(1, "Code 1", mock_device)
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
      capabilities.lockCodes.lockCodes(json.encode({["1"] = "Code 1"}), { visibility = { displayed = false } })))
    test.socket.zigbee:__queue_receive({mock_device.id, DoorLock.attributes.LockState:build_test_attr_report(mock_device, DoorLockState.UNLOCKED)})
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.unlocked()
      )
    )
    test.mock_time.advance_time(2)
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.OperatingEventNotification.build_test_rx(
            mock_device,
            0x00, -- 0 = keypad
            OperationEventCode.UNLOCK,
            0x0001,
            "1234",
            0x0000,
            ""
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.unlocked({ data = { method = "keypad", codeId = "1", codeName = "Code 1" } })
      )
    )
    test.mock_time.advance_time(2)
    test.timer.__create_and_queue_test_time_advance_timer(2.5, "oneshot")
    test.socket.zigbee:__queue_receive({mock_device.id, DoorLock.attributes.LockState:build_test_attr_report(mock_device, DoorLockState.LOCKED)})
    test.socket.zigbee:__queue_receive(
      {
        mock_device.id,
        DoorLock.client.commands.OperatingEventNotification.build_test_rx(
            mock_device,
            0x00, -- 0 = keypad
            OperationEventCode.LOCK,
            0x0001,
            "1234",
            0x0000,
            ""
        )
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.locked({ data = { method = "keypad", codeId = "1", codeName = "Code 1" } })
      )
    )
    test.mock_time.advance_time(2.5)
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main",
        capabilities.lock.lock.locked()
      )
    )
  end
)

test.run_registered_tests()
