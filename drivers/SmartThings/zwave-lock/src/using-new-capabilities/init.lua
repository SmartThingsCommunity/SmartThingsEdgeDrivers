local capabilities = require "st.capabilities"
local LockUsers = capabilities.lockUsers
local LockCredentials = capabilities.lockCredentials
local lock_utils = require "using-new-capabilities.new_lock_utils"
local utils = require "st.utils"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.UserCode
local UserCode = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
--- @type st.zwave.CommandClass.Notification
local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local access_control_event = Notification.event.access_control

-- Helper methods

local add_or_update = function(device, method, credential_index, user_index)
  -- if so, add the credential to the list
  local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
  credentials[credential_index] = { userIndex = user_index, credentialIndex = credential_index, credentialType = "pin"}
  -- emit credential event
  device:emit_event(LockCredentials.credentials(credentials, { visibility = { displayed = false } }))
  -- emit command success
  device:emit_event(LockCredentials.commandResult(
    { commandName = method, statusCode = lock_utils.STATUS_SUCCESS, credentialIndex = credential_index}, { state_change = true, visibility = { displayed = false } }
  ))
  -- set the ongoing operation field to nil
  device:set_field(method..credential_index, nil)
end

-- returns the index of the lowest unset index less than the max
local next_empty_index = function(table, max)
  local index = 1
  for i = 1, max + 1 do
    if table[i] == nil then
      index = i
      break
    end
  end
  return index
end

-- Lifecycle handlers
local added_handler = function(driver, device)
  -- read user/credential metadata
  -- reload all codes
end

-- Lock Users commands

local add_user_handler = function(driver, device, cmd)
  local user_name = cmd.args.userName
  local user_type = cmd.args.userType
  -- get the table of current users
  local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
  -- check that we can add a new user
  local max_users = device:get_latest_state("main", LockUsers.ID, LockUsers.totalUsersSupported.NAME, 8)
  if utils.table_size(users) == max_users then
    -- we cannot create a new user (unlikely!)
  end
  -- find the index to add the user at
  local index = next_empty_index(users, max_users)
  -- insert the user into the table
  users[index] = {userIndex = index, userName = user_name, userType = user_type}
  -- emit the users table event
  device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
  -- emit the command result event
  device:emit_event(LockUsers.commandResult(
    { commandName = lock_utils.ADD_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = index }, { state_change = true, visibility = { displayed = false } }
  ))
end

local update_user_handler = function(driver, device, cmd)
  local index = cmd.args.userIndex
  local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
  -- does the user index already exist?
  -- if not, update the user (offset user index by 1)
  if users[index] ~= nil then
    -- insert the user into the table
    users[index] = {userIndex = index, userName = cmd.args.userName, userType = cmd.args.userType}
    -- emit the users table event
    device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
    -- emit the command result event
    device:emit_event(LockUsers.commandResult(
      { commandName = lock_utils.UPDATE_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = index }, { state_change = true, visibility = { displayed = false } }
    ))
  end
end

local delete_user_handler = function(driver, device, cmd)
  local index = cmd.args.userIndex
  -- make sure the user exists
  local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
  if users[index] ~= nil then
    -- see if the user is associated with a lock code
    local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
    for _, credential in pairs(credentials) do
      if credential.userIndex == index then
        -- if so, delete that code
        device:send(UserCode:Set({user_identifier = credential.credentialIndex, user_id_status = UserCode.user_id_status.AVAILABLE}))
        -- save state for receipt of delete
        device:set_field("_delete_credential"..credential.credentialIndex, index)
        -- make sure delete went through
        device.thread:call_with_delay(4.2, function(d) device:send(UserCode:Get({user_identifier = credential.credentialIndex})) end)
        return -- if the user has a credential, we need confirmation that the code was deleted before proceeding
      end
    end
    -- delete user from the list
    users[index] = nil
    -- emit users event
    device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
    -- emit user delete success
    device:emit_event(LockUsers.commandResult(
      { commandName = lock_utils.DELETE_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = index }, { state_change = true, visibility = { displayed = false } }
    ))
  end
end

