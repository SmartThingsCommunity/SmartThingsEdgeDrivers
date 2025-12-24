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
local DoorLock = clusters.DoorLock
local capabilities = require "st.capabilities"

local DoorLockUserStatus = DoorLock.types.DrlkUserStatus
local DoorLockUserType = DoorLock.types.DrlkUserType

local test_credential_index = 1
local test_credentials = {}
local test_users = {}
local mock_device = test.mock_device.build_test_zigbee_device(
    {
        profile = t_utils.get_profile_definition("base-lock.yml"),
    }
)

zigbee_test_utils.prepare_zigbee_env_info()

local function test_init_new_capabilities()
    test_credential_index = 1
    test_credentials = {}
    test_users = {}
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
                args = { "Guest" .. i, "guest" }
            },
        })
        -- add to the user list that is now expected
        table.insert(user_list, { userIndex = i, userType = "guest", userName = "Guest" .. i })

        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(
                    user_list,
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "addUser", statusCode = "success", userIndex = i },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
    end
end

local function add_credential(user_index, credential_data)
    test.socket.capability:__queue_receive({
        mock_device.id,
        {
            capability = capabilities.lockCredentials.ID,
            command = "addCredential",
            args = { user_index, "guest", "pin", credential_data }
        },
    })
    test.socket.zigbee:__expect_send(
        {
            mock_device.id,
            DoorLock.server.commands.SetPINCode(mock_device,
                test_credential_index,
                DoorLockUserStatus.OCCUPIED_ENABLED,
                DoorLockUserType.UNRESTRICTED,
                credential_data
            )
        }
    )
    test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
    test.mock_time.advance_time(4)
    test.socket.zigbee:__expect_send(
        {
            mock_device.id,
            DoorLock.server.commands.GetPINCode(mock_device, test_credential_index)
        }
    )
    test.wait_for_events()
    test.socket.zigbee:__queue_receive(
        {
            mock_device.id,
            DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
                mock_device,
                test_credential_index,
                DoorLockUserStatus.OCCUPIED_ENABLED,
                DoorLockUserType.UNRESTRICTED,
                credential_data
            )
        }
    )
    table.insert(test_credentials,
        { userIndex = test_credential_index, credentialIndex = test_credential_index, credentialType = "pin" })
    table.insert(test_users,
        { userIndex = test_credential_index, userName = "Guest" .. test_credential_index, userType = "guest" })
    test.socket.capability:__expect_send(
        mock_device:generate_test_message(
            "main",
            capabilities.lockUsers.users(test_users, { state_change = true, visibility = { displayed = true } })
        )
    )
    test.socket.capability:__expect_send(
        mock_device:generate_test_message(
            "main",
            capabilities.lockCredentials.credentials(test_credentials,
                { state_change = true, visibility = { displayed = true } })
        )
    )
    test.socket.capability:__expect_send(
        mock_device:generate_test_message(
            "main",
            capabilities.lockCredentials.commandResult(
                { commandName = "addCredential", statusCode = "success", credentialIndex = test_credential_index, userIndex =
                test_credential_index },
                { state_change = true, visibility = { displayed = true } }
            )
        )
    )
    test.wait_for_events()
    test_credential_index = test_credential_index + 1
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
                    { state_change = true, visibility = { displayed = true } }
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

        local users = {
            { userIndex = 1, userName = "Guest1",         userType = "guest" },
            { userIndex = 2, userName = "ChangeUserName", userType = "guest" },
            { userIndex = 3, userName = "Guest3",         userType = "guest" },
            { userIndex = 4, userName = "Guest4",         userType = "guest" },
        }
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(users, { state_change = true, visibility = { displayed = true } })
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "updateUser", statusCode = "success", userIndex = 2 },
                    { state_change = true, visibility = { displayed = true } }
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
                    { state_change = true, visibility = { displayed = true } }
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

        local users = {
            { userIndex = 1, userName = "Guest1", userType = "guest" },
            { userIndex = 2, userName = "Guest2", userType = "guest" },
            { userIndex = 4, userName = "Guest4", userType = "guest" },
        }

        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(users, { state_change = true, visibility = { displayed = true } })
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.commandResult(
                    { commandName = "deleteUser", statusCode = "success", userIndex = 3 },
                    { state_change = true, visibility = { displayed = true } }
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
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
    end
)


test.register_coroutine_test(
    "addCredential command received and commandResult is success",
    function()
        init_migration()
        add_credential(0, "abc123")
    end
)

