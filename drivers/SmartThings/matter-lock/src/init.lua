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

local MatterDriver = require "st.matter.driver"
local interaction_model = require "st.matter.interaction_model"
local Status = interaction_model.InteractionResponse.Status
local clusters = require "st.matter.clusters"

local DoorLock = clusters.DoorLock
local PowerSource = clusters.PowerSource

local capabilities = require "st.capabilities"
local log = require "log"
local json = require "st.json"
local im = require "st.matter.interaction_model"
local utils = require "st.utils"
local lock_utils = require "lock_utils"

local YALE_LOCK_FINGERPRINT = {{vendorId = 0x101D, productId = 0x1}}

local function set_cota_credential(device)
  -- Device requires pin for remote operation if it supports COTA and PIN features.
  local eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.DoorLockFeature.CREDENTIALSOTA | DoorLock.types.DoorLockFeature.PIN_CREDENTIALS})
  if #eps == 0 then
    device.log.debug("Device should not require PIN for remote operation, so not setting COTA credential")
    return
  end
  local endpoint = eps[1]

  -- If we are scanning codes, we should wait to set the cota credential until scanning completes
  -- to help avoid replacing an existing code, and ensure we have queried the max codes on the device.
  if device:get_latest_state(
    "main", capabilities.lockCodes.ID, capabilities.lockCodes.scanCodes.NAME
  ) == "Scanning" then
    device.thread:call_with_delay(2, function(t)
      set_cota_credential(device)
    end)
    return
  end

  local len = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME) or 4
  local cred_data = math.floor(math.random() * (10 ^ len))
  cred_data = string.format("%0" .. tostring(len) .. "d", cred_data)
  device:set_field(lock_utils.COTA_CRED, cred_data, {persist = true})
  --try to use last code slot in hopes that it wont overwrite existing codes on the device
  local credential_index = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME) or 1
  local credential = {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = credential_index}

  -- Clear the credential to make sure that we have an open slot for the cota credential
  device.thread:call_with_delay(0, function(t)
    --Note we dont set lock_utils.DELETEING_CODE field to avoid re-setting cota credential this time
    device:send(DoorLock.server.commands.ClearCredential(
      device,
      endpoint,
      credential
    ))
  end)

  -- Set the credential to a code
  device.thread:call_with_delay(2, function(t)
    device:set_field(lock_utils.SET_CREDENTIAL, credential_index)
    device:send(DoorLock.server.commands.SetCredential(
      device, endpoint, DoorLock.types.DlDataOperationType.ADD,
      credential,
      device:get_field(lock_utils.COTA_CRED),
      nil, -- nil user_index creates a new user
      DoorLock.types.DlUserStatus.OCCUPIED_ENABLED,
      DoorLock.types.DlUserType.REMOTE_ONLY_USER
    ))
  end)
end

local function lock_state_handler(driver, device, ib, response)
  local LockState = DoorLock.attributes.LockState
  local attr = capabilities.lock.lock
  local LOCK_STATE = {
    [LockState.NOT_FULLY_LOCKED] = attr.unknown(),
    [LockState.LOCKED] = attr.locked(),
    [LockState.UNLOCKED] = attr.unlocked(),
  }

  if ib.data.value ~= nil then
    device:emit_event(LOCK_STATE[ib.data.value])
  else
    device:emit_event(LOCK_STATE[LockState.NOT_FULLY_LOCKED])
  end
end

local function handle_battery_percent_remaining(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

local function max_pin_code_len_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockCodes.maxCodeLength(ib.data.value, {visibility = {displayed = false}}))
end

local function min_pin_code_len_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockCodes.minCodeLength(ib.data.value, {visibility = {displayed = false}}))
end

local function num_pin_users_handler(driver, device, ib, response)
  device:set_field(lock_utils.TOTAL_PIN_USERS, ib.data.value)
  local creds_per_user = device:get_field(lock_utils.CREDENTIALS_PER_USER)
  if creds_per_user and creds_per_user > 0 then
    device:emit_event(capabilities.lockCodes.maxCodes(ib.data.value * creds_per_user, {visibility = {displayed = false}}))
  end
end

local function num_creds_per_user_handler(driver, device, ib, response)
  device:set_field(lock_utils.CREDENTIALS_PER_USER, ib.data.value)
  local num_pin_users = device:get_field(lock_utils.TOTAL_PIN_USERS)
  if num_pin_users and num_pin_users > 0 then
    device:emit_event(capabilities.lockCodes.maxCodes(ib.data.value * num_pin_users, {visibility = {displayed = false}}))
  end