local delete_all_users_handler = function(driver, device, cmd)
  -- TODO: Z-Wave User Code v2 includes mass sets/gets that could be leveraged to make this simpler
  -- delete every user
  -- send users event
  device:emit_event(LockUsers.users({}, { visibility = { displayed = false}}))
  -- send success event
  device:emit_event(LockUsers.commandResult({ commandName = lock_utils.DELETE_ALL_USERS, statusCode = lock_utils.STATUS_SUCCESS }, { state_change = true, visibility = { displayed = false}}))


  local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
  -- delete every credential
  local delay = 0
  for _, credential in pairs(credentials) do
    device.thread:call_with_delay(delay, function(d)
      device:send(UserCode:Set({user_identifier = credential.credentialIndex, user_id_status = UserCode.user_id_status.AVAILABLE}))
    end)
    -- include a delay between deletes
    delay = delay + .5
  end
  -- send credentials event
  device:emit_event(LockCredentials.credentials({}, { visibility = { displayed = false}}))
  -- send success event (this would be tedious to check for every code, so assume they all went through)
  device:emit_event(LockCredentials.commandResult({ commandName = lock_utils.DELETE_ALL_CREDENTIALS, statusCode = lock_utils.STATUS_SUCCESS }, { state_change = true, visibility = { displayed = false}}))
end

--- Lock Credentials Commands

local add_credential_handler = function(driver, device, cmd)
  local index = cmd.args.userIndex
  local user_type = cmd.args.userType
  local credential_type = cmd.args.credentialType -- if this is not "pin", send an error
  local data = cmd.args.credentialData
  -- get the table of current credentials
  local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
  -- does the user index already exist?
  local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
  -- if not, create a new user (offset user index by 1)
  if users[index] == nil then
    -- insert the user into the table
    users[index] = {userIndex = index, userName = "Code "..index, userType = user_type}
    -- emit the users table event
    device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
    -- emit the command result event
    device:emit_event(LockUsers.commandResult(
      { commandName = lock_utils.ADD_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = index }, { state_change = true, visibility = { displayed = false } }
    ))
  end
  -- find the index to add the credential at
  local max_credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.pinUsersSupported.NAME, 8)
  local credential_index = next_empty_index(credentials, max_credentials)
  -- save some state so we can complete the transaction on message receipt
  device:set_field(lock_utils.ADD_CREDENTIAL..credential_index, index)
  -- send the credential creation message
  device:send(UserCode:Set({
    user_identifier = credential_index,
    user_code = data,
    user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}))
end

local update_credential_handler = function(driver, device, cmd)
  -- validate args
  local user_index = cmd.args.userIndex
  local credential_index = cmd.args.credentialIndex
  local credential_type = cmd.args.credentialType
  local data = cmd.args.credentialData
  -- make sure credential already exists
  local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
  local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
  if credentials[credential_index] ~= nil and users[user_index] ~= nil then
    -- store state to track update
    device:set_field(lock_utils.UPDATE_CREDENTIAL..credential_index, user_index)
    -- send command to update code
    device:send(UserCode:Set({
      user_identifier = credential_index,
      user_code = data,
      user_id_status = UserCode.user_id_status.ENABLED_GRANT_ACCESS}))
  else
    -- failure
  end
end

local delete_credential_handler = function(driver, device, cmd)
  -- find the user associated with this credential
  local user_index = cmd.args.credentialIndex
  -- run delete user with that credential
  driver:inject_capability_command(device, {
    capability = capabilities.lockUsers.ID,
    command = capabilities.lockUsers.commands.deleteUser.NAME,
    args = { user_index }
  })
end

local delete_all_credentials_handler = function(driver, device, cmd)
  -- check to see if we have users that do not have a code associated
  local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
  local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
  local user_index_marked_for_individual_deletion = {}

  for _, credential in pairs(credentials) do
    users[credential.userIndex] = nil
    user_index_marked_for_individual_deletion[credential.userIndex] = true
  end
  -- if we don't, this is equivalent to delete_all_users
  if utils.table_size(users) == 0 then
    driver:inject_capability_command(device, {
      capability = capabilities.lockUsers.ID,
      command = capabilities.lockUsers.commands.deleteAllUsers.NAME,
      args = { }
    })
    return
  end
  -- if we do, delete all users other than those
  for i, _ in pairs(user_index_marked_for_individual_deletion) do
    device:emit_event(LockUsers.commandResult(
      { commandName = lock_utils.DELETE_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = i }, { state_change = true, visibility = { displayed = false } }
    ))
  end
  device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
  -- and then delete all codes
  local delay = 0
  for _, credential in pairs(credentials) do
    device.thread.call_with_delay(delay, function(d)
      device:send(UserCode:Set({user_identifier = credential.credentialIndex, user_id_status = UserCode.user_id_status.AVAILABLE}))
    end)
    -- include a delay between deletes
    delay = delay + .5
  end
  -- send credentials event (these will be sent before all the actual deletes have been sent)
  device:emit_event(LockCredentials.credentials({}, { visibility = { displayed = false}}))
  -- send success event (this would be tedious to check for every code, so assume they all went through)
  device:emit_event(LockCredentials.commandResult({ commandName = lock_utils.DELETE_ALL_CREDENTIALS, statusCode = lock_utils.STATUS_SUCCESS }, { visibility = { displayed = false}}))
