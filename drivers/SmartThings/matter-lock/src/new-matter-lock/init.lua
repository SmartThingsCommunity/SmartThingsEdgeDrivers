-- Copyright 2024 SmartThings
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

local device_lib = require "st.device"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local im = require "st.matter.interaction_model"
local lock_utils = require "lock_utils"
local log = require "log" -- needs to remove

local DoorLock = clusters.DoorLock
local INITIAL_COTA_INDEX = 1
local ALL_INDEX = 0xFFFE

local AQARA_MANUFACTURER_ID = 0x115f
local U200_PRODUCT_ID = 0x2802

local NEW_MATTER_LOCK_PRODUCTS = {
  {0x115f, 0x2802}, -- AQARA, U200
  {0x115f, 0x2801}, -- AQARA, U300
  {0x10E1, 0x1002} -- VDA
}

local subscribed_attributes = {
  [capabilities.lock.ID] = {
    DoorLock.attributes.LockState
  },
  [capabilities.remoteControlStatus.ID] = {
    DoorLock.attributes.OperatingMode
  },
  [capabilities.lockUsers.ID] = {
    DoorLock.attributes.NumberOfTotalUsersSupported
  },
  [capabilities.lockCredentials.ID] = {
    DoorLock.attributes.NumberOfPINUsersSupported,
    DoorLock.attributes.MaxPINCodeLength,
    DoorLock.attributes.MinPINCodeLength,
    DoorLock.attributes.RequirePINforRemoteOperation
  },
  [capabilities.lockSchedules.ID] = {
    DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser,
    DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser
  }
}

local subscribed_events = {
  [capabilities.lock.ID] = {
    DoorLock.events.LockOperation
  },
  [capabilities.lockAlarm.ID] = {
    DoorLock.events.DoorLockAlarm
  },
  [capabilities.lockUser.ID] = {
    DoorLock.events.LockUserChange
  }
}

local function is_new_matter_lock_products(opts, driver, device)
  if device.network_type ~= device_lib.NETWORK_TYPE_MATTER then
    return false
  end
  for _, p in ipairs(NEW_MATTER_LOCK_PRODUCTS) do
    if device.manufacturer_info.vendor_id == p[1] and
      device.manufacturer_info.product_id == p[2] then
        return true
    end
  end 
  return false
end

local function find_default_endpoint(device, cluster)
  local res = device.MATTER_DEFAULT_ENDPOINT
  local eps = device:get_endpoints(cluster)
  table.sort(eps)
  for _, v in ipairs(eps) do
    if v ~= 0 then --0 is the matter RootNode endpoint
      return v
    end
  end
  device.log.warn(string.format("Did not find default endpoint, will use endpoint %d instead", device.MATTER_DEFAULT_ENDPOINT))
  return res
end

local function component_to_endpoint(device, component_name)
  return find_default_endpoint(device, clusters.DoorLock.ID)
end

local function device_init(driver, device)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! device_added !!!!!!!!!!!!!")) -- needs to remove
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:subscribe()
 end

local function device_added(driver, device)
  device:emit_event(capabilities.lockAlarm.alarm.clear({state_change = true}))
end

local function do_configure(driver, device)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! do_configure !!!!!!!!!!!!!")) -- needs to remove

  local user_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.USER})
  local pin_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.PIN_CREDENTIAL})
  local week_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.WEEK_DAY_ACCESS_SCHEDULES})
  local year_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.YEAR_DAY_ACCESS_SCHEDULES})

  local profile_name = "lock"
  if #user_eps > 0 then
    profile_name = profile_name .. "-user"
    if #pin_eps > 0 then
      profile_name = profile_name .. "-pin"
    end
    if #week_schedule_eps + #year_schedule_eps > 0 then
      profile_name = profile_name .. "-schedule"
    end
  else
    profile_name = "base-lock"
  end
  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end

local function info_changed(driver, device, event, args)
  for cap_id, attributes in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(cap_id) then
      for _, attr in ipairs(attributes) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  for cap_id, events in pairs(subscribed_events) do
    if device:supports_capability_by_id(cap_id) then
      for _, e in ipairs(events) do
        device:add_subscribed_event(e)
      end
    end
  end
  device:subscribe()
end

-- Matter Handler
----------------
-- Lock State --
----------------
local function lock_state_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! lock_state_handler !!!!!!!!!!!!!")) -- needs to remove
  local LockState = DoorLock.attributes.LockState
  local attr = capabilities.lock.lock
  local LOCK_STATE = {
    [LockState.NOT_FULLY_LOCKED] = attr.not_fully_locked(),
    [LockState.LOCKED] = attr.locked({visibility = {displayed = false}}),
    [LockState.UNLOCKED] = attr.unlocked({visibility = {displayed = false}}),
  }

  if ib.data.value ~= nil then
    device:emit_event(LOCK_STATE[ib.data.value])
  else
    device:emit_event(attr.unknown())
  end
end

---------------------
-- Operating Modes --
---------------------
local function operating_modes_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! operating_modes_handler!!!!!!!!!!!!!")) -- needs to remove

  local status = capabilities.remoteControlStatus.remoteControlEnabled
  local op_type = DoorLock.types.OperatingModeEnum
  local opMode_map = {
    [op_type.NORMAL] = true,
    [op_type.VACATION] = true,
    [op_type.PRIVACY] = false,
    [op_type.NO_REMOTE_LOCK_UNLOCK] = false,
    [op_type.PASSAGE] = false,
  }
  local result = opMode_map[ib.data.value]
  if result == true then
    device:emit_event(status("true", {visibility = {displayed = true}}))
    device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  elseif result == false then
    device:emit_event(status("false", {visibility = {displayed = true}}))
    device:emit_event(capabilities.lock.supportedLockCommands({}, {visibility = {displayed = false}}))
  end
end
-------------------------------------
-- Number Of Total Users Supported --
------------------------------------- 
local function total_users_supported_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! total_users_supported_handler: %d !!!!!!!!!!!!!", ib.data.value)) -- needs to remove
  device:emit_event(capabilities.lockUsers.totalUsersSupported(ib.data.value, {visibility = {displayed = false}}))