end

local function num_total_users_handler(driver, device, ib, response)
  device:set_field(lock_utils.TOTAL_USERS, ib.data.value)
end

local function clear_credential_response_handler(driver, device, ib, response)
  local deleted_code_slot = device:get_field(lock_utils.DELETING_CODE)
  if deleted_code_slot == nil then
    device.log.debug("Cleared space in lock credential db for COTA credential")
    return
  end
  local max_codes = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
  if ib.status == im.InteractionResponse.Status.SUCCESS then
    lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, tostring(deleted_code_slot)))
    if deleted_code_slot == max_codes then --make sure cota credential exists if the user deletes it
      set_cota_credential(device)
    end
  else
    device.log.error(string.format("Failed to delete code slot %s", deleted_code_slot))
  end
  device:set_field(lock_utils.DELETING_CODE, nil)
end

local function set_credential_response_handler(driver, device, ib, response)
  if ib.status ~= im.InteractionResponse.Status.SUCCESS then
    device.log.error("Failed to set code for device")
    return
  end
  local elements = ib.info_block.data.elements
  local credential_index = device:get_field(lock_utils.SET_CREDENTIAL)
  device:set_field(lock_utils.SET_CREDENTIAL, nil)
  if credential_index == nil then
    device.log.error("Received unexpected SetCredentialResponse")
    return
  end
  local code_slot = tostring(credential_index)
  local status = elements.status
  if status.value == DoorLock.types.DlStatus.SUCCESS then
    local event = capabilities.lockCodes.codeChanged("", {state_change = true})
    local max_codes = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
    local code_name = (credential_index == max_codes and lock_utils.COTA_CODE_NAME) or lock_utils.get_code_name(device, code_slot)
    event.data = {codeName = code_name}
    event.value = lock_utils.get_change_type(device, tostring(code_slot))
    local lock_codes = lock_utils.get_lock_codes(device)
    lock_codes[code_slot] = event.data.codeName
    device:emit_event(event)
    if credential_index == max_codes then
      device:emit_event(
        capabilities.lockCodes.codeChanged(
          code_slot .. " renamed", {state_change = true}
        )
      )
    end
    lock_utils.lock_codes_event(device, lock_codes)
    lock_utils.reset_code_state(device, code_slot)
  else
    device.log.error(
      string.format(
        "Failed to set code for device, SetCredential status received: %s", status
      )
    )
  end
end

local function get_credential_status_response_handler(driver, device, ib, response)
  if ib.status ~= im.InteractionResponse.Status.SUCCESS then
    device.log.warn("Not taking action on GetCredentialStatusResponse because failed status")
  end
  local cred_index = device:get_field(lock_utils.CHECKING_CREDENTIAL)
  if cred_index == nil then
    device.log.warn("Received unexpected CredentialStatusResponse")
    return
  end
  local elements = ib.info_block.data.elements
  local user_index = elements.user_index.value
  local credential_exists = elements.credential_exists.value
  local next_credential_index = elements.next_credential_index and elements.next_credential_index.value or nil

  local event = capabilities.lockCodes.codeChanged("", {state_change = true})
  local code_slot = tostring(cred_index)
  local max_codes = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)
  local code_name = (cred_index == max_codes and lock_utils.COTA_CODE_NAME) or lock_utils.get_code_name(device, code_slot)
  event.data = {codeName = code_name}
  if credential_exists then
    -- Code slot is occupied
    event.value = lock_utils.get_change_type(device, code_slot)
    local lock_codes = lock_utils.get_lock_codes(device)
    lock_codes[code_slot] = event.data.codeName
    device:emit_event(event)
    lock_utils.lock_codes_event(device, lock_codes)
    lock_utils.reset_code_state(device, code_slot)
  else
    -- Code slot is unoccupied
    if (lock_utils.get_lock_codes(device)[code_slot] ~= nil) then
      -- Code has been deleted
      lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, code_slot))
      if cred_index == max_codes then --make sure cota credential exists if it was deleted
        set_cota_credential(device)
      end
    else
      -- Code is unset
      event.value = code_slot .. " unset"
      device:emit_event(event)
    end
  end
  device:set_field(lock_utils.CHECKING_CREDENTIAL, nil)

  if (cred_index == device:get_field(lock_utils.CHECKING_CODE)) then
    -- the code we're checking has arrived
    if (next_credential_index == nil) then
      device:emit_event(
        capabilities.lockCodes.scanCodes(
          "Complete", {visibility = {displayed = false}}
        )
      )
      local lock_codes = lock_utils.get_lock_codes(device)
      lock_utils.lock_codes_event(device, lock_codes)
      device:set_field(lock_utils.CHECKING_CODE, nil)
    elseif next_credential_index ~= nil then
      device:set_field(lock_utils.CHECKING_CODE, next_credential_index)
      device:set_field(lock_utils.CHECKING_CREDENTIAL, next_credential_index)
      device:send(
        DoorLock.server.commands.GetCredentialStatus(
          device,
          ib.info_block.endpoint_id,
          {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = device:get_field(lock_utils.CHECKING_CREDENTIAL)}
        )
      )
    end
  end