end



-- Z-Wave Message Handlers

local user_code_report_handler = function(driver, device, cmd)
  local code_id = cmd.args.user_identifier
  local user_id_status = cmd.args.user_id_status

  -- is this a report about an occupied credential index?
  if (user_id_status == UserCode.user_id_status.ENABLED_GRANT_ACCESS or
      (user_id_status == UserCode.user_id_status.STATUS_NOT_AVAILABLE and cmd.args.user_code)) then
    -- are we in the middle of a user code set for this index?
    local user_index_add = device:get_field(lock_utils.ADD_CREDENTIAL..code_id)
    local user_index_update = device:get_field(lock_utils.UPDATE_CREDENTIAL..code_id)
    if user_index_add ~= nil then
      add_or_update(device, lock_utils.ADD_CREDENTIAL, code_id, user_index_add)
    elseif user_index_update ~= nil then
      add_or_update(device, lock_utils.UPDATE_CREDENTIAL, code_id, user_index_update)
    end
  elseif user_id_status == UserCode.user_id_status.AVAILABLE then
    -- are we in the middle of a user code delete?
    local user_index = device:get_field("_delete_credential"..code_id)
    if user_index ~= nil then
      -- if so, delete the credential
      local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
      credentials[code_id] = nil
      -- emit credential event
      device:emit_event(LockCredentials.credentials(credentials, { visibility = { displayed = false } }))
      -- emit command success
      device:emit_event(LockCredentials.commandResult(
        { commandName = lock_utils.DELETE_CREDENTIAL, statusCode = lock_utils.STATUS_SUCCESS, credentialIndex = code_id }, { state_change = true, visibility = { displayed = false } }
      ))
      -- delete the user
      local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
      users[user_index] = nil
      -- emit users event
      device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
      -- emit command success
      device:emit_event(LockUsers.commandResult(
        { commandName = lock_utils.DELETE_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = user_index }, { state_change = true, visibility = { displayed = false } }
      ))
      -- clear state
      device:set_field("_delete_credential"..code_id, nil)
    end
  end
end

