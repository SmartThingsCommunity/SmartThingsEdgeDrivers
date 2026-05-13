-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local LockUsers = capabilities.lockUsers
local LockCredentials = capabilities.lockCredentials
local lock_utils = require "zwave_lock_utils"
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local log = require "log"
local TamperDefaults = require "st.zwave.defaults.tamperAlert"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"

-- Helper methods
local reload_all_codes = function(device)
  local max_codes = device:get_latest_state("main",
    LockCredentials.ID, LockCredentials.pinUsersSupported.NAME)
  if (max_codes == nil) then
    device:send(UserCode:UsersNumberGet({}))
  end

  if (device:get_field(lock_utils.CHECKING_CODE) == nil) then
    device:set_field(lock_utils.CHECKING_CODE, 1)
  end

  device:send(UserCode:Get({user_identifier = device:get_field(lock_utils.CHECKING_CODE)}))
end

local do_refresh = function(self, device)
  local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
  local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))
end

-- Lifecycle handlers
local added_handler = function(driver, device)
  if device:supports_capability_by_id(capabilities.lockCodes.ID) and device._provisioning_state == "TYPED" then
    -- set the migrated field to true so new devices use lockCredentials/lockUsers from the start.
    -- auto-migration is only run for typed devices, as provisioned devices have already been onboarded,
    -- and should be migrated manually by the user.
    device:emit_event(capabilities.lockCodes.migrated(true, { visibility = { displayed = false } }))
    device:set_field(lock_utils.SLGA_MIGRATED, true, { persist = true }) -- persist the migrated state to the datastore
  end
  lock_utils.reload_tables(device)
  device.thread:call_with_delay(2, function ()
    reload_all_codes(device)
  end)
  local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
  local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))
  if (device:supports_capability(capabilities.tamperAlert)) then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
  device:emit_event(capabilities.lockCredentials.supportedCredentials({"pin"}, { visibility = { displayed = false } }))
end

local init_handler = function(driver, device)
  lock_utils.reload_tables(device)
  device.thread:call_with_delay(10, function ()
    reload_all_codes(device)
  end)
end

-- Lock Users commands
local add_user_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.ADD_USER, type = lock_utils.LOCK_USERS}) then
    return
  end
  local available_index = lock_utils.get_available_user_index(device)
  local status = lock_utils.STATUS_SUCCESS
  if available_index == nil then
    status = lock_utils.STATUS_RESOURCE_EXHAUSTED
  else
    device:set_field(lock_utils.ACTIVE_CREDENTIAL, { userIndex = available_index})
    lock_utils.create_user(device, command.args.userName, command.args.userType, available_index)
  end

  if status == lock_utils.STATUS_SUCCESS then
    lock_utils.send_events(device, lock_utils.LOCK_USERS)
  end

  lock_utils.clear_busy_state(device, status)
end

local update_user_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.UPDATE_USER, type = lock_utils.LOCK_USERS}) then
    return
  end

  local user_name = command.args.userName
  local user_type = command.args.userType
  local user_index = tonumber(command.args.userIndex)
  local current_users = lock_utils.get_users(device)
  local status = lock_utils.STATUS_FAILURE

  for _, user in pairs(current_users) do
    if user.userIndex == user_index then
      device:set_field(lock_utils.ACTIVE_CREDENTIAL, { userIndex = user_index })
      user.userName = user_name
      user.userType = user_type
      device:set_field(lock_utils.LOCK_USERS, current_users)
      lock_utils.send_events(device, lock_utils.LOCK_USERS)
      status = lock_utils.STATUS_SUCCESS
      break
    end
  end

  lock_utils.clear_busy_state(device, status)
end

