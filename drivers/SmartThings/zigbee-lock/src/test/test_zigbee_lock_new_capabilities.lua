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
local zigbee_test_utils = require "integration_test.zigbee_test_utils"
local t_utils = require "integration_test.utils"

local clusters = require "st.zigbee.zcl.clusters"
local PowerConfiguration = clusters.PowerConfiguration
local DoorLock = clusters.DoorLock
local Alarm = clusters.Alarms
local capabilities = require "st.capabilities"

local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType = DoorLock.types.DrlkUserType

local json = require "st.json"

local mock_datastore = require "integration_test.mock_env_datastore"

local mock_device = test.mock_device.build_test_zigbee_device(
    {
        profile = t_utils.get_profile_definition("base-lock.yml"),
    }
)

local mock_device_with_users = test.mock_device.build_test_zigbee_device(
    {
        profile = t_utils.get_profile_definition("base-lock.yml"),
        data = {
            lockCodes = json.encode({
                ["1"] = "Zach",
                ["3"] = "Steven"
            }),
        }
    }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init_new_capabilities()
    test.mock_device.add_test_device(mock_device)
end

local function init_migration()
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.MinPINCodeLength:build_test_attr_report(
    mock_device, 4) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.minCodeLength(4, { visibility = { displayed = false } })))
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.MaxPINCodeLength:build_test_attr_report(
    mock_device, 8) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.maxCodeLength(8, { visibility = { displayed = false } })))
    test.socket.zigbee:__queue_receive({ mock_device.id, DoorLock.attributes.NumberOfPINUsersSupported
        :build_test_attr_report(mock_device, 4) })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.maxCodes(4, { visibility = { displayed = false } })))
    test.wait_for_events()
    test.socket.capability:__queue_receive({ mock_device.id, { capability = capabilities.lockCodes.ID, command = "migrate", args = {} } })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCredentials.minPinCodeLen(4, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCredentials.maxPinCodeLen(8, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCredentials.pinUsersSupported(4, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCredentials.credentials({}, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCredentials.supportedCredentials({ "pin" }, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockUsers.users({}, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockUsers.totalUsersSupported(4, { visibility = { displayed = false } })))
    test.socket.capability:__expect_send(mock_device:generate_test_message("main",
        capabilities.lockCodes.migrated(true, { visibility = { displayed = false } })))
    test.wait_for_events()
end

local function add_default_users()
    local user_list = {}
    for i = 1, 4 do
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockUsers.ID,
                command = "addUser",
                args = { "TestUser" .. i, "guest" }
            },
        })
        -- add to the user list that is now expected
        table.insert(user_list, { userIndex = i, userType = "guest", userName = "TestUser" .. i })

        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(
                    user_list,
                    { visibility = { displayed = false } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "addUser", statusCode = "success" },
                    { state_change = true, visibility = { displayed = false } }
                )
            )
        )
    end
end

test.set_test_init_function(test_init_new_capabilities)

test.register_coroutine_test(
    "Add User command received and commandResult is success until totalUsersSupported reached",
    function()
        -- make sure we have migrated and are using the new capabilities
        init_migration()
        -- create initial max users
        add_default_users()

        -- 5th addUser call - totalUsersSupported is passsed and now commandResult should be resourceExhausted
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockUsers.ID,
                command = "addUser",
                args = { "TestUser", "guest" }
            },
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "addUser", statusCode = "resourceExhausted" },
                    { state_change = true, visibility = { displayed = false } }
                )
            )
        )
    end
)

test.register_coroutine_test(
    "Update User command reports a commandResult of success unless user index doesn't exist",
    function()
        -- make sure we have migrated and are using the new capabilities
        init_migration()
        -- create initial users
        add_default_users()

        -- success
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockUsers.ID,
                command = "updateUser",
                args = { "2", "ChangeUserName", "guest" }
            },
        })

        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(
                    {
                        { userIndex = 1, userName = "TestUser1",  userType = "guest" },
                        { userIndex = 2, userName = "ChangeUserName", userType = "guest" },
                        { userIndex = 3, userName = "TestUser3",  userType = "guest" },
                        { userIndex = 4, userName = "TestUser4",  userType = "guest" }
                    },
                    { visibility = { displayed = false } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "updateUser", statusCode = "success" },
                    { state_change = true, visibility = { displayed = false } }
                )
            )
        )

        -- failure - try updating non existent userIndex
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockUsers.ID,
                command = "updateUser",
                args = { "6", "ChangeUserName", "guest" }
            },
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "updateUser", statusCode = "failure" },
                    { state_change = true, visibility = { displayed = false } }
                )
            )
        )
    end
)

test.register_coroutine_test(
    "Delete User command reports a commandResult of success unless user index doesn't exist",
    function()
        -- make sure we have migrated and are using the new capabilities
        init_migration()
        -- create initial users
        add_default_users()

        -- success
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockUsers.ID,
                command = "deleteUser",
                args = { "3" }
            },
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(
                    {
                        { userIndex = 1, userName = "TestUser1", userType = "guest" },
                        { userIndex = 2, userName = "TestUser2", userType = "guest" },
                        { userIndex = 4, userName = "TestUser4", userType = "guest" }
                    },
                    { visibility = { displayed = false } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "deleteUser", statusCode = "success" },
                    { state_change = true, visibility = { displayed = false } }
                )
            )
        )

        -- failure - try updating non existent userIndex
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockUsers.ID,
                command = "deleteUser",
                args = { "3" }
            },
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "deleteUser", statusCode = "failure" },
                    { state_change = true, visibility = { displayed = false } }
                )
            )
        )
    end
)


test.register_coroutine_test(
    "addCredential command received and commandResult is success",
    function()
        init_migration()
        test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockCredentials.ID,
                command = "addCredential",
                args = { "2", "guest", "pin", "abc123" }
            },
        })
        test.socket.zigbee:__expect_send(
            {
                mock_device.id,
                DoorLock.server.commands.SetPINCode(mock_device,
                    1,
                    DoorLockUserStatus.OCCUPIED_ENABLED,
                    DoorLockUserType.UNRESTRICTED,
                    "abc123"
                )
            }
        )

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
                    "abc123"
                )
            }
        )

        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.credentials(
                    {
                        { userIndex = 2, credentialIndex = 1, credentialType = "pin" }
                    },
                    { visibility = { displayed = false } }
                )
            )
        )

        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.commandResult(
                    { commandName = "addCredential", statusCode = "success" },
                    { state_change = true, visibility = { displayed = false } }
                )
            )
        )
    end
)

test.run_registered_tests()