end

local function alarm_event_handler(driver, device, ib, response)
  local DlAlarmCode = DoorLock.types.DlAlarmCode
  local alarm_code = ib.data.elements.alarm_code
  if alarm_code.value == DlAlarmCode.FRONT_ESCEUTCHEON_REMOVED or alarm_code.value
    == DlAlarmCode.WRONG_CODE_ENTRY_LIMIT or alarm_code.value == DlAlarmCode.FORCED_USER
    or alarm_code.value == DlAlarmCode.DOOR_FORCED_OPEN then
    device:emit_event(capabilities.tamperAlert.tamper.detected())
  end
end

local function lock_op_event_handler(driver, device, ib, response)
  local tamper_detected = device:get_latest_state(
                            device:endpoint_to_component(ib.endopint_id),
                              capabilities.tamperAlert.ID, capabilities.tamperAlert.tamper.NAME
                          )
  if nil == tamper_detected or tamper_detected == capabilities.tamperAlert.tamper.detected.NAME then
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local function lock_user_change_event_handler(driver, device, ib, response)
  local event = capabilities.lockCodes.codeChanged("", {state_change = true})
  local elements = ib.data.elements
  local data_type_changed = elements.lock_data_type.value
  local operation_type = elements.data_operation_type.value
  local user_index = elements.user_index.value
  local data_index = elements.data_index and elements.data_index.value
  local max_codes = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME)

  if data_type_changed == DoorLock.types.DlLockDataType.PIN then -- pin added or removed
    local code_slot = data_index and tostring(data_index) or nil
    if (operation_type == DoorLock.types.DlDataOperationType.ADD or operation_type
      == DoorLock.types.DlDataOperationType.MODIFY) and code_slot ~= nil then
      local change_type = lock_utils.get_change_type(device, code_slot)
      event.value = change_type
      local code_name = (data_index == max_codes and lock_utils.COTA_CODE_NAME) or lock_utils.get_code_name(device, code_slot)
      event.data = {codeName = code_name}
      device:emit_event(event)
      if string.match(change_type, "%d+ set") ~= nil then
        local lock_codes = lock_utils.get_lock_codes(device)
        lock_codes[code_slot] = code_name
        lock_utils.lock_codes_event(device, lock_codes)
      end
    elseif operation_type == DoorLock.types.DlDataOperationType.CLEAR and code_slot ~= nil then
      lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, tostring(code_slot)))
      if data_index == max_codes then --make sure cota credential exists if something deletes it
        set_cota_credential(device)
      end
    else -- invalid event because no credential index
      device.log.error(
        "Received unhandled LockUserChangeEvent because it didn't affect a PIN credential"
      )
    end
  elseif data_type_changed == DoorLock.types.DlLockDataType.USER_INDEX and operation_type
    == DoorLock.types.DlDataOperationType.CLEAR then
    if user_index == 0xFFFE then
      device.log.warn("All users were cleared by another fabric") -- we never do this
      for cs, _ in pairs(lock_utils.get_lock_codes(device)) do
        lock_utils.code_deleted(device, cs)
      end
      lock_utils.lock_codes_event(device, {})
      set_cota_credential(device)
    else
      device.log.info("Not handling LockUserChange event")
    end
    -- TODO Handle single user deletion. Do we need to bookkeep all the credential indexes
    -- associated with a single user so we can delete their ST code slot, or will PIN
    -- events be generated for the deleted credentials?
  else
    device.log.info(
      string.format(
        "Not handling LockUserChange event because the data type (%s) doesn't affect lock codes",
          elements.lock_data_type
      )
    )
  end