end

----------------------------------
-- Number Of PIN User Supported --
---------------------------------- 
local function pin_users_supported_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! pin_users_supported_handler: %d !!!!!!!!!!!!!", ib.data.value)) -- needs to remove
  device:emit_event(capabilities.lockCredentials.pinUsersSupported(ib.data.value, {visibility = {displayed = false}}))
end

-------------------------
-- Min PIN Code Length --
------------------------- 
local function min_pin_code_len_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! min_pin_code_len_handler: %d !!!!!!!!!!!!!", ib.data.value)) -- needs to remove
  device:emit_event(capabilities.lockCredentials.minPinCodeLen(ib.data.value, {visibility = {displayed = false}}))
end

-------------------------
-- Max PIN Code Length --
------------------------- 
local function max_pin_code_len_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! max_pin_code_len_handler: %d !!!!!!!!!!!!!", ib.data.value)) -- needs to remove
  device:emit_event(capabilities.lockCredentials.maxPinCodeLen(ib.data.value, {visibility = {displayed = false}}))
end

--------------------------------------
-- Require PIN For Remote Operation --
--------------------------------------
--- If a device needs a cota credential this function attempts to set the credential
--- at the index provided. The set_credential_response_handler handles all failures
--- and retries with the appropriate index when necessary.
local function set_cota_credential(device, credential_index)
  local eps = device:get_endpoints(DoorLock.ID)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  if cota_cred == nil then
    -- Shouldn't happen but defensive to try to figure out if we need the cota cred and set it.
    device:send(DoorLock.attributes.RequirePINforRemoteOperation:read(device, #eps > 0 and eps[1] or 1))
    device.thread:call_with_delay(2, function(t) set_cota_credential(device, credential_index) end)
  elseif not cota_cred then
    device.log.debug("Device does not require PIN for remote operation. Not setting COTA credential")
    return
  end

  if device:get_field(lock_utils.SET_CREDENTIAL) ~= nil then
    device.log.debug("delaying setting COTA credential since a credential is currently being set")
    device.thread:call_with_delay(2, function(t)
      set_cota_credential(device, credential_index)
    end)
    return
  end

  device:set_field(lock_utils.COTA_CRED_INDEX, credential_index, {persist = true})
  local credential = {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = credential_index}
  -- Set the credential to a code
  device:set_field(lock_utils.COMMAND_NAME, "addCredential")
  device:set_field(lock_utils.CRED_INDEX, credential_index)
  device:set_field(lock_utils.SET_CREDENTIAL, credential_index)
  device:set_field(lock_utils.USER_TYPE, "adminMember")
  device.log.info(string.format("Attempting to set COTA credential at index %s", credential_index))
  device:send(DoorLock.server.commands.SetCredential(
    device,
    #eps > 0 and eps[1] or 1,
    DoorLock.types.DlDataOperationType.ADD,
    credential,
    device:get_field(lock_utils.COTA_CRED),
    nil, -- nil user_index creates a new user
    DoorLock.types.DlUserStatus.OCCUPIED_ENABLED,
    DoorLock.types.DlUserType.REMOTE_ONLY_USER
  ))
end

local function generate_cota_cred_for_device(device)
  local len = device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.maxPinCodeLen.NAME) or 6
  local cred_data = math.floor(math.random() * (10 ^ len))
  cred_data = string.format("%0" .. tostring(len) .. "d", cred_data)
  log.info_with({hub_logs=true}, string.format("cota_cred: %s", cred_data))
  device:set_field(lock_utils.COTA_CRED, cred_data, {persist = true})
end

local function apply_cota_credentials_if_absent(device)
  if not device:get_field(lock_utils.COTA_CRED) then
    --Process after all other info blocks have been dispatched to ensure MaxPINCodeLength has been processed
    device.thread:call_with_delay(0, function(t)
      generate_cota_cred_for_device(device)
      -- delay needed to allow test to override the random credential data
      device.thread:call_with_delay(0, function(t)
        -- Attempt to set cota credential at the lowest index
        set_cota_credential(device, INITIAL_COTA_INDEX)
      end)
    end)
  end
end

local function require_remote_pin_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! require_remote_pin_handler: %s !!!!!!!!!!!!!", ib.data.value)) -- needs to remove
  if ib.data.value then
    apply_cota_credentials_if_absent(device)
  else
    device:set_field(lock_utils.COTA_CRED, false, {persist = true})
  end
end

-----------------------------------------------------
-- Number Of Week Day Schedules Supported Per User --
-----------------------------------------------------
local function max_week_schedule_of_user_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! max_week_schedule_of_user_handler: %s !!!!!!!!!!!!!", ib.data.value)) -- needs to remove
  device:emit_event(capabilities.lockSchedules.weekDaySchedulesPerUser(ib.data.value, {visibility = {displayed = false}}))
end

-----------------------------------------------------
-- Number Of Year Day Schedules Supported Per User --
-----------------------------------------------------
local function max_year_schedule_of_user_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! max_year_schedule_of_user_handler: %s !!!!!!!!!!!!!", ib.data.value)) -- needs to remove
  device:emit_event(capabilities.lockSchedules.yearDaySchedulesPerUser(ib.data.value, {visibility = {displayed = false}}))
end

-- Capability Handler
-----------------
-- Lock/Unlock --
-----------------
local function handle_lock(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_lock !!!!!!!!!!!!!")) -- needs to remove
  local ep = device:component_to_endpoint(command.component)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  log.info_with({hub_logs=true}, string.format("cota_cred: %s", cota_cred))
  if cota_cred then
    device:send(
      DoorLock.server.commands.LockDoor(device, ep, cota_cred)
    )
  else
    device:send(DoorLock.server.commands.LockDoor(device, ep))
  end
end

local function handle_unlock(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_unlock !!!!!!!!!!!!!")) -- needs to remove
  local ep = device:component_to_endpoint(command.component)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  log.info_with({hub_logs=true}, string.format("cota_cred: %s", cota_cred)) -- needs to remove
  if cota_cred then
    device:send(
      DoorLock.server.commands.UnlockDoor(device, ep, cota_cred)
    )
  else
    device:send(DoorLock.server.commands.UnlockDoor(device, ep))
  end
end

----------------
-- User Table --
----------------
local function add_user_to_table(device, userIdx, usrType)
  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! add_user_to_table !!!!!!!!!!!!!"))
  log.info_with({hub_logs=true}, string.format("userIdx: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("usrType: %s", usrType))

  -- Get latest user table
  local user_table = device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.users.NAME
  ) or {}
  local new_user_table = {}

  -- Recreate user table
  for index, entry in pairs(user_table) do
    table.insert(new_user_table, entry)
  end

  -- Add new entry to table
  table.insert(new_user_table, {userIndex = userIdx, userType = usrType})
  device:emit_event(capabilities.lockUsers.users(new_user_table, {visibility = {displayed = false}}))
end

local function update_user_in_table(device, userIdx, usrType)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! update_user_in_table !!!!!!!!!!!!!")) -- needs to remove

  -- Get latest user table
  local user_table = device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.users.NAME
  ) or {}
  local new_user_table = {}

  -- Recreate user table
  local i = 0
  for index, entry in pairs(user_table) do
    if entry.userIndex == userIdx then
      i = index
    end
    table.insert(new_user_table, entry)
  end

  -- Update user entry
  if i ~= 0 then
    new_user_table[i].userType = usrType
    device:emit_event(capabilities.lockUsers.users(new_user_table, {visibility = {displayed = false}}))
  end
end

local function delete_user_from_table(device, userIdx)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! delete_user_from_table !!!!!!!!!!!!!")) -- needs to remove
  -- If User Index is ALL_INDEX, remove all entry from the table
  if userIdx == ALL_INDEX then
    device:emit_event(capabilities.lockUsers.users({}, {visibility = {displayed = false}}))
    return
  end

  -- Get latest user table
  local user_table = device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.users.NAME
  ) or {}
  local new_user_table = {}

  -- Recreate user table
  for index, entry in pairs(user_table) do
    if entry.userIndex ~= userIdx then
      table.insert(new_user_table, entry)
    end
  end
  device:emit_event(capabilities.lockUsers.users(new_user_table, {visibility = {displayed = false}}))
end

----------------------
-- Credential Table --
----------------------
local function add_credential_to_table(device, userIdx, credIdx, credType)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! add_credential_to_table !!!!!!!!!!!!!")) -- needs to remove

  -- Get latest credential table
  local cred_table = device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME
  ) or {}
  local new_cred_table = {}

  -- Recreat credential table
  for index, entry in pairs(cred_table) do
    table.insert(new_cred_table, entry)
  end

  -- Add new entry to table
  table.insert(new_cred_table, {userIndex = userIdx, credentialIndex = credIdx, credentialType = credType})
  device:emit_event(capabilities.lockCredentials.credentials(new_cred_table, {visibility = {displayed = false}}))
end

local function delete_credential_from_table(device, credIdx)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! delete_credential_from_table !!!!!!!!!!!!!")) -- needs to remove
  -- If Credential Index is ALL_INDEX, remove all entry from the table
  if credIdx == ALL_INDEX then
    device:emit_event(capabilities.lockCredentials.credentials({}))
  end

  -- Get latest credential table
  local cred_table = device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME
  ) or {}
  local new_cred_table = {}

  -- Recreate credential table
  local i = 0
  for index, entry in pairs(cred_table) do
    if entry.credentialIndex ~= credIdx then
      table.insert(new_cred_table, entry)
    end
  end

  device:emit_event(capabilities.lockCredentials.credentials(new_cred_table, {visibility = {displayed = false}}))