test.register_coroutine_test(
    "updateCredential command received and commandResult is success",
    function()
        init_migration()
        add_credential(0, "abc123")

        -- try to update the wrong credentialIndex (4) first and expect a failure
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockCredentials.ID,
                command = "updateCredential",
                args = { "4", "4", "pin", "abc123" }
            },
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.commandResult(
                    { commandName = "updateCredential", statusCode = "failure" },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.wait_for_events()

        -- try to update the right credential
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockCredentials.ID,
                command = "updateCredential",
                args = { "1", "1", "pin", "changedPin123" }
            },
        })
        test.socket.zigbee:__expect_send(
            {
                mock_device.id,
                DoorLock.server.commands.SetPINCode(mock_device,
                    1,
                    DoorLockUserStatus.OCCUPIED_ENABLED,
                    DoorLockUserType.UNRESTRICTED,
                    "changedPin123"
                )
            }
        )
        test.timer.__create_and_queue_test_time_advance_timer(4, "oneshot")
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
                capabilities.lockUsers.users(
                    {
                        { userIndex = 1, userType = "guest", userName = "Guest1" }
                    },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.credentials(
                    {
                        { userIndex = 1, credentialIndex = 1, credentialType = "pin" }
                    },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.commandResult(
                    { commandName = "updateCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.wait_for_events()
    end
)

test.register_coroutine_test(
    "deleteCredential command received and commandResult is success",
    function()
        init_migration()
        add_credential(0, "abc123")
        add_credential(0, "test123")
        add_credential(0, "321test")

        -- try to delete credential with wrong index and expect a failure
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockCredentials.ID,
                command = "deleteCredential",
                args = { "4", "pin" }
            },
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.commandResult(
                    { commandName = "deleteCredential", statusCode = "failure" },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.wait_for_events()

        -- try to delete credential with correct index
        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockCredentials.ID,
                command = "deleteCredential",
                args = { "1", "pin" }
            },
        })
        test.socket.zigbee:__expect_send({
            mock_device.id, DoorLock.attributes.SendPINOverTheAir:write(mock_device, true)
        })
        test.socket.zigbee:__expect_send({
            mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 1)
        })
        test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
        test.mock_time.advance_time(2)
        test.socket.zigbee:__expect_send(
            {
                mock_device.id,
                DoorLock.server.commands.GetPINCode(mock_device, 1)
            }
        )
        test.wait_for_events()
        test.socket.zigbee:__queue_receive({
            mock_device.id,
            DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
                mock_device,
                0x01,
                DoorLockUserType.UNRESTRICTED,
                DoorLockUserStatus.AVAILABLE,
                ""
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(
                    {
                        { userIndex = 2, userType = "guest", userName = "Guest2" },
                        { userIndex = 3, userType = "guest", userName = "Guest3" }
                    },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.credentials(
                    {
                        { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
                        { userIndex = 3, credentialIndex = 3, credentialType = "pin" }
                    },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.commandResult(
                    { commandName = "deleteCredential", statusCode = "success", credentialIndex = 1, userIndex = 1 },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.wait_for_events()
    end
)

test.register_coroutine_test(
    "deleteAllCredentials command received and commandResult is success",
    function()
        init_migration()
        add_credential(0, "abc123")
        add_credential(0, "test123")
        add_credential(0, "321test")

        test.socket.capability:__queue_receive({
            mock_device.id,
            {
                capability = capabilities.lockCredentials.ID,
                command = "deleteAllCredentials",
                args = {}
            },
        })

        test.timer.__create_and_queue_test_time_advance_timer(0, "oneshot")
        test.socket.zigbee:__expect_send({
            mock_device.id, DoorLock.server.commands.ClearPINCode(mock_device, 1)
        })

        test.timer.__create_and_queue_test_time_advance_timer(2, "oneshot")
        test.socket.zigbee:__expect_send({
            mock_device.id, DoorLock.server.commands.GetPINCode(mock_device, 1)
        })

        test.wait_for_events()
        test.mock_time.advance_time(2)
        test.socket.zigbee:__queue_receive({
            mock_device.id,
            DoorLock.client.commands.GetPINCodeResponse.build_test_rx(
                mock_device,
                0x01,
                DoorLockUserType.UNRESTRICTED,
                DoorLockUserStatus.AVAILABLE,
                ""
            )
        })
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockUsers.users(
                    {
                        { userIndex = 2, userType = "guest", userName = "Guest2" },
                        { userIndex = 3, userType = "guest", userName = "Guest3" }
                    },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.credentials(
                    {
                        { userIndex = 2, credentialIndex = 2, credentialType = "pin" },
                        { userIndex = 3, credentialIndex = 3, credentialType = "pin" }
                    },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.socket.capability:__expect_send(
            mock_device:generate_test_message(
                "main",
                capabilities.lockCredentials.commandResult(
                    { commandName = "deleteAllCredentials", statusCode = "success" },
                    { state_change = true, visibility = { displayed = true } }
                )
            )
        )
        test.wait_for_events()
    end
)

test.run_registered_tests()
