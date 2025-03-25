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
local clusters = require "st.matter.clusters"

local DoorLock = clusters.DoorLock
local PowerSource = clusters.PowerSource

local capabilities = require "st.capabilities"
local im = require "st.matter.interaction_model"
local lock_utils = require "lock_utils"

local PROFILE_BASE_NAME = "__profile_base_name"

local INITIAL_COTA_INDEX = 1

-- add this definition for locks to work on older lua libs
local UNLATCHED_STATE = 0x3

local subscribed_attributes = {
  [capabilities.lock.ID] = {DoorLock.attributes.LockState},
  [capabilities.battery.ID] = {PowerSource.attributes.BatPercentRemaining},
  [capabilities.batteryLevel.ID] = {PowerSource.attributes.BatChargeLevel},
}

--- If a device needs a cota credential this function attempts to set the credential
--- at the index provided. The set_credential_response_handler handles all failures
--- and retries with the appropriate index when necessary.
local function set_cota_credential(device, credential_index)
  local eps = device:get_endpoints(DoorLock.ID)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  if cota_cred == nil then
    -- Shouldn't happen but defensive to try to figure out if we need the cota cred and set it.
    device:send(DoorLock.attributes.RequirePINforRemoteOperation:read(device, #eps > 0 and eps[1] or 1))
    return
  elseif cota_cred == false then
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
  device:set_field(lock_utils.SET_CREDENTIAL, credential_index)
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
  local len = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.maxCodeLength.NAME) or 4
  local cred_data = math.floor(math.random() * (10 ^ len))
  cred_data = string.format("%0" .. tostring(len) .. "d", cred_data)
  device:set_field(lock_utils.COTA_CRED, cred_data, {persist = true})
end

local function lock_state_handler(driver, device, ib, response)
  local LockState = DoorLock.attributes.LockState
  local attr = capabilities.lock.lock
  local LOCK_STATE = {
    [LockState.NOT_FULLY_LOCKED] = attr.not_fully_locked(),
    [LockState.LOCKED] = attr.locked(),
    [LockState.UNLOCKED] = attr.unlocked(),
    [UNLATCHED_STATE] = attr.unlocked(), -- Fully unlocked with latch pulled
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

local function handle_battery_charge_level(driver, device, ib, response)
  if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

local function handle_power_source_attribute_list(driver, device, ib, response)
  local support_battery_percentage = false
  local support_battery_level = false
  for _, attr in ipairs(ib.data.elements) do
    -- Re-profile the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present.
    if attr.value == 0x0C then
      support_battery_percentage = true
    elseif attr.value == 0x0E then
      support_battery_level = true
    end
  end
  local profile_name = device:get_field(PROFILE_BASE_NAME)
  if profile_name ~= nil then
    if not support_battery_percentage then
      if support_battery_level then
        profile_name = profile_name .. "-batteryLevel"
      else
        profile_name = profile_name .. "-nobattery"
      end
    end
    device.log.info(string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
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
  device:emit_event(capabilities.lockCodes.maxCodes(ib.data.value, {visibility = {displayed = false}}))
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
  if ib.data.value then
    apply_cota_credentials_if_absent(device)
  else
    device:set_field(lock_utils.COTA_CRED, false, {persist = true})
  end
end

local function clear_credential_response_handler(driver, device, ib, response)
  local deleted_code_slot = device:get_field(lock_utils.DELETING_CODE)
  if deleted_code_slot == nil and ib.status == im.InteractionResponse.Status.SUCCESS then
    device.log.debug("Cleared space in lock credential db for COTA credential")
    return
  end
  if ib.status == im.InteractionResponse.Status.SUCCESS then
    lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, tostring(deleted_code_slot)))
    --make sure cota credential exists if the user deletes it or if space was created for the COTA cred
    if deleted_code_slot == device:get_field(lock_utils.COTA_CRED_INDEX) or
      device:get_field(lock_utils.NONFUNCTIONAL) then
      set_cota_credential(device, device:get_field(lock_utils.COTA_CRED_INDEX) or INITIAL_COTA_INDEX)
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
  local status = elements.status.value
  if status == DoorLock.types.DlStatus.SUCCESS then
    local event = capabilities.lockCodes.codeChanged("", {state_change = true})
    local cota_cred_index = device:get_field(lock_utils.COTA_CRED_INDEX)
    local code_name = (credential_index == cota_cred_index and lock_utils.COTA_CODE_NAME) or
      lock_utils.get_code_name(device, code_slot)
    event.data = {codeName = code_name}
    event.value = lock_utils.get_change_type(device, tostring(code_slot))
    local lock_codes = lock_utils.get_lock_codes(device)
    lock_codes[code_slot] = event.data.codeName
    device:emit_event(event)
    if credential_index == cota_cred_index then
      device:emit_event(
        capabilities.lockCodes.codeChanged(
          code_slot .. " renamed", {state_change = true}
        )
      )
    end
    lock_utils.lock_codes_event(device, lock_codes)
    lock_utils.reset_code_state(device, code_slot)
    if device:get_field(lock_utils.NONFUNCTIONAL) and cota_cred_index == credential_index then
      device.log.info("Successfully set COTA credential after being non-functional")
      device:set_field(lock_utils.NONFUNCTIONAL, false, {persist = true})
      local profile_name = "base-lock"
      device:set_field(PROFILE_BASE_NAME, profile_name, {persist = true})
      local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
      if #battery_feature_eps == 0 then
        profile_name = profile_name .. "-nobattery"
        device.log.info(string.format("Updating device profile to %s.", profile_name))
        device:try_update_metadata({profile = profile_name, provisioning_state = "PROVISIONED"})
      else
        local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
        req:merge(clusters.PowerSource.attributes.AttributeList:read())
        device:send(req)
      end
    end
  elseif device:get_field(lock_utils.COTA_CRED) and credential_index == device:get_field(lock_utils.COTA_CRED_INDEX) then
    -- Handle failure to set a COTA credential
    if status == DoorLock.types.DlStatus.OCCUPIED and elements.next_credential_index.value ~= nil then
      --This credential index is unavailable, but there is another available
      set_cota_credential(device, elements.next_credential_index.value)
    elseif status == DoorLock.types.DlStatus.OCCUPIED and
        elements.next_credential_index.value == nil and
        credential_index == INITIAL_COTA_INDEX then
      --There are no credential indices available on the device
      device.log.error("Device requires COTA credential, but has no credential indexes available!")
      device.log.error("Lock and Unlock commands will no longer work!!")
      device:set_field(PROFILE_BASE_NAME, "nonfunctional-lock", {persist = true})
      device:try_update_metadata({profile = "nonfunctional-lock", provisioning_state = "NONFUNCTIONAL"})
      device:set_field(lock_utils.NONFUNCTIONAL, true, {persist = true})
    elseif status == DoorLock.types.DlStatus.OCCUPIED and elements.next_credential_index.value == nil then
      --There are no credential indices available, but we must ensure we search all indices.
      set_cota_credential(device, INITIAL_COTA_INDEX)
    elseif status == DoorLock.types.DlStatus.DUPLICATE then
      --The credential we randomly generated already exists
      generate_cota_cred_for_device(device)
      --delay 0 needed for unit test verification of random value
      device.thread:call_with_delay(0, function(t) set_cota_credential(device, credential_index) end)
    elseif status == DoorLock.types.DlStatus.INVALID_FIELD then
      device.log.error("Invalid SetCredential command sent to set a COTA credential. This is a bug.")
    elseif elements.next_credential_index.value ~= nil then
      device.log.warn(string.format(
        "Received non-success SetCredentialResponse status (%s), but there is a next credential index available", elements.status
      ))
      set_cota_credential(device, elements.next_credential_index.value)
    end
  else
    device.log.error(
      string.format(
        "Failed to set user code for device, SetCredential status received: %s", elements.status
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
  local credential_exists = elements.credential_exists.value
  local next_credential_index = elements.next_credential_index and elements.next_credential_index.value or nil

  local event = capabilities.lockCodes.codeChanged("", {state_change = true})
  local code_slot = tostring(cred_index)
  local cota_cred_index = device:get_field(lock_utils.COTA_CRED_INDEX)
  local code_name = (cred_index == cota_cred_index and lock_utils.COTA_CODE_NAME) or lock_utils.get_code_name(device, code_slot)
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
      if cred_index == cota_cred_index then --make sure cota credential exists if it was deleted
        set_cota_credential(device, INITIAL_COTA_INDEX)
      end
    else
      -- Code is unset
      event.value = code_slot .. " unset"
      device:emit_event(event)
    end
  end
  device:set_field(lock_utils.CHECKING_CREDENTIAL, nil)

  local is_scanning = device:get_latest_state(
      "main", capabilities.lockCodes.ID, capabilities.lockCodes.scanCodes.NAME
    ) == "Scanning"
  if not is_scanning then
    return
  end
  if (next_credential_index == nil) then
    device:emit_event(
      capabilities.lockCodes.scanCodes(
        "Complete", {visibility = {displayed = false}}
      )
    )
    local lock_codes = lock_utils.get_lock_codes(device)
    lock_utils.lock_codes_event(device, lock_codes)
  elseif next_credential_index ~= nil then
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
  local cota_cred_index = device:get_field(lock_utils.COTA_CRED_INDEX)

  if data_type_changed == DoorLock.types.DlLockDataType.PIN then -- pin added or removed
    local code_slot = data_index and tostring(data_index) or nil
    if (operation_type == DoorLock.types.DlDataOperationType.ADD or operation_type
      == DoorLock.types.DlDataOperationType.MODIFY) and code_slot ~= nil then
      local change_type = lock_utils.get_change_type(device, code_slot)
      event.value = change_type
      local code_name = (data_index == cota_cred_index and lock_utils.COTA_CODE_NAME) or lock_utils.get_code_name(device, code_slot)
      event.data = {codeName = code_name}
      device:emit_event(event)
      if string.match(change_type, "%d+ set") ~= nil then
        local lock_codes = lock_utils.get_lock_codes(device)
        lock_codes[code_slot] = code_name
        lock_utils.lock_codes_event(device, lock_codes)
      end
    elseif operation_type == DoorLock.types.DlDataOperationType.CLEAR and code_slot ~= nil then
      lock_utils.lock_codes_event(device, lock_utils.code_deleted(device, tostring(code_slot)))
      --make sure cota credential is created if the user deletes it or a space is made for it
      if data_index == cota_cred_index or device:get_field(lock_utils.NONFUNCTIONAL) then
        set_cota_credential(device, cota_cred_index or INITIAL_COTA_INDEX)
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
      if device:get_field(lock_utils.COTA_CRED) ~= nil then set_cota_credential(device, INITIAL_COTA_INDEX) end
    else
      device.log.info("Not handling LockUserChange event")
    end
    -- Note when a Lock User is deleted, the credentials associated with that user are also deleted.
    -- Change events are created for each credential as well as the user.
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
  -- Note: no endpoint specified indicates a wildcard endpoint
  local req = DoorLock.attributes.LockState:read(device)
  req:merge(PowerSource.attributes.BatPercentRemaining:read(device))
  device:send(req)
end

local function handle_lock(driver, device, command)
  local ep = device:component_to_endpoint(command.component)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  if cota_cred then
    device:send(
      DoorLock.server.commands.LockDoor(device, ep, cota_cred)
    )
  else
    device:send(DoorLock.server.commands.LockDoor(device, ep))
  end
end

local function handle_unlock(driver, device, command)
  local ep = device:component_to_endpoint(command.component)
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  if cota_cred then
    device:send(
      DoorLock.server.commands.UnlockDoor(device, ep, cota_cred)
    )
  else
    device:send(DoorLock.server.commands.UnlockDoor(device, ep))
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
  if (device:get_field(lock_utils.CHECKING_CREDENTIAL) == nil) then
    lock_utils.lock_codes_event(device, {})
    device:set_field(lock_utils.CHECKING_CREDENTIAL, 1)
  else
    device.log.info(string.format("Delaying scanning since currently checking credential %d", device:get_field(lock_utils.CHECKING_CREDENTIAL)))
    device.thread:call_with_delay(2, function(t) handle_reload_all_codes(driver, device, command) end)
    return
  end
  device.thread:call_with_delay(5, function(t)
    device:emit_event(capabilities.lockCodes.scanCodes("Scanning"))
    device:send(
      clusters.DoorLock.server.commands.GetCredentialStatus(
        device, device:component_to_endpoint(command.component),
        {credential_type = DoorLock.types.DlCredentialType.PIN, credential_index = device:get_field(lock_utils.CHECKING_CREDENTIAL)}
      )
    )
  end)
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

local function info_changed(driver, device, event, args)
  if device.profile.id ~= args.old_st_store.profile.id then
    device:subscribe()
  end
end

local function do_configure(driver, device)
  -- check if the device is NOT currently profiled as base-lock
  -- by ANDing a query for every capability in the base-lock profiles.
  -- If it does not use base-lock, it is WWST and does not need re-profiling.
  if not (device:supports_capability(capabilities.lock) and
    device:supports_capability(capabilities.lockCodes) and
    device:supports_capability(capabilities.tamperAlert) and
    device:supports_capability(capabilities.battery)) then
    return
  end

  -- if not fingerprinted, dynamically configure base-lock profile
  local profile_name = "base-lock"
  device:set_field(PROFILE_BASE_NAME, profile_name, {persist = true})
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps == 0 then
    profile_name = profile_name .. "-nobattery"
    device.log.info(string.format("Updating device profile to %s.", profile_name))
    device:try_update_metadata({profile = profile_name})
  else
    local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
    req:merge(clusters.PowerSource.attributes.AttributeList:read())
    device:send(req)
  end
end

local function device_init(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  device:subscribe()

  -- check if we have a missing COTA credential. Only run this if it has not been run before (i.e. in device added),
  -- because there is a delay built into the COTA process and we do not want to start two COTA generations at the same time
  -- in the event this was triggered on add.
  if not device:get_field(lock_utils.COTA_READ_INITIALIZED) or not device:get_field(lock_utils.COTA_CRED) then
    local eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.DoorLockFeature.CREDENTIALSOTA | DoorLock.types.DoorLockFeature.PIN_CREDENTIALS})
    if #eps == 0 then
      device.log.debug("Device will not require PIN for remote operation")
      device:set_field(lock_utils.COTA_CRED, false, {persist = true})
    else
      device:send(DoorLock.attributes.RequirePINforRemoteOperation:read(device, eps[1]))
      device:set_field(lock_utils.COTA_READ_INITIALIZED, true, {persist = true})
    end
  end
end

local function device_added(driver, device)
  --Note: May want to write OperatingMode to NORMAL, to attempt to ensure remote operation works
  --Note: May want to write RequirePINForRemoteOperation, to avoid cota cases if possible.
  device:emit_event(capabilities.tamperAlert.tamper.clear())
  local eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.DoorLockFeature.PIN_CREDENTIALS})
  if #eps == 0 then
    if device:supports_capability_by_id(capabilities.tamperAlert.ID) then
      device.log.debug("Device does not support lockCodes. Switching profile.")
      local profile_name = "lock-without-codes"
      device:set_field(PROFILE_BASE_NAME, profile_name, {persist = true})
      local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
      if #battery_feature_eps == 0 then
        profile_name = profile_name .. "-nobattery"
      end
      device.log.info(string.format("Updating device profile to %s.", profile_name))
      device:try_update_metadata({profile = profile_name})
    else
      device.log.debug("Device supports neither lock codes nor tamper. Unable to switch profile.")
    end
  else
    local req = im.InteractionRequest(im.InteractionRequest.RequestType.READ, {})
    req:merge(DoorLock.attributes.MaxPINCodeLength:read(device, eps[1]))
    req:merge(DoorLock.attributes.MinPINCodeLength:read(device, eps[1]))
    req:merge(DoorLock.attributes.NumberOfPINUsersSupported:read(device, eps[1]))
    driver:inject_capability_command(device, {
      capability = capabilities.lockCodes.ID,
      command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
      args = {}
    })

    --Device may require pin for remote operation if it supports COTA and PIN features.
    eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.DoorLockFeature.CREDENTIALSOTA | DoorLock.types.DoorLockFeature.PIN_CREDENTIALS})
    if #eps == 0 then
      device.log.debug("Device will not require PIN for remote operation")
      device:set_field(lock_utils.COTA_CRED, false, {persist = true})
    else
      req:merge(DoorLock.attributes.RequirePINforRemoteOperation:read(device, eps[1]))
      device:set_field(lock_utils.COTA_READ_INITIALIZED, true, {persist = true})
    end
    device:send(req)
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
        [DoorLock.attributes.RequirePINforRemoteOperation.ID] = require_remote_pin_handler,
      },
      [PowerSource.ID] = {
        [PowerSource.attributes.AttributeList.ID] = handle_power_source_attribute_list,
        [PowerSource.attributes.BatPercentRemaining.ID] = handle_battery_percent_remaining,
        [PowerSource.attributes.BatChargeLevel.ID] = handle_battery_charge_level,
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
  subscribed_attributes = subscribed_attributes,
  subscribed_events = {
    [capabilities.tamperAlert.ID] = {DoorLock.events.DoorLockAlarm, DoorLock.events.LockOperation},
    [capabilities.lockAlarm.ID] = {DoorLock.events.DoorLockAlarm},
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
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.tamperAlert,
    capabilities.battery,
    capabilities.batteryLevel,
  },
  sub_drivers = {
    require("new-matter-lock"),
  },
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
  },
}

-----------------------------------------------------------------------------------------------------------------------------
-- Driver Initialization
-----------------------------------------------------------------------------------------------------------------------------
local matter_driver = MatterDriver("matter-lock", matter_lock_driver)
matter_driver:run()