end

local function handle_refresh(driver, device, command)
  local req = DoorLock.attributes.LockState:read(device, device.MATTER_DEFAULT_ENDPOINT)
  req:merge(PowerSource.attributes.BatPercentRemaining:read(device, device.MATTER_DEFAULT_ENDPOINT))
  device:send(req)
end

local function handle_lock(driver, device, command)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  if cota_cred then
    device:send(
      DoorLock.server.commands.LockDoor(device, device.MATTER_DEFAULT_ENDPOINT, cota_cred)
    )
  else
    device:send(DoorLock.server.commands.LockDoor(device, device.MATTER_DEFAULT_ENDPOINT))
  end
end

local function handle_unlock(driver, device, command)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  if cota_cred then
    device:send(
      DoorLock.server.commands.UnlockDoor(device, device.MATTER_DEFAULT_ENDPOINT, cota_cred)
    )
  else
    device:send(DoorLock.server.commands.UnlockDoor(device, device.MATTER_DEFAULT_ENDPOINT))
  end
end

local function handle_delete_code(driver, device, command)
  local endpoint = device:component_to_endpoint(command.component)
  device:set_field(lock_utils.DELETING_CODE, command.args.codeSlot)
  device:send(DoorLock.server.commands.ClearCredential(
    device,
    endpoint,
    {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = command.args.codeSlot}
  ))
end

local function handle_reload_all_codes(driver, device, command)
  local endpoint_id = device:component_to_endpoint(command.component)
  -- starts at first user code index then iterates through all lock codes as they come in
  local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
  if (device:get_latest_state(
    "main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME
  ) == nil) then req:merge(clusters.DoorLock.attributes.MaxPINCodeLength:read(device, endpoint_id)) end
  if (device:get_latest_state(
    "main", capabilities.lockCodes.ID, capabilities.lockCodes.minCodeLength.NAME
  ) == nil) then req:merge(clusters.DoorLock.attributes.MinPINCodeLength:read(device, endpoint_id)) end
  if (device:get_latest_state(
    "main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodes.NAME
  ) == nil) then
    req:merge(clusters.DoorLock.attributes.NumberOfPINUsersSupported:read(device, endpoint_id))
    req:merge(clusters.DoorLock.attributes.NumberOfTotalUsersSupported:read(device, endpoint_id))
  end
  if (device.num_creds_per_user == nil) then
    req:merge(
      clusters.DoorLock.attributes.NumberOfCredentialsSupportedPerUser:read(
        device, endpoint_id
      )
    )
  end
  device:send(req)
  if (device:get_field(lock_utils.CHECKING_CODE) == nil) then
    device:set_field(lock_utils.CHECKING_CODE, 1)
  end
  device:emit_event(capabilities.lockCodes.scanCodes("Scanning"))
  device:set_field(lock_utils.CHECKING_CREDENTIAL, device:get_field(lock_utils.CHECKING_CODE))
  device:send(
    clusters.DoorLock.server.commands.GetCredentialStatus(
      device, endpoint_id,
      {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = device:get_field(lock_utils.CHECKING_CODE)}
    )
  )
end

local function handle_request_code(driver, device, command)
  local endpoint_id = device:component_to_endpoint(command.component)
  device:set_field(lock_utils.CHECKING_CREDENTIAL, command.args.codeSlot)
  local credential = {
    credential_type = DoorLock.types.DlCredentialType.PIN,
    credential_index = command.args.codeSlot,
  }
  device:send(clusters.DoorLock.server.commands.GetCredentialStatus(device, endpoint_id, credential))
end

local function handle_set_code(driver, device, command)
  local endpoint = device:component_to_endpoint(command.component)
  if (command.args.codePIN == "") then
    driver:inject_capability_command(
      device, {
        capability = capabilities.lockCodes.ID,
        command = capabilities.lockCodes.commands.nameSlot.NAME,
        args = {command.args.codeSlot, command.args.codeName},
      }
    )
  else
    local credential = {
      credential_type = DoorLock.types.DlCredentialType.PIN,
      credential_index = command.args.codeSlot,
    }
    device:set_field(lock_utils.SET_CREDENTIAL, command.args.codeSlot)
    device:send(
      DoorLock.server.commands.SetCredential(
        device, endpoint, DoorLock.types.DlDataOperationType.ADD, -- operation_type
        credential, command.args.codePIN, -- credential_data
        nil, -- nil user_index creates a new user
        DoorLock.types.DlUserStatus.OCCUPIED_ENABLED, DoorLock.types.DlUserType.UNRESTRICTED_USER
      )
    )
    if (command.args.codeName ~= nil) then
      -- wait for confirmation from the lock to commit this to memory
      -- Groovy driver has a lot more info passed here as a description string, may need to be investigated
      local codeState = device:get_field(lock_utils.CODE_STATE) or {}
      codeState["setName" .. command.args.codeSlot] = command.args.codeName
      device:set_field(lock_utils.CODE_STATE, codeState, {persist = true})
    end
  end