local notification_report_handler = function(driver, device, cmd)
  if (cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL) then
    local event = cmd.args.event
    local credentials = device:get_latest_state("main", LockCredentials.ID, LockCredentials.credentials.NAME, {})
    local users = device:get_latest_state("main", LockUsers.ID, LockUsers.users.NAME, {})
    if (event == access_control_event.ALL_USER_CODES_DELETED) then
      -- this is unexpected, but we got this out of band, so...
      -- check to see if we have users that do not have a code associated
      local user_index_marked_for_individual_deletion = {}
      for _, credential in pairs(credentials) do
        users[credential.userIndex] = nil
        user_index_marked_for_individual_deletion[credential.userIndex] = true
      end
      -- if we don't, this is equivalent to delete_all_users
      if utils.table_size(users) == 0 then
        driver:inject_capability_command(device, {
          capability = capabilities.lockUsers.ID,
          command = capabilities.lockUsers.commands.deleteAllUsers.NAME,
          args = { }
        })
        return
      end
      -- if we do, delete all users other than those
      for i, _ in pairs(user_index_marked_for_individual_deletion) do
        device:emit_event(LockUsers.commandResult(
          { commandName = lock_utils.DELETE_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = i }, { state_change = true, visibility = { displayed = false } }
        ))
      end
      device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
      -- emit empty credentials
      device:emit_event(LockCredentials.credentials({}, { visibility = { displayed = false } }))
      device:emit_event(LockCredentials.commandResult({ commandName = lock_utils.DELETE_ALL_CREDENTIALS, statusCode = lock_utils.STATUS_SUCCESS }, { visibility = { displayed = false}}))
    elseif (event == access_control_event.SINGLE_USER_CODE_DELETED) then
      local credential_index = lock_utils.get_code_id_from_notification_event(cmd.args.event_parameter, cmd.args.v1_alarm_level)
      -- find the user index assigned to this code to delete it as well
      local credential = credentials[credential_index]
      if credential ~= nil then
        -- we may want to check if these match
        local stored_user_index = device:get_field("_delete_credential"..credential_index)
        local user_index = credential.userIndex
        local user = users[user_index]
        if user ~= nil then
          users[user_index] = nil
          device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
          device:emit_event(LockUsers.commandResult(
            { commandName = lock_utils.DELETE_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = user_index }, { state_change = true, visibility = { displayed = false } }
          ))
          device:set_field("_delete_credential"..credential_index, nil)
        end
      else
        -- something bad happened
      end
    elseif (event == access_control_event.NEW_USER_CODE_ADDED) then
      local credential_index = lock_utils.get_code_id_from_notification_event(cmd.args.event_parameter, cmd.args.v1_alarm_level)
      -- determine if this is due to a command or an out-of-band update
      local user_index_add = device:get_field(lock_utils.ADD_CREDENTIAL..credential_index)
      local user_index_update = device:get_field(lock_utils.UPDATE_CREDENTIAL..credential_index)
      if user_index_add ~= nil then
        add_or_update(device, lock_utils.ADD_CREDENTIAL, credential_index, user_index_add)
      elseif user_index_update ~= nil then
        add_or_update(device, lock_utils.UPDATE_CREDENTIAL, credential_index, user_index_update)
      else
        -- out-of-band update
        -- create a user for this code index
        local max_users = device:get_latest_state("main", LockUsers.ID, LockUsers.totalUsersSupported.NAME, 8)
        -- find the index to add the user at
        local index = next_empty_index(users, max_users)
        -- insert the user into the table
        users[index] = {userIndex = index, userName = "Code "..index, userType = "guest"}
        -- emit the users table event
        device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
        -- emit the command result event
        device:emit_event(LockUsers.commandResult(
          { commandName = lock_utils.ADD_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = index }, { state_change = true, visibility = { displayed = false } }
        ))
        -- add the credential
        add_or_update(device, lock_utils.ADD_CREDENTIAL, credential_index, index)
      end
    elseif (event == access_control_event.NEW_USER_CODE_NOT_ADDED_DUE_TO_DUPLICATE_CODE) then
      local credential_index = lock_utils.get_code_id_from_notification_event(cmd.args.event_parameter, cmd.args.v1_alarm_level)
      -- this is a create code failure
      -- double check we have a stored add command
      local user_index_add = device:get_field(lock_utils.ADD_CREDENTIAL..credential_index)
      -- clear that state
      device:set_field(lock_utils.ADD_CREDENTIAL..credential_index, nil)
      -- emit a credential add failure
      device:emit_event(LockCredentials.commandResult(
        { commandName = lock_utils.ADD_CREDENTIAL, statusCode = "duplicate", credentialIndex = credential_index }, { state_change = true, visibility = { displayed = false } }
      ))
      -- if we have a stored add command, we should delete the associated user, I think
      if users[user_index_add] ~= nil then
        users[user_index_add] = nil
        device:emit_event(LockUsers.commandResult(
          { commandName = lock_utils.DELETE_USER, statusCode = lock_utils.STATUS_SUCCESS, userIndex = user_index_add }, { state_change = true, visibility = { displayed = false } }
        ))
        device:emit_event(LockUsers.users(users, { visibility = { displayed = false } }))
      end
    elseif (event == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION) then
      --  master code changed
      --  we might want to fire a credential updated success here?


    -- these are all the lock operation events
    elseif (event >= access_control_event.MANUAL_LOCK_OPERATION and event <= access_control_event.LOCK_JAMMED) then
      local event_to_send

      local METHOD = {
        KEYPAD = "keypad",
        MANUAL = "manual",
        COMMAND = "command",
        AUTO = "auto"
      }

      local DELAY_LOCK_EVENT = "_delay_lock_event"
      local DELAY_LOCK_EVENT_TIMER = "_delay_lock_event_timer"
      local MAX_DELAY = 10

      if ((event >= access_control_event.MANUAL_LOCK_OPERATION and
            event <= access_control_event.KEYPAD_UNLOCK_OPERATION) or
            event == access_control_event.AUTO_LOCK_LOCKED_OPERATION) then
        -- even event codes are unlocks, odd event codes are locks
        local events = {[0] = capabilities.lock.lock.unlocked(), [1] = capabilities.lock.lock.locked()}
        event_to_send = events[event & 1]
      elseif (event >= access_control_event.MANUAL_NOT_FULLY_LOCKED_OPERATION and
              event <= access_control_event.LOCK_JAMMED) then
        event_to_send = capabilities.lock.lock.unknown()
      end

      if (event_to_send ~= nil) then
        local method_map = {
          [access_control_event.MANUAL_UNLOCK_OPERATION] = METHOD.MANUAL,
          [access_control_event.MANUAL_LOCK_OPERATION] = METHOD.MANUAL,
          [access_control_event.MANUAL_NOT_FULLY_LOCKED_OPERATION] = METHOD.MANUAL,
          [access_control_event.RF_LOCK_OPERATION] = METHOD.COMMAND,
          [access_control_event.RF_UNLOCK_OPERATION] = METHOD.COMMAND,
          [access_control_event.RF_NOT_FULLY_LOCKED_OPERATION] = METHOD.COMMAND,
          [access_control_event.KEYPAD_LOCK_OPERATION] = METHOD.KEYPAD,
          [access_control_event.KEYPAD_UNLOCK_OPERATION] = METHOD.KEYPAD,
          [access_control_event.AUTO_LOCK_LOCKED_OPERATION] = METHOD.AUTO,
          [access_control_event.AUTO_LOCK_NOT_FULLY_LOCKED_OPERATION] = METHOD.AUTO
        }

        event_to_send["data"] = {method = method_map[event]}

        -- SPECIAL CASES:
        if (event == access_control_event.MANUAL_UNLOCK_OPERATION and cmd.args.event_parameter == 2) then
          -- functionality from DTH, some locks can distinguish being manually locked via keypad
          event_to_send.data.method = METHOD.KEYPAD
        elseif (event == access_control_event.KEYPAD_LOCK_OPERATION or event == access_control_event.KEYPAD_UNLOCK_OPERATION) then
          local code_id = cmd.args.v1_alarm_level
          if cmd.args.event_parameter ~= nil and string.len(cmd.args.event_parameter) ~= 0 then
            local event_params = { cmd.args.event_parameter:byte(1, -1) }
            code_id = (#event_params == 1) and event_params[1] or event_params[3]
          end
          local user_id
          if (credentials ~= nil and
              credentials[code_id] ~= nil) then
            user_id = credentials[code_id].userIndex
          end
          if user_id ~= nil then event_to_send["data"] = { userIndex = user_id, method = event_to_send["data"].method } end
        end

        -- if this is an event corresponding to a recently-received attribute report, we
        -- want to set our delay timer for future lock attribute report events
        if device:get_latest_state(
          "main",
          capabilities.lock.ID,
          capabilities.lock.lock.ID) == event_to_send.value.value then
          local preceding_event_time = device:get_field(DELAY_LOCK_EVENT) or 0
          local socket = require "socket"
          local time_diff = socket.gettime() - preceding_event_time
          if time_diff < MAX_DELAY then
            device:set_field(DELAY_LOCK_EVENT, time_diff)
          end
        end

        local timer = device:get_field(DELAY_LOCK_EVENT_TIMER)
        if timer ~= nil then
          device.thread:cancel_timer(timer)
          device:set_field(DELAY_LOCK_EVENT_TIMER, nil)
        end

        device:emit_event(event_to_send)
      end
    end
  end
end

local users_number_report_handler = function(driver, device, cmd)
  -- these are the same for Z-Wave
  device:emit_event(LockUsers.totalUsersSupported(cmd.args.supported_users, { visibility = { displayed = false } }))
  device:emit_event(LockCredentials.pinUsersSupported(cmd.args.supported_users, { visibility = { displayed = false } }))
end

local zwave_lock = {
  lifecycle_handlers = {
    added = added_handler,
  },
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    },
    [cc.USER_CODE] = {
      [UserCode.REPORT] = user_code_report_handler,
      [UserCode.USERS_NUMBER_REPORT] = users_number_report_handler,
    }
  },
  capability_handlers = {
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
    }
  },
  NAME = "Using new capabilities",
  can_handle = function(opts, driver, device, ...)
    if not device:supports_capability_by_id(LockUsers.ID) then return false end
    local lock_codes_migrated = device:get_latest_state("main", capabilities.lockCodes.ID,
      capabilities.lockCodes.migrated.NAME, false)
    if lock_codes_migrated then
      local subdriver = require("using-new-capabilities")
      return true, subdriver
    end
    return false
  end
}

return zwave_lock