end

local function delete_credential_from_table_as_user(device, userIdx)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! delete_credential_from_table_as_user !!!!!!!!!!!!!")) -- needs to remove
  -- If User Index is ALL_INDEX, remove all entry from the table
  if userIdx == ALL_INDEX then
    device:emit_event(capabilities.lockCredentials.credentials({}, {visibility = {displayed = false}}))
  end

  -- Get latest credential table
  local cred_table = device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME
  ) or {}
  local new_cred_table = {}

  -- Recreate credential table
  local i = 0
  for index, entry in pairs(cred_table) do
    if entry.userIndex ~= userIdx then
      table.insert(new_cred_table, entry)
    end
  end

  device:emit_event(capabilities.lockCredentials.credentials(new_cred_table, {visibility = {displayed = false}}))
end

-----------------------------
-- Week Day Schedule Table --
-----------------------------
local WEEK_DAY_MAP = {
  ["Sunday"] = 1,
  ["Monday"] = 2,
  ["Tuesday"] = 4,
  ["Wednesday"] = 8,
  ["Thursday"] = 16,
  ["Friday"] = 32,
  ["Saturday"] = 64,
}

local function add_week_schedule_to_table(device, userIdx, scheduleIdx, schedule)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! add_week_schedule_to_table !!!!!!!!!!!!!")) -- needs to remove

  -- Get latest week day schedule table
  local week_schedule_table = device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.weekDaySchedules.NAME
  ) or {}
  local new_week_schedule_table = {}

  -- Find shcedule list
  local i = 0
  for index, entry in pairs(week_schedule_table) do
    if entry.userIndex == userIdx then
      i = index
    end
    table.insert(new_week_schedule_table, entry)
  end

  -- Recreate weekDays list
  local weekDayList = {}
  for _, weekday in ipairs(schedule.weekDays) do
    table.insert(weekDayList, weekday)
    log.info_with({hub_logs=true}, string.format("weekDay: %s", weekday)) -- needs to remove
  end

  if i ~= 0 then -- Add schedule for existing user
    local new_schedule_table = {}
    for index, entry in pairs(new_week_schedule_table[i].schedules) do
      if entry.scheduleIndex == scheduleIdx then
        return
      end
      table.insert(new_schedule_table, entry)
    end

    table.insert(
      new_schedule_table,
      {
        scheduleIndex = scheduleIdx,
        weekdays = weekDayList,
        startHour = schedule.startHour,
        startMinute = schedule.startMinute,
        endHour = schedule.endHour,
        endMinute = schedule.endMinute
      }
    )

    new_week_schedule_table[i].schedules = new_schedule_table
  else -- Add schedule for new user
    log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! add_week_schedule_to_table 2!!!!!!!!!!!!!")) -- needs to remove
    table.insert(
      new_week_schedule_table,
      {
        userIndex = userIdx,
        schedules = {{
          scheduleIndex = scheduleIdx,
          weekdays = weekDayList,
          startHour = schedule.startHour,
          startMinute = schedule.startMinute,
          endHour = schedule.endHour,
          endMinute = schedule.endMinute
        }}
      }
    )
  end

  device:emit_event(capabilities.lockSchedules.weekDaySchedules(new_week_schedule_table, {visibility = {displayed = false}}))