local delete_user_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_USER, type = lock_utils.LOCK_USERS}, command.override_busy_check) then
    return
  end
  local status = lock_utils.STATUS_SUCCESS
  local user_index = tonumber(command.args.userIndex)
  if lock_utils.get_user(device, user_index) ~= nil then

    if command.override_busy_check == nil then
      device:set_field(lock_utils.ACTIVE_CREDENTIAL, { userIndex = user_index })
    end

    local associated_credential = lock_utils.get_credential_by_user_index(device, user_index)
    if associated_credential ~= nil then
      -- if there is an associated credential with this user then delete the credential
      -- this command also handles the user deletion
      driver:inject_capability_command(device, {
        capability = capabilities.lockCredentials.ID,
        command = capabilities.lockCredentials.commands.deleteCredential.NAME,
        args = { associated_credential.credentialIndex, "pin" },
        override_busy_check = true
      })
    else
      lock_utils.delete_user(device, user_index)
      lock_utils.send_events(device, lock_utils.LOCK_USERS)
      lock_utils.clear_busy_state(device, status, command.override_busy_check)
    end
  else
    status = lock_utils.STATUS_FAILURE
    lock_utils.clear_busy_state(device, status, command.override_busy_check)
  end
end

local delete_all_users_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_ALL_USERS, type = lock_utils.LOCK_USERS}) then
    return
  end
  local status = lock_utils.STATUS_SUCCESS
  local current_users = lock_utils.get_users(device)

  local delay = 0
  for _, user in pairs(current_users) do
    device.thread:call_with_delay(delay, function()
      driver:inject_capability_command(device, {
        capability = capabilities.lockUsers.ID,
        command = capabilities.lockUsers.commands.deleteUser.NAME,
        args = {user.userIndex},
        override_busy_check = true
      })
    end)
    delay = delay + 2
  end

  device.thread:call_with_delay(delay + 4, function()
    lock_utils.clear_busy_state(device, status)
  end)
end

--- Lock Credentials Commands

local add_credential_handler = lock_utils.add_credential_handler

local update_credential_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.UPDATE_CREDENTIAL, type = lock_utils.LOCK_CREDENTIALS}) then
    return
  end
  local credential_index = tonumber(command.args.credentialIndex)
  local credential_data = command.args.credentialData
  local credential = lock_utils.get_credential(device, credential_index)

  if credential ~= nil then
    device:set_field(lock_utils.ACTIVE_CREDENTIAL,
      { userIndex = credential.userIndex, credentialType = credential.credentialType, credentialIndex = credential.credentialIndex })
    device:send(UserCode:Set({
      user_identifier = credential_index,
      user_code = credential_data,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}))
    -- clearing busy state handled in user_code_report_handler
  else
    lock_utils.clear_busy_state(device, lock_utils.STATUS_FAILURE)
  end
end

local delete_credential_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_CREDENTIAL, type = lock_utils.LOCK_CREDENTIALS}, command.override_busy_check) then
    return
  end

  local credential_index = tonumber(command.args.credentialIndex)
  local credential = lock_utils.get_credential(device, credential_index)
  if credential ~= nil then
    if command.override_busy_check == nil then
      device:set_field(lock_utils.ACTIVE_CREDENTIAL,
        { userIndex = credential.userIndex, credentialType = credential.credentialType, credentialIndex = credential.credentialIndex })
    end
    device:send(UserCode:Set({
      user_identifier = credential.credentialIndex,
      user_id_status = UserCode.user_id_status.AVAILABLE
    }))
    -- clearing busy state handled in user_code_report_handler
  else
    lock_utils.clear_busy_state(device, lock_utils.STATUS_FAILURE, command.override_busy_check)
  end
end

local delete_all_credentials_handler = function(driver, device, command)
  if lock_utils.busy_check_and_set(device, {name = lock_utils.DELETE_ALL_CREDENTIALS, type = lock_utils.LOCK_CREDENTIALS}) then
    return
  end
  local credentials = lock_utils.get_credentials(device)
  local status = lock_utils.STATUS_SUCCESS
  local delay = 0
  for _, credential in pairs(credentials) do
    local credential_index = tonumber(credential.credentialIndex)
    device:send(UserCode:Set({
      user_identifier = credential_index,
      user_id_status = UserCode.user_id_status.AVAILABLE
    }))
    delay = delay + 2
  end

  device.thread:call_with_delay(delay + 4, function()
    lock_utils.clear_busy_state(device, status)
  end)