end

local function handle_name_slot(driver, device, command)
  local code_slot = tostring(command.args.codeSlot)
  local lock_codes = lock_utils.get_lock_codes(device)
  if (lock_codes[code_slot] ~= nil) then
    lock_codes[code_slot] = command.args.codeName
    device:emit_event(
      capabilities.lockCodes.codeChanged(
        code_slot .. " renamed", {state_change = true}
      )
    )
    lock_utils.lock_codes_event(device, lock_codes)
  end
end

local function device_init(driver, device) device:subscribe() end

local function device_added(driver, device)
  device:emit_event(capabilities.tamperAlert.tamper.clear())
end

local function do_configure(driver, device)
  local eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.DoorLockFeature.PIN_CREDENTIALS})
  if #eps == 0 then
    device.log.debug("Device does not support lockCodes")
    device:try_update_metadata({profile = "lock-without-codes"})
  else
    driver:inject_capability_command(device, {
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
      args = {}
    })

    -- TODO delay setting device to provisioned until a COTA cred has been set on the device if we need to set it.
    device.thread:call_with_delay(0, function(t)
      set_cota_credential(device)
    end)
  end
end

local matter_lock_driver = {
  matter_handlers = {
    attr = {
      [DoorLock.ID] = {
        [DoorLock.attributes.LockState.ID] = lock_state_handler,
        [DoorLock.attributes.MaxPINCodeLength.ID] = max_pin_code_len_handler,
        [DoorLock.attributes.MinPINCodeLength.ID] = min_pin_code_len_handler,
        [DoorLock.attributes.NumberOfPINUsersSupported.ID] = num_pin_users_handler,
        [DoorLock.attributes.NumberOfTotalUsersSupported.ID] = num_total_users_handler,
        [DoorLock.attributes.NumberOfCredentialsSupportedPerUser.ID] = num_creds_per_user_handler,

      },
      [PowerSource.ID] = {
        [PowerSource.attributes.BatPercentRemaining.ID] = handle_battery_percent_remaining,
      },
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
        [DoorLock.client.commands.SetCredentialResponse.ID] = set_credential_response_handler,
        [DoorLock.client.commands.GetCredentialStatusResponse.ID] = get_credential_status_response_handler,
        [DoorLock.server.commands.ClearCredential.ID] = clear_credential_response_handler,
      },
    },
  },
  subscribed_attributes = {
    [capabilities.lock.ID] = {DoorLock.attributes.LockState},
    [capabilities.battery.ID] = {PowerSource.attributes.BatPercentRemaining},
  },
  subscribed_events = {
    [capabilities.tamperAlert.ID] = {DoorLock.events.DoorLockAlarm, DoorLock.events.LockOperation},
    [capabilities.lockCodes.ID] = {DoorLock.events.LockUserChange},
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {[capabilities.refresh.commands.refresh.NAME] = handle_refresh},
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = handle_lock,
      [capabilities.lock.commands.unlock.NAME] = handle_unlock,
    },
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.deleteCode.NAME] = handle_delete_code,
      [capabilities.lockCodes.commands.reloadAllCodes.NAME] = handle_reload_all_codes,
      [capabilities.lockCodes.commands.requestCode.NAME] = handle_request_code,
      [capabilities.lockCodes.commands.setCode.NAME] = handle_set_code,
      [capabilities.lockCodes.commands.nameSlot.NAME] = handle_name_slot,
    },
  },
  lifecycle_handlers = {init = device_init, added = device_added, doConfigure = do_configure},
}

-----------------------------------------------------------------------------------------------------------------------------
-- Driver Initialization
-----------------------------------------------------------------------------------------------------------------------------
local matter_driver = MatterDriver("matter-lock", matter_lock_driver)
matter_driver:run()