end

local function delete_week_schedule_to_table(device, userIdx, scheduleIdx)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! delete_week_schedule_to_table !!!!!!!!!!!!!")) -- needs to remove

  -- Get latest week day schedule table
  local week_schedule_table = device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.weekDaySchedules.NAME
  ) or {}
  local new_week_schedule_table = {}

  -- Find shcedule list
  local i = 0
  for index, entry in pairs(week_schedule_table) do
    if entry.userIndex == userIdx then
      i = index
    end
    table.insert(new_week_schedule_table, entry)
  end

  -- When there is no userIndex in the table
  if i == 0 then
    log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! No userIndex in Week Day Schedule Table !!!!!!!!!!!!!", i)) -- needs to remove
    return
  end

  -- Recreate schedule table for the user
  local new_schedule_table = {}
  for index, entry in pairs(new_week_schedule_table[i].schedules) do
    if entry.scheduleIndex ~= scheduleIdx then
      table.insert(new_schedule_table, entry)
    end
  end

  -- If user has no schedule, remove user from the table
  if #new_schedule_table == 0 then
    log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! No schedule for User !!!!!!!!!!!!!", i)) -- needs to remove
    table.remove(new_week_schedule_table, i)
  else
    new_week_schedule_table[i].schedules = new_schedule_table
  end

  device:emit_event(capabilities.lockSchedules.weekDaySchedules(new_week_schedule_table, {visibility = {displayed = false}}))
end

--------------
-- Add User --
--------------
local function handle_add_user(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_add_user !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "addUser"
  local userName = command.args.userName
  local userType = command.args.lockUserType
  local userTypeMatter = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  if userType == "guest" then
    userTypeMatter = DoorLock.types.UserTypeEnum.SCHEDULE_RESTRICTED_USER
  end

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockUsers.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  -- device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.USER_TYPE, userType, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("userName: %s", userName))
  log.info_with({hub_logs=true}, string.format("userType: %s", userType))
  log.info_with({hub_logs=true}, string.format("userTypeMatter: %s", userTypeMatter))
    
  -- Send command
  device:send(
    DoorLock.server.commands.SetUser(
      device, ep,
      DoorLock.types.DlDataOperationType.ADD, -- Operation Type: Add(0), Modify(2)
      userName,         -- User Name
      nil,              -- Unique ID
      nil,              -- User Status
      userTypeMatter,   -- User Type
      nil               -- Credential Rule
    )
  )
end

-----------------
-- Update User --
-----------------
local function handle_update_user(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_update_user !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "updateUser"
  local userIdx = command.args.userIndex
  local userName = command.args.userName
  local userType = command.args.lockUserType
  local userTypeMatter = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  if userType == "guest" then
    userTypeMatter = DoorLock.types.UserTypeEnum.SCHEDULE_RESTRICTED_USER
  end

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockUsers.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.USER_TYPE, userType, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("userIndex: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("userName: %s", userName))
  log.info_with({hub_logs=true}, string.format("userType: %s", userType))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetUser(
      device, ep,
      DoorLock.types.DlDataOperationType.MODIFY, -- Operation Type: Add(0), Modify(2)
      userIdx,        -- User Index
      userName,       -- User Name
      nil,            -- Unique ID
      nil,            -- User Status
      userTypeMatter, -- User Type
      nil             -- Credential Rule
    )
  )
end

-----------------------
-- Set User Response --
-----------------------
local function set_user_response_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! set_user_response_handler !!!!!!!!!!!!!")) -- needs to remove

  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local userType = device:get_field(lock_utils.USER_TYPE)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.OCCUPIED then
    status = "occupied"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end
  
  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("userIdx: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("userType: %s", userType))
  log.info_with({hub_logs=true}, string.format("status: %s", status))

  -- Update User in table
  if status == "success" then
    if cmdName == "addUser" then
      add_user_to_table(device, userIdx, userType)
    elseif cmdName == "updateUser" then
      update_user_in_table(device, userIdx, userType)
    end
  end

  -- Update commandResult
  local result = {
    commandName = cmdName,
    userIndex = userIdx,
    statusCode = status
  }
  local event = capabilities.lockUsers.commandResult(
    result,
    {
      state_change = true,
      visibility = {displayed = false}
    }
  )
  device:emit_event(event)
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

-----------------
-- Delete User --
-----------------
local function handle_delete_user(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_delete_user !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "deleteUser"
  local userIdx = command.args.userIndex

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockUsers.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("userIndex: %s", userIdx))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearUser(device, ep, userIdx))
end

----------------------
-- Delete All Users --
----------------------
local function handle_delete_all_users(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_delete_all_users !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "deleteAllUsers"

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockUsers.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, ALL_INDEX, {persist = true})

  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName)) -- needs to remove

  -- Send command
  device:send(DoorLock.server.commands.ClearUser(device, ep, ALL_INDEX))