end

-- Z-Wave Message Handlers

local user_code_report_handler = lock_utils.user_code_report_handler

local notification_report_handler = function(driver, device, cmd)
  ------------ USER CODE PROGRAMMING EVENTS ------------
  lock_utils.base_driver_code_event_handler(driver, device, cmd)

  ------------ LOCK OPERATION EVENTS ------------
  lock_utils.door_operation_event_handler(driver, device, cmd)

  ------------ TAMPER EVENTS ------------
  -- We have to load and call this manually since we're now overriding notfication handling
  -- in this driver
  TamperDefaults.zwave_handlers[cc.NOTIFICATION][Notification.REPORT](driver, device, cmd)
end

local users_number_report_handler = function(driver, device, cmd)
  -- these are the same for Z-Wave
  device:emit_event(LockUsers.totalUsersSupported(cmd.args.supported_users, { state_change = true, visibility = { displayed = false } }))
  device:emit_event(LockCredentials.pinUsersSupported(cmd.args.supported_users, { state_change = true, visibility = { displayed = false } }))
end

-- Leave this here for logging purposes, it can be removed once lock migration is complete
local migrate = function(driver, device, value)
  log.error_with({ hub_logs = true }, "\n--- PK -- CURRENT USERS ---- \n" ..
  "\n" ..utils.stringify_table(lock_utils.get_users(device)).."\n" ..
  "\n--- PK -- CURRENT CREDENTIALS ---- \n" ..
  "\n" ..utils.stringify_table(lock_utils.get_credentials(device)).."\n" ..
  "\n --------------------------------- \n")
end

local function time_get_handler(driver, device, cmd)
  local Time = (require "st.zwave.CommandClass.Time")({ version = 1 })
  local time = os.date("*t")
  device:send_to_component(
    Time:Report({
      hour_local_time = time.hour,
      minute_local_time = time.min,
      second_local_time = time.sec
    }),
    device:endpoint_to_component(cmd.src_channel)
  )
end

local driver_template = {
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.lockUsers,
    capabilities.lockCredentials,
    capabilities.battery,
    capabilities.tamperAlert
  },
  lifecycle_handlers = {
    added = added_handler,
    init = init_handler,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    },
    [LockUsers.ID] = {
      [LockUsers.commands.addUser.NAME] = add_user_handler,
      [LockUsers.commands.updateUser.NAME] = update_user_handler,
      [LockUsers.commands.deleteUser.NAME] = delete_user_handler,
      [LockUsers.commands.deleteAllUsers.NAME] = delete_all_users_handler,
    },
    [LockCredentials.ID] = {
      [LockCredentials.commands.addCredential.NAME] = add_credential_handler,
      [LockCredentials.commands.updateCredential.NAME] = update_credential_handler,
      [LockCredentials.commands.deleteCredential.NAME] = delete_credential_handler,
      [LockCredentials.commands.deleteAllCredentials.NAME] = delete_all_credentials_handler,
    },
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.migrate.NAME] = migrate,
    },
  },
  zwave_handlers = {
    [cc.TIME] = {
      [0x01] = time_get_handler -- used by DanaLock
    },
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.USER_CODE] = {
      [UserCode.REPORT] = user_code_report_handler,
      [UserCode.USERS_NUMBER_REPORT] = users_number_report_handler,
    }
  },
  sub_drivers = require("sub_drivers"),
  shared_device_thread_enabled = true,
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local lock = ZwaveDriver("zwave_lock", driver_template)
lock:run()
return driver_template