end

-------------------------
-- Clear User Response --
-------------------------
local function clear_user_response_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! clear_user_response_handler !!!!!!!!!!!!!")) -- needs to remove

  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end

  -- Delete User and Credential from table
  if status == "success" then
    delete_user_from_table(device, userIdx)
    delete_credential_from_table_as_user(device, userIdx)
  end

  -- Update commandResult
  local result = {
    commandName = cmdName,
    userIndex = userIdx,
    statusCode = status
  }
  local event = capabilities.lockUsers.commandResult(
    result,
    {

      visibility = {displayed = false}
    })
  device:emit_event(event)
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

--------------------
-- Add Credential --
--------------------
local function handle_add_credential(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_add_credential !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "addCredential"
  local userIdx = command.args.userIndex
  if userIdx == 0 then
    userIdx = nil
  end
  local userType = command.args.userType
  local userTypeMatter = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  if userType == "guest" then
    userTypeMatter = DoorLock.types.UserTypeEnum.SCHEDULE_RESTRICTED_USER
  end
  local credential = {
    credential_type = DoorLock.types.CredentialTypeEnum.PIN,
    credential_index = INITIAL_COTA_INDEX
  }
  local credData = command.args.credentialData

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockCredentials.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.USER_TYPE, userType, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, INITIAL_COTA_INDEX, {persist = true})
  device:set_field(lock_utils.CRED_DATA, credData, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("userIndex: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("userType: %s", userType))
  log.info_with({hub_logs=true}, string.format("credIndex: %s", INITIAL_COTA_INDEX))
  log.info_with({hub_logs=true}, string.format("credData: %s", credData))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetCredential(
      device, ep,
      DoorLock.types.DlDataOperationType.ADD, -- Data Operation Type: Add(0), Modify(2)
      credential,     -- Credential
      credData,       -- Credential Data
      userIdx,        -- User Index
      nil,            -- User Status
      userTypeMatter  -- User Type
    )
  )
end

-----------------------
-- Update Credential --
-----------------------
local function handle_update_credential(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_update_credential !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "updateCredential"
  local userIdx = command.args.userIndex
  local credIdx = command.args.credentialIndex
  local credential = {
    credential_type = DoorLock.types.CredentialTypeEnum.PIN,
    credential_index = credIdx
  }
  local credData = command.args.credentialData

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockCredentials.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, credIdx, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("userIndex: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("credentialIndex: %s", credIdx))
  log.info_with({hub_logs=true}, string.format("credData: %s", credData))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetCredential(
      device, ep,
      DoorLock.types.DlDataOperationType.MODIFY, -- Data Operation Type: Add(0), Modify(2)
      credential,  -- Credential
      credData,    -- Credential Data
      userIdx,     -- User Index
      nil,         -- User Status
      nil          -- User Type
    )
  )
end

-----------------------------
-- Set Credential Response --
-----------------------------
local function set_credential_response_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! set_credential_response_handler !!!!!!!!!!!!!")) -- needs to remove

  if ib.status ~= im.InteractionResponse.Status.SUCCESS then
    device.log.error("Failed to set credential for device")
    return
  end

  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local credIdx = device:get_field(lock_utils.CRED_INDEX)
  local status = "success"

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("cmdName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("userIdx: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("credIdx: %s", credIdx))

  local elements = ib.info_block.data.elements
  if elements.status.value == DoorLock.types.DlStatus.SUCCESS then
    -- If user is added also, update User table
    if userIdx == nil then
      local userType = device:get_field(lock_utils.USER_TYPE)
      add_user_to_table(device, elements.user_index.value, userType)
    end

    -- Update Credential table
    userIdx = elements.user_index.value
    if cmdName == "addCredential" then
      add_credential_to_table(device, userIdx, credIdx, "pin")
    end

    -- Update commandResult
    local result = {
      commandName = cmdName,
      userIndex = userIdx,
      credentialIndex = credIdx,
      statusCode = status
    }
    local event = capabilities.lockCredentials.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
    return
  end

  -- @field public byte_length number 1
  -- @field public SUCCESS number 0
  -- @field public FAILURE number 1
  -- @field public DUPLICATE number 2
  -- @field public OCCUPIED number 3
  -- @field public INVALID_FIELD number 133
  -- @field public RESOURCE_EXHAUSTED number 137
  -- @field public NOT_FOUND number 139
 
  -- Update commandResult
  status = "occupied"
  if elements.status.value == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif elements.status.value == DoorLock.types.DlStatus.DUPLICATE then
    status = "duplicate"
  elseif elements.status.value == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  elseif elements.status.value == DoorLock.types.DlStatus.RESOURCE_EXHAUSTED then
    status = "resourceExhausted"
  elseif elements.status.value == DoorLock.types.DlStatus.NOT_FOUND then
    status = "failure"
  end
  log.info_with({hub_logs=true}, string.format("Result: %s", status)) -- needs to remove

  if status ~= "occupied" then
    local result = {
      commandName = cmdName,
      statusCode = status
    }
    local event = capabilities.lockCredentials.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
    return
  end

  if elements.next_credential_index.value ~= nil then
    -- Get parameters
    local credIdx = elements.next_credential_index.value
    local credential = {
      credential_type = DoorLock.types.DlCredentialType.PIN,
      credential_index = credIdx,
    }
    local credData = device:get_field(lock_utils.CRED_DATA)
    local userIdx = device:get_field(lock_utils.USER_INDEX)
    local userType = device:get_field(lock_utils.USER_TYPE)
    local userTypeMatter = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
    if userType == "guest" then
      userTypeMatter = DoorLock.types.UserTypeEnum.SCHEDULE_RESTRICTED_USER
    end

    -- needs to remove logs
    log.info_with({hub_logs=true}, string.format("credentialIndex: %s", credIdx))
    log.info_with({hub_logs=true}, string.format("credData: %s", credData))
    log.info_with({hub_logs=true}, string.format("userIndex: %s", userIdx))
    log.info_with({hub_logs=true}, string.format("userType: %s", userType))

    device:set_field(lock_utils.CRED_INDEX, credIdx, {persist = true})

    -- Sned command
    local ep = find_default_endpoint(device, DoorLock.ID)
    device:send(
      DoorLock.server.commands.SetCredential(
        device, ep,
        DoorLock.types.DlDataOperationType.ADD, -- Data Operation Type: Add(0), Modify(2)
        credential,    -- Credential
        credData,      -- Credential Data
        userIdx,       -- User Index
        nil,           -- User Status
        userTypeMatter -- User Type
      )
    )
  else
    local result = {
      commandName = cmdName,
      statusCode = "resourceExhausted" -- No more available credential index
    }
    local event = capabilities.lockCredentials.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  end
end

-----------------------
-- Delete Credential --
-----------------------
local function handle_delete_credential(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_delete_credential !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "deleteCredential"
  local credIdx = command.args.credentialIndex
  local credential = {
    credential_type = DoorLock.types.DlCredentialType.PIN,
    credential_index = credIdx,
  }

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockCredentials.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, credIdx, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("credentialIndex: %s", credIdx))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearCredential(device, ep, credential))
end

----------------------------
-- Delete All Credentials --
----------------------------
local function handle_delete_all_credentials(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_delete_all_credentials !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "deleteAllCredentials"
  local credential = {
    credential_type = DoorLock.types.DlCredentialType.PIN,
    credential_index = ALL_INDEX,
  }

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockCredentials.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, ALL_INDEX, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("credentialIndex: %s", ALL_INDEX))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearUser(device, ep, credential))
end

-------------------------------
-- Clear Credential Response --
-------------------------------
local function clear_credential_response_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! clear_credential_response_handler !!!!!!!!!!!!!")) -- needs to remove

  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local credIdx = device:get_field(lock_utils.CRED_INDEX)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end

  -- Delete User in table
  if status == "success" then
    delete_credential_from_table(device, credIdx)
  end
  
  -- Update commandResult
  local result = {
    commandName = cmdName,
    credentialIndex = credIdx,
    statusCode = status
  }
  local event = capabilities.lockCredentials.commandResult(
    result,
    {
      state_change = true,
      visibility = {displayed = false}
    }
  )
  device:emit_event(event)
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

---------------------------
-- Set Week Day Schedule --
---------------------------
local function handle_set_week_day_schedule(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_set_week_day_schedule !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "setWeekDaySchedule"
  local scheduleIdx = command.args.scheduleIndex
  local userIdx = command.args.userIndex
  local schedule = command.args.schedule
  local scheduleBit = 0
  for _, weekDay in ipairs(schedule.weekDays) do
    scheduleBit = scheduleBit + WEEK_DAY_MAP[weekDay]
    log.info_with({hub_logs=true}, string.format("%s, %s", WEEK_DAY_MAP[weekDay], weekDay)) -- needs to remove
  end
  local startHour = schedule.startHour
  local startMinute = schedule.startMinute
  local endHour = schedule.endHour
  local endMinute = schedule.endMinute

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockSchedules.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.SCHEDULE_INDEX, scheduleIdx, {persist = true})
  device:set_field(lock_utils.SCHEDULE, schedule, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("scheduleIndex: %s", scheduleIdx))
  log.info_with({hub_logs=true}, string.format("userIndex: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("weekDay[1]: %s", schedule.weekDays[1]))
  log.info_with({hub_logs=true}, string.format("weekDay[2]: %s", schedule.weekDays[2]))
  log.info_with({hub_logs=true}, string.format("weekDay[3]: %s", schedule.weekDays[3]))
  log.info_with({hub_logs=true}, string.format("weekDay[4]: %s", schedule.weekDays[4]))
  log.info_with({hub_logs=true}, string.format("weekDay[5]: %s", schedule.weekDays[5]))
  log.info_with({hub_logs=true}, string.format("weekDay[6]: %s", schedule.weekDays[6]))
  log.info_with({hub_logs=true}, string.format("weekDay[7]: %s", schedule.weekDays[7]))
  log.info_with({hub_logs=true}, string.format("scheduleBit: %s", scheduleBit))
  log.info_with({hub_logs=true}, string.format("startHour: %s", startHour))
  log.info_with({hub_logs=true}, string.format("startMinute: %s", startMinute))
  log.info_with({hub_logs=true}, string.format("endHour: %s", endHour))
  log.info_with({hub_logs=true}, string.format("endMinute: %s", endMinute))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetWeekDaySchedule(
      device, ep,
      scheduleIdx,   -- Week Day Schedule Index
      userIdx,       -- User Index
      scheduleBit,   -- Days Mask
      startHour,     -- Start Hour
      startMinute,   -- Start Minute
      endHour,       -- End Hour
      endMinute      -- End Minute
    )
  )
end

------------------------------------
-- Set Week Day Schedule Response --
------------------------------------
local function set_week_day_schedule_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! set_week_day_schedule_handler !!!!!!!!!!!!!")) -- needs to remove

  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local scheduleIdx = device:get_field(lock_utils.SCHEDULE_INDEX)
  local schedule = device:get_field(lock_utils.SCHEDULE)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end

  -- Add Week Day Schedule to table
  if status == "success" then
    add_week_schedule_to_table(device, userIdx, scheduleIdx, schedule)
  end
  
  -- Update commandResult
  local result = {
    commandName = cmdName,
    userIndex = userIdx,
    scheduleIndex = scheduleIdx,
    statusCode = status
  }
  local event = capabilities.lockSchedules.commandResult(
    result,
    {
      state_change = true,
      visibility = {displayed = false}
    }
  )
  device:emit_event(event)
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

-----------------------------
-- Clear Week Day Schedule --
-----------------------------
local function handle_clear_week_day_schedule(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_clear_week_day_schedule !!!!!!!!!!!!!")) -- needs to remove

  -- Get parameters
  local cmdName = "clearWeekDaySchedule"
  local scheduleIdx = command.args.scheduleIndex
  local userIdx = command.args.userIndex

  -- Check busy state
  local busy = device:get_field(lock_utils.BUSY_STATE)
  if busy == true then
    local result = {
      commandName = cmdName,
      statusCode = "busy"
    }
    local event = capabilities.lockSchedules.commandResult(
      result,
      {
        state_change = true,
        visibility = {displayed = false}
      }
    )
    device:emit_event(event)
    return
  end

  device:set_field(lock_utils.BUSY_STATE, true, {persist = true})
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.SCHEDULE_INDEX, scheduleIdx, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("commandName: %s", cmdName))
  log.info_with({hub_logs=true}, string.format("scheduleIndex: %s", scheduleIdx))
  log.info_with({hub_logs=true}, string.format("userIndex: %s", userIdx))

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearWeekDaySchedule(device, ep, scheduleIdx, userIdx))
end

------------------------------------
-- Clear Week Day Schedule Response --
------------------------------------
local function clear_week_day_schedule_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! clear_week_day_schedule_handler !!!!!!!!!!!!!")) -- needs to remove

  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local scheduleIdx = device:get_field(lock_utils.SCHEDULE_INDEX)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end

  -- Delete Week Day Schedule to table
  if status == "success" then
    delete_week_schedule_to_table(device, userIdx, scheduleIdx)
  end
  
  -- Update commandResult
  local result = {
    commandName = cmdName,
    userIndex = userIdx,
    scheduleIndex = scheduleIdx,
    statusCode = status
  }
  local event = capabilities.lockSchedules.commandResult(
    result,
    {
      state_change = true,
      visibility = {displayed = false}
    }
  )
  device:emit_event(event)
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

---------------------------
-- Set Year Day Schedule --
---------------------------
local function handle_set_year_day_schedule(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_set_year_day_schedule !!!!!!!!!!!!!")) -- needs to remove
end

-----------------------------
-- Clear Year Day Schedule --
-----------------------------
local function handle_clear_year_day_schedule(driver, device, command)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! handle_clear_year_day_schedule !!!!!!!!!!!!!")) -- needs to remove
end

----------------
-- Lock Alarm --
----------------
local function alarm_event_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! alarm_event_handler !!!!!!!!!!!!!")) -- needs to remove
  local DlAlarmCode = DoorLock.types.DlAlarmCode
  local alarm_code = ib.data.elements.alarm_code
  if alarm_code.value == DlAlarmCode.LOCK_JAMMED then
    device:emit_event(capabilities.lockAlarm.alarm.unableToLockTheDoor({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.LOCK_FACTORY_RESET then
    device:emit_event(capabilities.lockAlarm.alarm.lockFactoryReset({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.WRONG_CODE_ENTRY_LIMIT then
    device:emit_event(capabilities.lockAlarm.alarm.attemptsExceeded({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.FRONT_ESCEUTCHEON_REMOVED then
    device:emit_event(capabilities.lockAlarm.alarm.damaged({state_change = true}))
  elseif alarm_code.value == DlAlarmCode.DOOR_FORCED_OPEN then
    device:emit_event(capabilities.lockAlarm.alarm.forcedOpeningAttempt({state_change = true}))
  end
end

--------------------
-- Lock Operation --
--------------------
local function lock_op_event_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! lock_op_event_handler !!!!!!!!!!!!!")) -- needs to remove
  local opType = ib.data.elements.lock_operation_type
  local opSource = ib.data.elements.operation_source
  local userIdx = ib.data.elements.user_index
  local fabricId = ib.data.elements.fabric_index

  if opType == nil or opSource == nil then
    return
  end

  local Type = DoorLock.types.LockOperationTypeEnum
  local Lock = capabilities.lock.lock
  if opType.value == Type.LOCK then
    opType = Lock.locked
  elseif opType.value == Type.UNLOCK then
    opType = Lock.unlocked
  elseif opType.value == Type.UNLATCH then
    opType = Lock.locked
  else
    return
  end

  local Source = DoorLock.types.OperationSourceEnum
  if opSource.value == Source.UNSPECIFIED then
    opSource = nil
  elseif opSource.value == Source.MANUAL then
    opSource = "manual"
  elseif opSource.value == Source.PROPRIETARY_REMOTE then
    opSource = "proprietaryRemote"
  elseif opSource.value == Source.KEYPAD then
    opSource = "keypad"
  elseif opSource.value == Source.AUTO then
    opSource = "auto"
  elseif opSource.value == Source.BUTTON then
    opSource = "button"
  elseif opSource.value == Source.SCHEDULE then
    opSource = nil
  elseif opSource.value == Source.REMOTE then
    opSource = "command"
  elseif opSource.value == Source.RFID then
    opSource = "rfid"
  elseif opSource.value == Source.BIOMETRIC then
    opSource = "keypad"
  elseif opSource.value == Source.ALIRO then
    opSource = nil
  else
    opSource =nil
  end

  if fabricId ~= nil then
    fabricId = fabricId.value
  end
 
  if userIdx ~= nil then
    userIdx = userIdx.value
  end

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("opType: %s", opType.NAME))
  log.info_with({hub_logs=true}, string.format("opSource: %s", opSource))
  log.info_with({hub_logs=true}, string.format("userIdx: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("fabricId: %s", fabricId))

  local data_obj = {method = opSource, userIndex = userIdx}
  device:emit_event(opType({data = data_obj, state_change = true}))
end

----------------------
-- Lock User Change --
----------------------
local function lock_user_change_event_handler(driver, device, ib, response)
  log.info_with({hub_logs=true}, string.format("!!!!!!!!!!!!!!! lock_user_change_event_handler !!!!!!!!!!!!!")) -- needs to remove
  local lockDataType = ib.data.elements.lock_data_type
  local dataOpType = ib.data.elements.data_operation_type
  local opSource = ib.data.elements.operation_source
  local userIdx = ib.data.elements.user_index
  local fabricId = ib.data.elements.fabric_index

  if lockDataType ~= nil then
    lockDataType = lockDataType.value
  end

  if dataOpType ~= nil then
    dataOpType = dataOpType.value
  end

  local Source = DoorLock.types.OperationSourceEnum
  if opSource.value == Source.UNSPECIFIED then
    opSource = nil
  elseif opSource.value == Source.MANUAL then
    opSource = "manual"
  elseif opSource.value == Source.PROPRIETARY_REMOTE then
    opSource = "proprietaryRemote"
  elseif opSource.value == Source.KEYPAD then
    opSource = "keypad"
  elseif opSource.value == Source.AUTO then
    opSource = "auto"
  elseif opSource.value == Source.BUTTON then
    opSource = "button"
  elseif opSource.value == Source.SCHEDULE then
    opSource = nil
  elseif opSource.value == Source.REMOTE then
    opSource = "command"
  elseif opSource.value == Source.RFID then
    opSource = "rfid"
  elseif opSource.value == Source.BIOMETRIC then
    opSource = "keypad"
  elseif opSource.value == Source.ALIRO then
    opSource = nil
  else
    opSource =nil
  end

  if userIdx ~= nil then
    userIdx = userIdx.value
  end

  if fabricId ~= nil then
    fabricId = fabricId.value
  end

  -- needs to remove logs
  log.info_with({hub_logs=true}, string.format("lockDataType: %s", lockDataType))
  log.info_with({hub_logs=true}, string.format("dataOpType: %s", dataOpType))
  log.info_with({hub_logs=true}, string.format("opSource: %s", opSource))
  log.info_with({hub_logs=true}, string.format("userIdx: %s", userIdx))
  log.info_with({hub_logs=true}, string.format("fabricId: %s", fabricId))

  -- local data_obj = {method = opSource, userIndex = userIdx}
  -- device:emit_event(opType({data = data_obj}, {state_change = true}))
end

local function handle_refresh(driver, device, command)
  local req = DoorLock.attributes.LockState:read(device)
  device:send(req)
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

local new_matter_lock_handler = {
  NAME = "New Matter Lock Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
  matter_handlers = {
    attr = {
      [DoorLock.ID] = {
        [DoorLock.attributes.LockState.ID] = lock_state_handler,
        [DoorLock.attributes.OperatingMode.ID] = operating_modes_handler,
        [DoorLock.attributes.NumberOfTotalUsersSupported.ID] = total_users_supported_handler,
        [DoorLock.attributes.NumberOfPINUsersSupported.ID] = pin_users_supported_handler,
        [DoorLock.attributes.MinPINCodeLength.ID] = min_pin_code_len_handler,
        [DoorLock.attributes.MaxPINCodeLength.ID] = max_pin_code_len_handler,
        [DoorLock.attributes.RequirePINforRemoteOperation.ID] = require_remote_pin_handler,
        [DoorLock.attributes.NumberOfWeekDaySchedulesSupportedPerUser.ID] = max_week_schedule_of_user_handler,
        [DoorLock.attributes.NumberOfYearDaySchedulesSupportedPerUser.ID] = max_year_schedule_of_user_handler,
      }
    },
    event = {
      [DoorLock.ID] = {
        [DoorLock.events.DoorLockAlarm.ID] = alarm_event_handler,
        [DoorLock.events.LockOperation.ID] = lock_op_event_handler,
        [DoorLock.events.LockUserChange.ID] = lock_user_change_event_handler,
      },
    },
    cmd_response = {
      [DoorLock.ID] = {
        [DoorLock.server.commands.SetUser.ID] = set_user_response_handler,
        [DoorLock.server.commands.ClearUser.ID] = clear_user_response_handler,
        [DoorLock.client.commands.SetCredentialResponse.ID] = set_credential_response_handler,
        [DoorLock.server.commands.ClearCredential.ID] = clear_credential_response_handler,
        [DoorLock.server.commands.SetWeekDaySchedule.ID] = set_week_day_schedule_handler,
        [DoorLock.server.commands.ClearWeekDaySchedule.ID] = clear_week_day_schedule_handler,
      },
    },
  },
  subscribed_attributes = subscribed_attributes,
  subscribed_events = subscribed_events,
  capability_handlers = {
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = handle_lock,
      [capabilities.lock.commands.unlock.NAME] = handle_unlock,
    },
    [capabilities.lockUsers.ID] = {
      [capabilities.lockUsers.commands.addUser.NAME] = handle_add_user,
      [capabilities.lockUsers.commands.updateUser.NAME] = handle_update_user,
      [capabilities.lockUsers.commands.deleteUser.NAME] = handle_delete_user,
      [capabilities.lockUsers.commands.deleteAllUsers.NAME] = handle_delete_all_users,
    },
    [capabilities.lockCredentials.ID] = {
      [capabilities.lockCredentials.commands.addCredential.NAME] = handle_add_credential,
      [capabilities.lockCredentials.commands.updateCredential.NAME] = handle_update_credential,
      [capabilities.lockCredentials.commands.deleteCredential.NAME] = handle_delete_credential,
      [capabilities.lockCredentials.commands.deleteAllCredentials.NAME] = handle_delete_all_credentials,
    },
    [capabilities.lockSchedules.ID] = {
      [capabilities.lockSchedules.commands.setWeekDaySchedule.NAME] = handle_set_week_day_schedule,
      [capabilities.lockSchedules.commands.clearWeekDaySchedules.NAME] = handle_clear_week_day_schedule,
      [capabilities.lockSchedules.commands.setYearDaySchedule.NAME] = handle_set_year_day_schedule,
      [capabilities.lockSchedules.commands.clearYearDaySchedules.NAME] = handle_clear_year_day_schedule,
    },
    [capabilities.refresh.ID] = {[capabilities.refresh.commands.refresh.NAME] = handle_refresh}
  },
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockUsers,
    capabilities.lockCredentials,
    capabilities.lockSchedules
  },
  can_handle = is_new_matter_lock_products
}

return new_matter_lock_handler