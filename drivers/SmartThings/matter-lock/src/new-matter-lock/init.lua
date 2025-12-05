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
local utils = require "st.utils"
local lock_utils = require "lock_utils"

local version = require "version"
if version.api < 10 then
  clusters.DoorLock = require "DoorLock"
end

local DoorLock = clusters.DoorLock
local PowerSource = clusters.PowerSource

local INITIAL_CREDENTIAL_INDEX = 1
local ALL_INDEX = 0xFFFE
local MIN_EPOCH_S = 0
local MAX_EPOCH_S = 0xffffffff
local THIRTY_YEARS_S = 946684800 -- 1970-01-01T00:00:00 ~ 2000-01-01T00:00:00

local MODULAR_PROFILE_UPDATED = "__MODULAR_PROFILE_UPDATED"

local RESPONSE_STATUS_MAP = {
  [DoorLock.types.DlStatus.SUCCESS] = "success",
  [DoorLock.types.DlStatus.FAILURE] = "failure",
  [DoorLock.types.DlStatus.DUPLICATE] = "duplicate",
  [DoorLock.types.DlStatus.OCCUPIED] = "occupied",
  [DoorLock.types.DlStatus.INVALID_FIELD] = "invalidCommand",
  [DoorLock.types.DlStatus.RESOURCE_EXHAUSTED] = "resourceExhausted",
  [DoorLock.types.DlStatus.NOT_FOUND] = "failure"
}

local WEEK_DAY_MAP = {
  ["Sunday"] = 1,
  ["Monday"] = 2,
  ["Tuesday"] = 4,
  ["Wednesday"] = 8,
  ["Thursday"] = 16,
  ["Friday"] = 32,
  ["Saturday"] = 64,
}

local ALIRO_KEY_TYPE_TO_CRED_ENUM_MAP = {
  ["evictableEndpointKey"] = DoorLock.types.CredentialTypeEnum.ALIRO_EVICTABLE_ENDPOINT_KEY,
  ["nonEvictableEndpointKey"] = DoorLock.types.CredentialTypeEnum.ALIRO_NON_EVICTABLE_ENDPOINT_KEY
}

local NEW_MATTER_LOCK_PRODUCTS = {
  {0x115f, 0x2802}, -- AQARA, U200
  {0x115f, 0x2801}, -- AQARA, U300
  {0x115f, 0x2807}, -- AQARA, U200 Lite
  {0x147F, 0x0001}, -- U-tec
  {0x147F, 0x0008}, -- Ultraloq, Bolt Smart Matter Door Lock
  {0x144F, 0x4002}, -- Yale, Linus Smart Lock L2
  {0x101D, 0x8110}, -- Yale, New Lock
  {0x1533, 0x0001}, -- eufy, E31
  {0x1533, 0x0002}, -- eufy, E30
  {0x1533, 0x0003}, -- eufy, C34
  {0x1533, 0x000F}, -- eufy, FamiLock S3 Max
  {0x1533, 0x0010}, -- eufy, FamiLock S3
  {0x1533, 0x0011}, -- eufy, FamiLock E34
  {0x1533, 0x0012}, -- eufy, FamiLock E35
  {0x135D, 0x00B1}, -- Nuki, Smart Lock Pro
  {0x135D, 0x00B2}, -- Nuki, Smart Lock
  {0x135D, 0x00C1}, -- Nuki, Smart Lock
  {0x135D, 0x00A1}, -- Nuki, Smart Lock
  {0x135D, 0x00B0}, -- Nuki, Smart Lock
  {0x15F2, 0x0001}, -- Viomi, AiSafety Smart Lock E100
  {0x158B, 0x0001}, -- Deasino, DS-MT01
  {0x10E1, 0x2002}, -- VDA
  {0x1421, 0x0042}, -- Kwikset Halo Select Plus
}

local battery_support = {
  NO_BATTERY = "NO_BATTERY",
  BATTERY_LEVEL = "BATTERY_LEVEL",
  BATTERY_PERCENTAGE = "BATTERY_PERCENTAGE"
}

local profiling_data = {
  BATTERY_SUPPORT = "__BATTERY_SUPPORT",
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
  },
  [capabilities.lockAliro.ID] = {
    DoorLock.attributes.AliroReaderVerificationKey,
    DoorLock.attributes.AliroReaderGroupIdentifier,
    DoorLock.attributes.AliroReaderGroupSubIdentifier,
    DoorLock.attributes.AliroExpeditedTransactionSupportedProtocolVersions,
    DoorLock.attributes.AliroGroupResolvingKey,
    DoorLock.attributes.AliroSupportedBLEUWBProtocolVersions,
    DoorLock.attributes.AliroBLEAdvertisingVersion,
    DoorLock.attributes.NumberOfAliroCredentialIssuerKeysSupported,
    DoorLock.attributes.NumberOfAliroEndpointKeysSupported,
  },
  [capabilities.battery.ID] = {
    PowerSource.attributes.BatPercentRemaining
  },
  [capabilities.batteryLevel.ID] = {
    PowerSource.attributes.BatChargeLevel
  }
}

local subscribed_events = {
  [capabilities.lock.ID] = {
    DoorLock.events.LockOperation
  },
  [capabilities.lockAlarm.ID] = {
    DoorLock.events.DoorLockAlarm
  },
  [capabilities.lockUsers.ID] = {
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
  device:set_component_to_endpoint_fn(component_to_endpoint)
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

local function device_added(driver, device)
  device:emit_event(capabilities.lockAlarm.alarm.clear({state_change = true}))
  local battery_feature_eps = device:get_endpoints(clusters.PowerSource.ID, {feature_bitmap = clusters.PowerSource.types.PowerSourceFeature.BATTERY})
  if #battery_feature_eps > 0 then
    device:send(clusters.PowerSource.attributes.AttributeList:read(device))
  else
    device:set_field(profiling_data.BATTERY_SUPPORT, battery_support.NO_BATTERY, { persist = true })
  end
end

local function match_profile_modular(driver, device)
  local enabled_optional_component_capability_pairs = {}
  local main_component_capabilities = {}
  local modular_profile_name = "lock-modular"
  for _, device_ep in pairs(device.endpoints) do
    for _, ep_cluster in pairs(device_ep.clusters) do
      if ep_cluster.cluster_id == DoorLock.ID then
        local clus_has_feature = function(feature_bitmap)
          return DoorLock.are_features_supported(feature_bitmap, ep_cluster.feature_map)
        end
        if clus_has_feature(DoorLock.types.Feature.USER) then
          table.insert(main_component_capabilities, capabilities.lockUsers.ID)
        end
        if clus_has_feature(DoorLock.types.Feature.PIN_CREDENTIAL) then
          table.insert(main_component_capabilities, capabilities.lockCredentials.ID)
        end
        if clus_has_feature(DoorLock.types.Feature.WEEK_DAY_ACCESS_SCHEDULES) or
          clus_has_feature(DoorLock.types.Feature.YEAR_DAY_ACCESS_SCHEDULES) then
          table.insert(main_component_capabilities, capabilities.lockSchedules.ID)
        end
        if clus_has_feature(DoorLock.types.Feature.UNBOLT) then
          device:emit_event(capabilities.lock.supportedLockValues({"locked", "unlocked", "unlatched", "not fully locked"}, {visibility = {displayed = false}}))
          device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
          modular_profile_name = "lock-modular-embedded-unlatch" -- use the embedded config specified in this profile for devices supporting "unlatch"
        else
          device:emit_event(capabilities.lock.supportedLockValues({"locked", "unlocked", "not fully locked"}, {visibility = {displayed = false}}))
          device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
        end
        if clus_has_feature(DoorLock.types.Feature.ALIRO_PROVISIONING) then
          table.insert(main_component_capabilities, capabilities.lockAliro.ID)
        end
        break
      end
    end
  end

  local supported_battery_type = device:get_field(profiling_data.BATTERY_SUPPORT)
  if supported_battery_type == battery_support.BATTERY_LEVEL then
    table.insert(main_component_capabilities, capabilities.batteryLevel.ID)
  elseif supported_battery_type == battery_support.BATTERY_PERCENTAGE then
    table.insert(main_component_capabilities, capabilities.battery.ID)
  end

  table.insert(enabled_optional_component_capability_pairs, {"main", main_component_capabilities})
  device:try_update_metadata({profile = modular_profile_name, optional_component_capabilities = enabled_optional_component_capability_pairs})
  device:set_field(MODULAR_PROFILE_UPDATED, true)
end

local function match_profile_switch(driver, device)
  local user_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.USER})
  local pin_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.PIN_CREDENTIAL})
  local week_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.WEEK_DAY_ACCESS_SCHEDULES})
  local year_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.YEAR_DAY_ACCESS_SCHEDULES})
  local unbolt_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.UNBOLT})

  local profile_name = "lock"
  if #user_eps > 0 then
    profile_name = profile_name .. "-user"
    if #pin_eps > 0 then
      profile_name = profile_name .. "-pin"
    end
    if #week_schedule_eps + #year_schedule_eps > 0 then
      profile_name = profile_name .. "-schedule"
    end
  end
  if #unbolt_eps > 0 then
    profile_name = profile_name .. "-unlatch"
    device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
  else
    device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
  end

  local supported_battery_type = device:get_field(profiling_data.BATTERY_SUPPORT)
  if supported_battery_type == battery_support.BATTERY_LEVEL then
    profile_name = profile_name .. "-batteryLevel"
  elseif supported_battery_type == battery_support.BATTERY_PERCENTAGE then
    profile_name = profile_name .. "-battery"
  end

  device.log.info_with({hub_logs=true}, string.format("Updating device profile to %s.", profile_name))
  device:try_update_metadata({profile = profile_name})
end

local function info_changed(driver, device, event, args)
  if device.profile.id == args.old_st_store.profile.id and not device:get_field(MODULAR_PROFILE_UPDATED) then
    return
  end
  device:set_field(MODULAR_PROFILE_UPDATED, nil)
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
  device:emit_event(capabilities.lockAlarm.alarm.clear({state_change = true}))
  device:emit_event(capabilities.lockAlarm.supportedAlarmValues({"unableToLockTheDoor"}, {visibility = {displayed = false}})) -- lockJammed is madatory
end

local function profiling_data_still_required(device)
  for _, field in pairs(profiling_data) do
    if device:get_field(field) == nil then
      return true -- data still required if a field is nil
    end
  end
  return false
end

local function match_profile(driver, device)
  if profiling_data_still_required(device) then return end

  if version.api >= 15 and version.rpc >= 9 then
    match_profile_modular(driver, device)
  else
    match_profile_switch(driver, device)
  end
end

local function do_configure(driver, device)
  match_profile(driver, device)
end

local function driver_switched(driver, device)
  match_profile(driver, device)
end

-- This function check busy_state and if busy_state is false, set it to true(current time)
local function is_busy_state_set(device)
  local c_time = os.time()
  local busy_state = device:get_field(lock_utils.BUSY_STATE) or false
  if busy_state == false or c_time - busy_state > 10 then
    device:set_field(lock_utils.BUSY_STATE, c_time, {persist = true})
    return false
  else
    return true
  end
end

-- Matter Handler
----------------
-- Lock State --
----------------
local function lock_state_handler(driver, device, ib, response)
  local LockState = DoorLock.attributes.LockState
  local attr = capabilities.lock.lock
  local LOCK_STATE = {
    [LockState.NOT_FULLY_LOCKED] = attr.not_fully_locked(),
    [LockState.LOCKED] = attr.locked(),
    [LockState.UNLOCKED] = attr.unlocked(),
    [LockState.UNLATCHED] = attr.unlatched()
  }

  -- The lock state is usually updated in lock_state_handler and lock_op_event_handler, respectively.
  -- In this case, two events occur. To prevent this, when both functions are called,
  -- it send the event after 1 second so that no event occurs in the lock_state_handler.
  device.thread:call_with_delay(1, function ()
    if ib.data.value ~= nil then
      device:emit_event(LOCK_STATE[ib.data.value])
    else
      device.log.warn("Lock State is nil")
    end
  end)
end

---------------------
-- Operating Modes --
---------------------
local function operating_modes_handler(driver, device, ib, response)
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
  local unbolt_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.UNBOLT})
  if result == true then
    device:emit_event(status("true", {visibility = {displayed = true}}))
    if #unbolt_eps > 0 then
      device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock", "unlatch"}, {visibility = {displayed = false}}))
    else
      device:emit_event(capabilities.lock.supportedLockCommands({"lock", "unlock"}, {visibility = {displayed = false}}))
    end
  elseif result == false then
    device:emit_event(status("false", {visibility = {displayed = true}}))
    device:emit_event(capabilities.lock.supportedLockCommands({}, {visibility = {displayed = false}}))
  end
end

-------------------------------------
-- Number Of Total Users Supported --
-------------------------------------
local function total_users_supported_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockUsers.totalUsersSupported(ib.data.value, {visibility = {displayed = false}}))
end

----------------------------------
-- Number Of PIN Users Supported --
----------------------------------
local function pin_users_supported_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockCredentials.pinUsersSupported(ib.data.value, {visibility = {displayed = false}}))
end

-------------------------
-- Min PIN Code Length --
-------------------------
local function min_pin_code_len_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockCredentials.minPinCodeLen(ib.data.value, {visibility = {displayed = false}}))
end

-------------------------
-- Max PIN Code Length --
-------------------------
local function max_pin_code_len_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockCredentials.maxPinCodeLen(ib.data.value, {visibility = {displayed = false}}))
end

--------------------------------------
-- Require PIN For Remote Operation --
--------------------------------------
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

  -- Check Busy State
  if is_busy_state_set(device) then
    device.log.debug("delaying setting COTA credential since a credential is currently being set")
    device.thread:call_with_delay(2, function(t)
      set_cota_credential(device, credential_index)
    end)
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, "addCota")
  device:set_field(lock_utils.CRED_INDEX, credential_index)
  device:set_field(lock_utils.COTA_CRED_INDEX, credential_index, {persist = true})
  device:set_field(lock_utils.USER_TYPE, "remote")

  -- Send command
  device.log.info(string.format("Attempting to set COTA credential at index %s", credential_index))
  local credential = {
    credential_type = DoorLock.types.CredentialTypeEnum.PIN,
    credential_index = credential_index
  }
  device:send(DoorLock.server.commands.SetCredential(
    device,
    #eps > 0 and eps[1] or 1,
    DoorLock.types.DataOperationTypeEnum.ADD,
    credential,
    device:get_field(lock_utils.COTA_CRED),
    nil, -- nil user_index creates a new user
    DoorLock.types.UserStatusEnum.OCCUPIED_ENABLED,
    DoorLock.types.UserTypeEnum.REMOTE_ONLY_USER
  ))
end

local function generate_cota_cred_for_device(device)
  local len = device:get_latest_state("main", capabilities.lockCredentials.ID, capabilities.lockCredentials.maxPinCodeLen.NAME) or 6
  local cred_data = math.floor(math.random() * (10 ^ len))
  cred_data = string.format("%0" .. tostring(len) .. "d", cred_data)
  device:set_field(lock_utils.COTA_CRED, cred_data, {persist = true})
end

local function apply_cota_credentials_if_absent(device)
  if not device:get_field(lock_utils.COTA_CRED) then
    -- Process after all other info blocks have been dispatched to ensure MaxPINCodeLength has been processed
    device.thread:call_with_delay(0, function(t)
      generate_cota_cred_for_device(device)
      -- delay needed to allow test to override the random credential data
      device.thread:call_with_delay(0, function(t)
        -- Attempt to set cota credential at the lowest index
        set_cota_credential(device, INITIAL_CREDENTIAL_INDEX)
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

-----------------------------------------------------
-- Number Of Week Day Schedules Supported Per User --
-----------------------------------------------------
local function max_week_schedule_of_user_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockSchedules.weekDaySchedulesPerUser(ib.data.value, {visibility = {displayed = false}}))
end

-----------------------------------------------------
-- Number Of Year Day Schedules Supported Per User --
-----------------------------------------------------
local function max_year_schedule_of_user_handler(driver, device, ib, response)
  device:emit_event(capabilities.lockSchedules.yearDaySchedulesPerUser(ib.data.value, {visibility = {displayed = false}}))
end

----------------
-- Aliro Util --
----------------
local function hex_string_to_octet_string(hex_string)
  if hex_string == nil then
    return nil
  end
  local octet_string = ""
  for i = 1, #hex_string, 2 do
      local hex = hex_string:sub(i, i + 1)
      octet_string = octet_string .. string.char(tonumber(hex, 16))
  end
  return octet_string
end

-----------------------------------
-- Aliro Reader Verification Key --
-----------------------------------
local function aliro_reader_verification_key_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.lockAliro.readerVerificationKey(
      utils.bytes_to_hex_string(ib.data.value), {visibility = {displayed = false}}
    ))
  end
end

-----------------------------------
-- Aliro Reader Group Identifier --
-----------------------------------
local function aliro_reader_group_id_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.lockAliro.readerGroupIdentifier(
      utils.bytes_to_hex_string(ib.data.value),
      {visibility = {displayed = false}}
    ))
  end
end

-------------------------------------------------------------
-- Aliro Expedited Transaction Supported Protocol Versions --
-------------------------------------------------------------
local function aliro_group_resolving_key_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.lockAliro.groupResolvingKey(
      utils.bytes_to_hex_string(ib.data.value),
      {visibility = {displayed = false}}
    ))
  end
end

-------------------------------
-- Aliro Group Resolving Key --
-------------------------------
local function aliro_protocol_versions_handler(driver, device, ib, response)
  if ib.data.elements == nil then
    return
  end
  local protocol_versions = {}
  for i, element in ipairs(ib.data.elements) do
    local version = string.format("%s.%s", element.value:byte(1), element.value:byte(2))
    table.insert(protocol_versions, version);
  end
  device:emit_event(capabilities.lockAliro.expeditedTransactionProtocolVersions(protocol_versions, {visibility = {displayed = false}}))
end

-----------------------------------------------
-- Aliro Supported BLE UWB Protocol Versions --
-----------------------------------------------
local function aliro_supported_ble_uwb_protocol_versions_handler(driver, device, ib, response)
  if ib.data.elements == nil then
    return
  end
  local protocol_versions = {}
  for i, element in ipairs(ib.data.elements) do
    local version = string.format("%s.%s", element.value:byte(1), element.value:byte(2))
    table.insert(protocol_versions, version);
  end
  device:emit_event(capabilities.lockAliro.bleUWBProtocolVersions(protocol_versions, {visibility = {displayed = false}}))
end

-----------------------------------
-- Aliro BLE Advertising Version --
-----------------------------------
local function aliro_ble_advertising_version_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.lockAliro.bleAdvertisingVersion(string.format("%s", ib.data.value), {visibility = {displayed = false}}))
  end
end

------------------------------------------------------
-- Number Of Aliro Credential Issuer Keys Supported --
------------------------------------------------------
local function max_aliro_credential_issuer_key_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.lockAliro.maxCredentialIssuerKeys(ib.data.value, {visibility = {displayed = false}}))
  end
end

---------------------------------------------
-- Number Of Aliro Endpoint Keys Supported --
---------------------------------------------
local function max_aliro_endpoint_key_handler(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.lockAliro.maxEndpointKeys(ib.data.value, {visibility = {displayed = false}}))
  end
end

---------------------------------
-- Power Source Attribute List --
---------------------------------
local function handle_power_source_attribute_list(driver, device, ib, response)
  for _, attr in ipairs(ib.data.elements) do
    -- mark if the device if BatPercentRemaining (Attribute ID 0x0C) or
    -- BatChargeLevel (Attribute ID 0x0E) is present and try profiling.
    if attr.value == 0x0C then
      device:set_field(profiling_data.BATTERY_SUPPORT, battery_support.BATTERY_PERCENTAGE, { persist = true })
      match_profile(driver, device)
      return
    elseif attr.value == 0x0E then
      device:set_field(profiling_data.BATTERY_SUPPORT, battery_support.BATTERY_LEVEL, { persist = true })
      match_profile(driver, device)
      return
    end
  end

  -- neither BatChargeLevel nor BatPercentRemaining were found. Re-profiling without battery.
  device:set_field(profiling_data.BATTERY_SUPPORT, battery_support.NO_BATTERY, { persist = true })
  match_profile(driver, device)
end

-------------------------------
-- Battery Percent Remaining --
-------------------------------
local function handle_battery_percent_remaining(driver, device, ib, response)
  if ib.data.value ~= nil then
    device:emit_event(capabilities.battery.battery(math.floor(ib.data.value / 2.0 + 0.5)))
  end
end

--------------------------
-- Battery Charge Level --
--------------------------
local function handle_battery_charge_level(driver, device, ib, response)
  if ib.data.value == PowerSource.types.BatChargeLevelEnum.OK then
    device:emit_event(capabilities.batteryLevel.battery.normal())
  elseif ib.data.value == PowerSource.types.BatChargeLevelEnum.WARNING then
    device:emit_event(capabilities.batteryLevel.battery.warning())
  elseif ib.data.value == PowerSource.types.BatChargeLevelEnum.CRITICAL then
    device:emit_event(capabilities.batteryLevel.battery.critical())
  end
end

-- Capability Handler
-----------------
-- Lock/Unlock --
-----------------
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
  local unbolt_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.UNBOLT})
  local cota_cred = device:get_field(lock_utils.COTA_CRED)
  local ep = device:component_to_endpoint(command.component)

  if #unbolt_eps > 0 then
    if cota_cred then
      device:send(
        DoorLock.server.commands.UnboltDoor(device, ep, cota_cred)
      )
    else
      device:send(DoorLock.server.commands.UnboltDoor(device, ep))
    end
  else
    if cota_cred then
      device:send(
        DoorLock.server.commands.UnlockDoor(device, ep, cota_cred)
      )
    else
      device:send(DoorLock.server.commands.UnlockDoor(device, ep))
    end
  end
end

local function handle_unlatch(driver, device, command)
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

----------------
-- User Table --
----------------
local function add_user_to_table(device, userIdx, userName, userType)
  -- Get latest user table
  local user_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.users.NAME,
    {}
  ))

  -- Add new entry to table
  table.insert(user_table, {userIndex = userIdx, userName = userName, userType = userType})
  device:emit_event(capabilities.lockUsers.users(user_table, {visibility = {displayed = false}}))
end

local function update_user_in_table(device, userIdx, userName, userType)
  -- Get latest user table
  local user_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.users.NAME,
    {}
  ))

  -- Find user entry
  local i = 0
  for index, entry in pairs(user_table) do
    if entry.userIndex == userIdx then
      i = index
      break
    end
  end

  -- Update user entry
  if i ~= 0 then
    user_table[i].userType = userType
    user_table[i].userName = userName
    device:emit_event(capabilities.lockUsers.users(user_table, {visibility = {displayed = false}}))
  end
end

local function delete_user_from_table(device, userIdx)
  -- If User Index is ALL_INDEX, remove all entry from the table
  if userIdx == ALL_INDEX then
    device:emit_event(capabilities.lockUsers.users({}, {visibility = {displayed = false}}))
    return
  end

  -- Get latest user table
  local user_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.users.NAME,
    {}
  ))

  -- Remove element from user table
  for index, entry in pairs(user_table) do
    if entry.userIndex == userIdx then
      table.remove(user_table, index)
      break
    end
  end
  device:emit_event(capabilities.lockUsers.users(user_table, {visibility = {displayed = false}}))
end

----------------------
-- Credential Table --
----------------------
local function has_credentials(device, userIdx)
  -- Get latest credential table
  local cred_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME,
    {}
  ))

  -- Find credential
  for index, entry in pairs(cred_table) do
    if entry.userIndex == userIdx then
      return true
    end
  end

  -- Get latest Aliro credential table
  local aliro_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockAliro.ID,
    capabilities.lockAliro.credentials.NAME,
    {}
  ))

  -- Find Aliro credential
  for index, entry in pairs(aliro_table) do
    if entry.userIndex == userIdx then
      return true
    end
  end

  return false
end

local function add_credential_to_table(device, userIdx, credIdx, credType)
  -- Get latest credential table
  local cred_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME,
    {}
  ))

  -- Add new entry to table
  table.insert(cred_table, {userIndex = userIdx, credentialIndex = credIdx, credentialType = credType})
  device:emit_event(capabilities.lockCredentials.credentials(cred_table, {visibility = {displayed = false}}))
end

local function delete_credential_from_table(device, credIdx)
  -- If Credential Index is ALL_INDEX, remove all entries from the table
  if credIdx == ALL_INDEX then
    device:emit_event(capabilities.lockCredentials.credentials({}, {visibility = {displayed = false}}))
    return ALL_INDEX
  end

  -- Get latest credential table
  local cred_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME,
    {}
  ))

  -- Delete an entry from credential table
  local userIdx = nil
  for index, entry in pairs(cred_table) do
    if entry.credentialIndex == credIdx then
      table.remove(cred_table, index)
      userIdx = entry.userIndex
      break
    end
  end

  device:emit_event(capabilities.lockCredentials.credentials(cred_table, {visibility = {displayed = false}}))
  return userIdx
end

local function delete_credential_from_table_as_user(device, userIdx)
  -- If User Index is ALL_INDEX, remove all entry from the table
  if userIdx == ALL_INDEX then
    device:emit_event(capabilities.lockCredentials.credentials({}, {visibility = {displayed = false}}))
    return
  end

  -- Get latest credential table
  local cred_table = device:get_latest_state(
    "main",
    capabilities.lockCredentials.ID,
    capabilities.lockCredentials.credentials.NAME
  ) or {}
  local new_cred_table = {}

  -- Re-create credential table
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
local function add_week_schedule_to_table(device, userIdx, scheduleIdx, schedule)
  -- Get latest week day schedule table
  local week_schedule_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.weekDaySchedules.NAME,
    {}
  ))

  -- Find schedule for specific user
  local i = 0
  for index, entry in pairs(week_schedule_table) do
    if entry.userIndex == userIdx then
      i = index
    end
  end

  -- Re-create weekDays list
  local weekDayList = {}
  for _, weekday in ipairs(schedule.weekDays) do
    table.insert(weekDayList, weekday)
  end

  if i ~= 0 then -- Add schedule for existing user
    -- Exclude same scheduleIdx
    local new_schedule_table = {}
    for index, entry in pairs(week_schedule_table[i].schedules) do
      if entry.scheduleIndex ~= scheduleIdx then
        table.insert(new_schedule_table, entry)
      end
    end
    -- Add new entry to table
    table.insert(
      new_schedule_table,
      {
        scheduleIndex = scheduleIdx,
        weekDays = weekDayList,
        startHour = schedule.startHour,
        startMinute = schedule.startMinute,
        endHour = schedule.endHour,
        endMinute = schedule.endMinute
      }
    )
    -- Update schedule for specific user
    week_schedule_table[i].schedules = new_schedule_table
  else -- Add schedule for new user
    table.insert(
      week_schedule_table,
      {
        userIndex = userIdx,
        schedules = {{
          scheduleIndex = scheduleIdx,
          weekDays = weekDayList,
          startHour = schedule.startHour,
          startMinute = schedule.startMinute,
          endHour = schedule.endHour,
          endMinute = schedule.endMinute
        }}
      }
    )
  end

  device:emit_event(capabilities.lockSchedules.weekDaySchedules(week_schedule_table, {visibility = {displayed = false}}))
end

local function delete_week_schedule_from_table(device, userIdx, scheduleIdx)
  -- Get latest week day schedule table
  local week_schedule_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.weekDaySchedules.NAME,
    {}
  ))

  -- Find schedule for specific user
  local i = 0
  for index, entry in pairs(week_schedule_table) do
    if entry.userIndex == userIdx then
      i = index
    end
  end

  -- When there is no userIndex in the table
  if i == 0 then
    return
  end

  -- Re-create schedule table for the user
  local new_schedule_table = {}
  for index, entry in pairs(week_schedule_table[i].schedules) do
    if entry.scheduleIndex ~= scheduleIdx then
      table.insert(new_schedule_table, entry)
    end
  end

  -- If user has no schedule, remove user from the table
  if #new_schedule_table == 0 then
    table.remove(week_schedule_table, i)
  else
    week_schedule_table[i].schedules = new_schedule_table
  end

  device:emit_event(capabilities.lockSchedules.weekDaySchedules(week_schedule_table, {visibility = {displayed = false}}))
end

local function delete_week_schedule_from_table_as_user(device, userIdx)
  -- If User Index is ALL_INDEX, remove all entry from the table
  if userIdx == ALL_INDEX then
    device:emit_event(capabilities.lockSchedules.weekDaySchedules({}, {visibility = {displayed = false}}))
    return
  end

  -- Get latest week day schedule table
  local week_schedule_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.weekDaySchedules.NAME,
    {}
  ))

  -- Re-create week day schedule table
  local new_week_schedule_table = {}
  for index, entry in pairs(week_schedule_table) do
    if entry.userIndex ~= userIdx then
      table.insert(new_week_schedule_table, entry)
    end
  end

  device:emit_event(capabilities.lockSchedules.weekDaySchedules(new_week_schedule_table, {visibility = {displayed = false}}))
end

-----------------------------
-- Year Day Schedule Table --
-----------------------------
local function add_year_schedule_to_table(device, userIdx, scheduleIdx, sTime, eTime)
  -- Get latest year day schedule table
  local year_schedule_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.yearDaySchedules.NAME,
    {}
  ))

  -- Find schedule for specific user
  local i = 0
  for index, entry in pairs(year_schedule_table) do
    if entry.userIndex == userIdx then
      i = index
    end
  end

  if i ~= 0 then -- Add schedule for existing user
    -- Exclude same scheduleIdx
    local new_schedule_table = {}
    for index, entry in pairs(year_schedule_table[i].schedules) do
      if entry.scheduleIndex ~= scheduleIdx then
        table.insert(new_schedule_table, entry)
      end
    end
    -- Add new entry to table
    table.insert(
      new_schedule_table,
      {
        scheduleIndex = scheduleIdx,
        localStartTime = sTime,
        localEndTime = eTime
      }
    )
    -- Update schedule for specific user
    year_schedule_table[i].schedules = new_schedule_table
  else -- Add schedule for new user
    table.insert(
      year_schedule_table,
      {
        userIndex = userIdx,
        schedules = {{
          scheduleIndex = scheduleIdx,
          localStartTime = sTime,
          localEndTime = eTime
        }}
      }
    )
  end

  device:emit_event(capabilities.lockSchedules.yearDaySchedules(year_schedule_table, {visibility = {displayed = false}}))
end

local function delete_year_schedule_from_table(device, userIdx, scheduleIdx)
  -- Get latest year day schedule table
  local year_schedule_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.yearDaySchedules.NAME,
    {}
  ))

  -- Find schedule for specific user
  local i = 0
  for index, entry in pairs(year_schedule_table) do
    if entry.userIndex == userIdx then
      i = index
    end
  end

  -- When there is no userIndex in the table
  if i == 0 then
    return
  end

  -- Re-create year day schedule table for the user
  local new_schedule_table = {}
  for index, entry in pairs(year_schedule_table[i].schedules) do
    if entry.scheduleIndex ~= scheduleIdx then
      table.insert(new_schedule_table, entry)
    end
  end

  -- If user has no schedule, remove user from the table
  if #new_schedule_table == 0 then
    table.remove(year_schedule_table, i)
  else
    year_schedule_table[i].schedules = new_schedule_table
  end

  device:emit_event(capabilities.lockSchedules.yearDaySchedules(year_schedule_table, {visibility = {displayed = false}}))
end

local function delete_year_schedule_from_table_as_user(device, userIdx)
  -- If User Index is ALL_INDEX, remove all entry from the table
  if userIdx == ALL_INDEX then
    device:emit_event(capabilities.lockSchedules.yearDaySchedules({}, {visibility = {displayed = false}}))
    return
  end

  -- Get latest year day schedule table
  local year_schedule_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockSchedules.ID,
    capabilities.lockSchedules.yearDaySchedules.NAME,
    {}
  ))

  -- Re-create year day schedule table
  local new_year_schedule_table = {}
  for index, entry in pairs(year_schedule_table) do
    if entry.userIndex ~= userIdx then
      table.insert(new_year_schedule_table, entry)
    end
  end

  device:emit_event(capabilities.lockSchedules.yearDaySchedules(new_year_schedule_table, {visibility = {displayed = false}}))
end

----------------------------
-- Aliro Credential Table --
----------------------------
local function add_aliro_to_table(device, userIdx, keyIdx, keyType, keyId)
  -- Get latest aliro table
  local aliro_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockAliro.ID,
    capabilities.lockAliro.credentials.NAME,
    {}
  ))

  -- Add new entry to table
  table.insert(aliro_table, {userIndex = userIdx, keyIndex = keyIdx, keyType = keyType, keyId = keyId})
  device:emit_event(capabilities.lockAliro.credentials(aliro_table, {visibility = {displayed = false}}))
end

local function delete_aliro_from_table(device, userIdx, keyType, keyId)
  -- Get latest aliro table
  local aliro_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockAliro.ID,
    capabilities.lockAliro.credentials.NAME,
    {}
  ))

  -- Delete an entry from aliro table
  if keyType == "issuerKey" then
    for i, entry in pairs(aliro_table) do
      if entry.userIndex == userIdx then
        table.remove(aliro_table, i)
        break
      end
    end
  else
    for i, entry in pairs(aliro_table) do
      if entry.userIndex == userIdx and entry.keyId == keyId then
        table.remove(aliro_table, i)
        break
      end
    end
  end
  device:emit_event(capabilities.lockAliro.credentials(aliro_table, {visibility = {displayed = false}}))
end

local function delete_aliro_from_table_as_user(device, userIdx)
  -- If User Index is ALL_INDEX, remove all entry from the table
  if userIdx == ALL_INDEX then
    device:emit_event(capabilities.lockAliro.credentials({}, {visibility = {displayed = false}}))
    return
  end

  -- Get latest credential table
  local aliro_table = device:get_latest_state(
    "main",
    capabilities.lockAliro.ID,
    capabilities.lockAliro.credentials.NAME
  ) or {}
  local new_aliro_table = {}

  -- Re-create credential table
  for index, entry in pairs(aliro_table) do
    if entry.userIndex ~= userIdx then
      table.insert(new_aliro_table, entry)
    end
  end

  device:emit_event(capabilities.lockAliro.credentials(new_aliro_table, {visibility = {displayed = false}}))
end

--------------
-- Add User --
--------------
local function handle_add_user(driver, device, command)
  -- Get parameters
  local cmdName = "addUser"
  local userName = command.args.userName
  local userType = command.args.userType

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockUsers.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, INITIAL_CREDENTIAL_INDEX, {persist = true})
  device:set_field(lock_utils.USER_NAME, userName, {persist = true})
  device:set_field(lock_utils.USER_TYPE, userType, {persist = true})

  -- Get available user index
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.GetUser(device, ep, INITIAL_CREDENTIAL_INDEX))
end

-----------------
-- Update User --
-----------------
local function handle_update_user(driver, device, command)
  -- Get parameters
  local cmdName = "updateUser"
  local userIdx = command.args.userIndex
  local userName = command.args.userName
  local userType = command.args.userType
  local userTypeMatter = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  if userType == "guest" then
    userTypeMatter = DoorLock.types.UserTypeEnum.SCHEDULE_RESTRICTED_USER
  end

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockUsers.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.USER_NAME, userName, {persist = true})
  device:set_field(lock_utils.USER_TYPE, userType, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetUser(
      device, ep,
      DoorLock.types.DataOperationTypeEnum.MODIFY, -- Operation Type: Add(0), Modify(2)
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
-- Get User Response --
-----------------------
local function get_user_response_handler(driver, device, ib, response)
  local elements = ib.info_block.data.elements
  local userIdx = elements.user_index.value
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end
  if status ~= "success" then
    -- Update commandResult
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      statusCode = status
    }
    device:emit_event(capabilities.lockUsers.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  end

  local ep = find_default_endpoint(device, DoorLock.ID)
  local status = elements.user_status.value
  local maxUser = device:get_latest_state(
    "main",
    capabilities.lockUsers.ID,
    capabilities.lockUsers.totalUsersSupported.NAME
  ) or 10

  -- Found available user index
  if status == nil or status == DoorLock.types.UserStatusEnum.AVAILABLE then
    local userName = device:get_field(lock_utils.USER_NAME)
    local userType = device:get_field(lock_utils.USER_TYPE)
    local userTypeMatter = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
    if userType == "guest" then
      userTypeMatter = DoorLock.types.UserTypeEnum.SCHEDULE_RESTRICTED_USER
    end

    -- Save values to field
    device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})

    -- Send command
    device:send(
      DoorLock.server.commands.SetUser(
        device, ep,
        DoorLock.types.DataOperationTypeEnum.ADD, -- Operation Type: Add(0), Modify(2)
        userIdx,          -- User Index
        userName,         -- User Name
        nil,              -- Unique ID
        nil,              -- User Status
        userTypeMatter,   -- User Type
        nil               -- Credential Rule
      )
    )
  elseif userIdx >= maxUser then -- There's no available user index
    -- Update commandResult
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      statusCode = "resourceExhausted"
    }
    device:emit_event(capabilities.lockUsers.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  else -- Check next user index
    device:send(DoorLock.server.commands.GetUser(device, ep, userIdx + 1))
  end
end

-----------------------
-- Set User Response --
-----------------------
local function set_user_response_handler(driver, device, ib, response)
  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local userName = device:get_field(lock_utils.USER_NAME)
  local userType = device:get_field(lock_utils.USER_TYPE)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.OCCUPIED then
    status = "occupied"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end

  -- Update User in table
  if status == "success" then
    if cmdName == "addUser" then
      add_user_to_table(device, userIdx, userName, userType)
    elseif cmdName == "updateUser" then
      update_user_in_table(device, userIdx, userName, userType)
    end
  else
    device.log.warn(string.format("Failed to set user: %s", status))
  end

  -- Update commandResult
  local command_result_info = {
    commandName = cmdName,
    userIndex = userIdx,
    statusCode = status
  }
  device:emit_event(capabilities.lockUsers.commandResult(
    command_result_info, {state_change = true, visibility = {displayed = false}}
  ))
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

-----------------
-- Delete User --
-----------------
local function handle_delete_user(driver, device, command)
  -- Get parameters
  local cmdName = "deleteUser"
  local userIdx = command.args.userIndex

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockUsers.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearUser(device, ep, userIdx))
end

----------------------
-- Delete All Users --
----------------------
local function handle_delete_all_users(driver, device, command)
  -- Get parameters
  local cmdName = "deleteAllUsers"

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockUsers.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, ALL_INDEX, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearUser(device, ep, ALL_INDEX))
end

-------------------------
-- Clear User Response --
-------------------------
local function clear_user_response_handler(driver, device, ib, response)
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
    delete_aliro_from_table_as_user(device, userIdx)
    delete_week_schedule_from_table_as_user(device, userIdx)
    delete_year_schedule_from_table_as_user(device, userIdx)
  else
    device.log.warn(string.format("Failed to clear user: %s", status))
  end

  -- Update commandResult
  local command_result_info = {
    commandName = cmdName,
    userIndex = userIdx,
    statusCode = status
  }
  device:emit_event(capabilities.lockUsers.commandResult(
    command_result_info, {state_change = true, visibility = {displayed = false}}
  ))
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

--------------------
-- Add Credential --
--------------------
local function handle_add_credential(driver, device, command)
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
    credential_index = INITIAL_CREDENTIAL_INDEX
  }
  local credData = command.args.credentialData

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.USER_TYPE, userType, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, INITIAL_CREDENTIAL_INDEX, {persist = true})
  device:set_field(lock_utils.CRED_DATA, credData, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetCredential(
      device, ep,
      DoorLock.types.DataOperationTypeEnum.ADD, -- Data Operation Type: Add(0), Modify(2)
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
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, credIdx, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetCredential(
      device, ep,
      DoorLock.types.DataOperationTypeEnum.MODIFY, -- Data Operation Type: Add(0), Modify(2)
      credential,  -- Credential
      credData,    -- Credential Data
      userIdx,     -- User Index
      nil,         -- User Status
      nil          -- User Type
    )
  )
end

---------------------------------
-- Set Pin Credential Response --
---------------------------------
local function set_pin_response_handler(driver, device, ib, response)
  if ib.status ~= im.InteractionResponse.Status.SUCCESS then
    device.log.error("Failed to set credential for device")
    return
  end

  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local credData = device:get_field(lock_utils.CRED_DATA)
  if cmdName == "addCota" then
    credData = device:get_field(lock_utils.COTA_CRED)
  end
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local userType = device:get_field(lock_utils.USER_TYPE)
  local credIdx = device:get_field(lock_utils.CRED_INDEX)
  local elements = ib.info_block.data.elements
  local status = RESPONSE_STATUS_MAP[elements.status.value]

  if status == "success" then
    -- Don't save user and credential for COTA
    if cmdName == "addCota" then
      device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
      return
    end

    -- If user is added also, update User table
    if userIdx == nil then
      add_user_to_table(device, elements.user_index.value, nil, userType)
    end

    -- Update Credential table
    userIdx = elements.user_index.value
    if cmdName == "addCredential" then
      add_credential_to_table(device, userIdx, credIdx, "pin")
    end

    -- Update commandResult
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      credentialIndex = credIdx,
      statusCode = status
    }
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))

    -- If User Type is Guest and device support schedule, add default schedule
    local week_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.WEEK_DAY_ACCESS_SCHEDULES})
    local year_schedule_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.YEAR_DAY_ACCESS_SCHEDULES})
    if userType == "guest" and (#week_schedule_eps > 0 or #year_schedule_eps > 0) then
      local cmdName = "defaultSchedule"
      local scheduleIdx = 1

      -- Save values to field
      device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
      device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
      device:set_field(lock_utils.SCHEDULE_INDEX, scheduleIdx, {persist = true})

      local ep = device:component_to_endpoint("main")
      device:send(
        DoorLock.server.commands.SetYearDaySchedule(
          device, ep,
          scheduleIdx,
          userIdx,
          MIN_EPOCH_S,
          MAX_EPOCH_S
        )
      )
    else
      device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
    end
    return
  end

  -- In the case DlStatus returns Occupied, this means the current credential index is in use,
  -- so we must try the next one. If there is not a next index (i.e. it is nil),
  -- we should mark this as "resourceExhausted" and stop attempting to set the credentials.
  device.log.warn(string.format("Failed to set credential: %s", status))
  if status == "occupied" and elements.next_credential_index.value == nil then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "resourceExhausted" -- No more available credential index
    }
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  elseif status == "occupied" then
    -- Get parameters
    local credIdx = elements.next_credential_index.value
    local credential = {
      credential_type = DoorLock.types.CredentialTypeEnum.PIN,
      credential_index = credIdx,
    }
    local userIdx = device:get_field(lock_utils.USER_INDEX)
    local userType = device:get_field(lock_utils.USER_TYPE)
    local userTypeMatter = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
    if userIdx ~= nil then
      userTypeMatter = nil
    elseif userType == "guest" then
      userTypeMatter = DoorLock.types.UserTypeEnum.SCHEDULE_RESTRICTED_USER
    elseif userType == "remote" then
      userTypeMatter = DoorLock.types.UserTypeEnum.REMOTE_ONLY_USER
    end

    device:set_field(lock_utils.CRED_INDEX, credIdx, {persist = true})

    -- Send command
    local ep = find_default_endpoint(device, DoorLock.ID)
    device:send(
      DoorLock.server.commands.SetCredential(
        device, ep,
        DoorLock.types.DataOperationTypeEnum.ADD, -- Data Operation Type: Add(0), Modify(2)
        credential,    -- Credential
        credData,      -- Credential Data
        userIdx,       -- User Index
        nil,           -- User Status
        userTypeMatter -- User Type
      )
    )
  elseif status == "duplicate" and cmdName == "addCota" then
    generate_cota_cred_for_device(device)
    device.thread:call_with_delay(0, function(t) set_cota_credential(device, credIdx) end)
  else
    local command_result_info = {
      commandName = cmdName,
      statusCode = status
    }
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  end
end

-----------------------------------
-- Set Aliro Credential Response --
-----------------------------------
local function set_issuer_key_response_handler(driver, device, ib, response)
  local cmdName = "setIssuerKey"
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local userType = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  local issuerKeyIndex = device:get_field(lock_utils.ISSUER_KEY_INDEX)
  local reqId = device:get_field(lock_utils.COMMAND_REQUEST_ID)
  local elements = ib.info_block.data.elements
  local status = RESPONSE_STATUS_MAP[elements.status.value]

  if status == "success" then
    -- Delete field data
    device:set_field(lock_utils.ISSUER_KEY, nil, {persist = true})

    -- If user is added also, update User table
    if userIdx == nil then
      userIdx = elements.user_index.value
      add_user_to_table(device, userIdx, nil, "adminMember")
    end

    -- Update Aliro table
    add_aliro_to_table(device, userIdx, issuerKeyIndex, "issuerKey", nil)

    -- Update commandResult
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      requestId = reqId,
      statusCode = status
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
    return
  end

  -- In the case DlStatus returns Occupied, this means the current credential index is in use,
  -- so we must try the next one. If there is not a next index (i.e. it is nil),
  -- we should mark this as "resourceExhausted" and stop attempting to set the credentials.
  device.log.warn(string.format("Failed to set credential: %s", status))
  if status == "occupied" and elements.next_credential_index.value == nil then
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      requestId = reqId,
      statusCode = "resourceExhausted" -- No more available credential index
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  elseif status == "occupied" then
    -- Get parameters
    if userIdx ~= nil then
      userType = nil
    end
    local credIdx = elements.next_credential_index.value
    local credType = DoorLock.types.CredentialTypeEnum.ALIRO_CREDENTIAL_ISSUER_KEY
    local credData = device:get_field(lock_utils.ISSUER_KEY)
    local credential = {
      credential_type = credType,
      credential_index = credIdx
    }

    -- Save values to field
    device:set_field(lock_utils.ISSUER_KEY_INDEX, credIdx, {persist = true})

    -- Send command
    local ep = find_default_endpoint(device, DoorLock.ID)
    device:send(
      DoorLock.server.commands.SetCredential(
        device, ep,
        DoorLock.types.DataOperationTypeEnum.ADD,
        credential, -- Credential
        hex_string_to_octet_string(credData), -- Credential Data
        userIdx, -- User Index
        nil,     -- User Status
        userType -- User Type
      )
    )
  else
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      requestId = reqId,
      statusCode = status
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  end
end

local function set_endpoint_key_response_handler(driver, device, ib, response)
  local cmdName = "setEndpointKey"
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local userType = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  local keyId = device:get_field(lock_utils.DEVICE_KEY_ID)
  local keyType = device:get_field(lock_utils.ENDPOINT_KEY_TYPE)
  local endpointKeyIndex = device:get_field(lock_utils.ENDPOINT_KEY_INDEX)
  local reqId = device:get_field(lock_utils.COMMAND_REQUEST_ID)
  local elements = ib.info_block.data.elements
  local status = RESPONSE_STATUS_MAP[elements.status.value]

  if status == "success" then
    -- Delete field data
    device:set_field(lock_utils.ENDPOINT_KEY, nil, {persist = true})

    -- If user is added also, update User table
    if userIdx == nil then
      userIdx = elements.user_index.value
      add_user_to_table(device, userIdx, nil, "adminMember")
    end

    -- Update Aliro table
    add_aliro_to_table(device, userIdx, endpointKeyIndex, keyType, keyId)

    -- Update commandResult
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      keyId = keyId,
      requestId = reqId,
      statusCode = status
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
    return
  end

  -- In the case DlStatus returns Occupied, this means the current credential index is in use,
  -- so we must try the next one. If there is not a next index (i.e. it is nil),
  -- we should mark this as "resourceExhausted" and stop attempting to set the credentials.
  device.log.warn(string.format("Failed to set credential: %s", status))

  if status == "occupied" and elements.next_credential_index.value == nil then
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      keyId = keyId,
      requestId = reqId,
      statusCode = "resourceExhausted" -- No more available credential index
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  elseif status == "occupied" then
    -- Get parameters
    if userIdx ~= nil then
      userType = nil
    end
    local credIdx = elements.next_credential_index.value
    local credType = ALIRO_KEY_TYPE_TO_CRED_ENUM_MAP[keyType]
    local credData = device:get_field(lock_utils.ENDPOINT_KEY)
    local credential = {
      credential_type = credType,
      credential_index = credIdx
    }

    -- Save values to field
    device:set_field(lock_utils.ENDPOINT_KEY_INDEX, credIdx, {persist = true})

    -- Send command
    local ep = find_default_endpoint(device, DoorLock.ID)
    device:send(
      DoorLock.server.commands.SetCredential(
        device, ep,
        DoorLock.types.DataOperationTypeEnum.ADD,
        credential, -- Credential
        hex_string_to_octet_string(credData), -- Credential Data
        userIdx, -- User Index
        nil,     -- User Status
        userType -- User Type
      )
    )
  else
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      keyId = keyId,
      requestId = reqId,
      statusCode = status
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
  end
end

local function set_credential_response_handler(driver, device, ib, response)
  if ib.status ~= im.InteractionResponse.Status.SUCCESS then
    device.log.error("Failed to set credential for device")
    return
  end
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  if cmdName == "addCredential" or cmdName == "updateCredential" or cmdName == "addCota" then
    set_pin_response_handler(driver, device, ib, response)
  elseif cmdName == "setIssuerKey" then
    set_issuer_key_response_handler(driver, device, ib, response)
  elseif cmdName == "setEndpointKey" then
    set_endpoint_key_response_handler(driver, device, ib, response)
  end
end

-----------------------
-- Delete Credential --
-----------------------
local function handle_delete_credential(driver, device, command)
  -- Get parameters
  local cmdName = "deleteCredential"
  local credIdx = command.args.credentialIndex
  local credential = {
    credential_type = DoorLock.types.CredentialTypeEnum.PIN,
    credential_index = credIdx,
  }

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, credIdx, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearCredential(device, ep, credential))
end

----------------------------
-- Delete All Credentials --
----------------------------
local function handle_delete_all_credentials(driver, device, command)
  -- Get parameters
  local cmdName = "deleteAllCredentials"
  local credential = {
    credential_type = DoorLock.types.CredentialTypeEnum.PIN,
    credential_index = ALL_INDEX,
  }

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.CRED_INDEX, ALL_INDEX, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearCredential(device, ep, credential))
end

-------------------------------
-- Clear Credential Response --
-------------------------------
local function clear_credential_response_handler(driver, device, ib, response)
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  if cmdName ~= "deleteCredential" and cmdName ~= "clearEndpointKey" and
  cmdName ~= "clearIssuerKey" and cmdName ~= "deleteAllCredentials" then
    return
  end
  local status = RESPONSE_STATUS_MAP[ib.status] or "success"
  local command_result_info = { commandName = cmdName, statusCode = status } -- default command result
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local all_user_credentials_removed = false

  if (cmdName == "deleteCredential" or cmdName == "deleteAllCredentials") and status == "success" then
    -- Get result from data saved in relevant, associated fields
    local credIdx = device:get_field(lock_utils.CRED_INDEX)

    -- find userIdx associated with credIdx, don't use lock utils field in this case
    userIdx = delete_credential_from_table(device, credIdx)
    if userIdx ~= nil then
      all_user_credentials_removed = not has_credentials(device, userIdx)
    end

    -- set unique command result fields
    command_result_info.userIndex = userIdx
    command_result_info.credentialIndex = credIdx
  elseif cmdName == "clearIssuerKey" and status == "success" then
    -- Get result from data saved in relevant, associated fields
    local reqId = device:get_field(lock_utils.COMMAND_REQUEST_ID)

    delete_aliro_from_table(device, userIdx, "issuerKey", nil)
    all_user_credentials_removed = not has_credentials(device, userIdx)

    -- set unique command result fields
    command_result_info.userIndex = userIdx
    command_result_info.requestId = reqId
  elseif cmdName == "clearEndpointKey" and status == "success" then
    -- Get result from data saved in relevant, associated fields
    local deviceKeyId = device:get_field(lock_utils.DEVICE_KEY_ID)
    local keyType = device:get_field(lock_utils.ENDPOINT_KEY_TYPE)
    local reqId = device:get_field(lock_utils.COMMAND_REQUEST_ID)

    delete_aliro_from_table(device, userIdx, keyType, deviceKeyId)
    all_user_credentials_removed = not has_credentials(device, userIdx)

    -- set unique command result fields
    command_result_info.userIndex = userIdx
    command_result_info.keyId = deviceKeyId
    command_result_info.requestId = reqId
  end

  -- user data if credentials were removed
  if all_user_credentials_removed then
    delete_user_from_table(device, userIdx)
    delete_week_schedule_from_table_as_user(device, userIdx)
    delete_year_schedule_from_table_as_user(device, userIdx)
  end

  -- Update commandResult
  if cmdName == "deleteCredential" or cmdName == "deleteAllCredentials" then
    device:emit_event(capabilities.lockCredentials.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
  else
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
  end
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

---------------------------
-- Set Week Day Schedule --
---------------------------
local function handle_set_week_day_schedule(driver, device, command)
  -- Get parameters
  local cmdName = "setWeekDaySchedule"
  local scheduleIdx = command.args.scheduleIndex
  local userIdx = command.args.userIndex
  local schedule = command.args.schedule
  local wDays = {}
  local scheduleBit = 0
  for _, weekDay in ipairs(schedule.weekDays) do
    scheduleBit = scheduleBit + WEEK_DAY_MAP[weekDay]
    table.insert(wDays, weekDay)
  end
  local startHour = schedule.startHour
  local startMinute = schedule.startMinute
  local endHour = schedule.endHour
  local endMinute = schedule.endMinute

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockSchedules.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.SCHEDULE_INDEX, scheduleIdx, {persist = true})
  device:set_field(lock_utils.SCHEDULE_WEEK_DAYS, wDays, {persist = true})
  device:set_field(lock_utils.SCHEDULE_START_HOUR, startHour, {persist = true})
  device:set_field(lock_utils.SCHEDULE_START_MINUTE, startMinute, {persist = true})
  device:set_field(lock_utils.SCHEDULE_END_HOUR, endHour, {persist = true})
  device:set_field(lock_utils.SCHEDULE_END_MINUTE, endMinute, {persist = true})

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
  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local scheduleIdx = device:get_field(lock_utils.SCHEDULE_INDEX)
  local days = device:get_field(lock_utils.SCHEDULE_WEEK_DAYS)
  local sHour = device:get_field(lock_utils.SCHEDULE_START_HOUR)
  local sMinute = device:get_field(lock_utils.SCHEDULE_START_MINUTE)
  local eHour = device:get_field(lock_utils.SCHEDULE_END_HOUR)
  local eMinute = device:get_field(lock_utils.SCHEDULE_END_MINUTE)
  local schedule = {
    weekDays = days,
    startHour = sHour,
    startMinute = sMinute,
    endHour = eHour,
    endMinute = eMinute
  }
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end

  -- Add Week Day Schedule to table
  if status == "success" then
    add_week_schedule_to_table(device, userIdx, scheduleIdx, schedule)
  else
    device.log.warn(string.format("Failed to set week day schedule: %s", status))
  end

  -- Update commandResult
  local command_result_info = {
    commandName = cmdName,
    userIndex = userIdx,
    scheduleIndex = scheduleIdx,
    statusCode = status
  }
  device:emit_event(capabilities.lockSchedules.commandResult(
    command_result_info, {state_change = true, visibility = {displayed = false}}
  ))
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

-----------------------------
-- Clear Week Day Schedule --
-----------------------------
local function handle_clear_week_day_schedule(driver, device, command)
  -- Get parameters
  local cmdName = "clearWeekDaySchedules"
  local scheduleIdx = command.args.scheduleIndex
  local userIdx = command.args.userIndex

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockSchedules.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.SCHEDULE_INDEX, scheduleIdx, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(DoorLock.server.commands.ClearWeekDaySchedule(device, ep, scheduleIdx, userIdx))
end

------------------------------------
-- Clear Week Day Schedule Response --
------------------------------------
local function clear_week_day_schedule_handler(driver, device, ib, response)
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
    delete_week_schedule_from_table(device, userIdx, scheduleIdx)
  else
    device.log.warn(string.format("Failed to clear week day schedule: %s", status))
  end

  -- Update commandResult
  local command_result_info = {
    commandName = cmdName,
    userIndex = userIdx,
    scheduleIndex = scheduleIdx,
    statusCode = status
  }
  device:emit_event(capabilities.lockSchedules.commandResult(
    command_result_info, {state_change = true, visibility = {displayed = false}}
  ))
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

-- This type represents an offset, in seconds, from 0 hours, 0 minutes, 0 seconds, on the 1st of January, 2000 UTC
local function iso8601_to_epoch(iso_str)
  local pattern = "^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)"
  local year, month, day, hour, min, sec = iso_str:match(pattern)
  if not year then
      return nil
  end
  local epoch_s = os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(min),
      sec = tonumber(sec),
  })

  -- The os.time() is based on 1970. Thirty years must be subtracted for calculations from 2000.
  epoch_s = epoch_s - THIRTY_YEARS_S

  if epoch_s < MIN_EPOCH_S then
    return MIN_EPOCH_S
  elseif epoch_s > MAX_EPOCH_S then
    return MAX_EPOCH_S
  else
    return epoch_s
  end
end

---------------------------
-- Set Year Day Schedule --
---------------------------
local function handle_set_year_day_schedule(driver, device, command)
  -- Get parameters
  local cmdName = "setYearDaySchedule"
  local scheduleIdx = command.args.scheduleIndex
  local userIdx = command.args.userIndex
  local localStartTime = command.args.schedule.localStartTime
  local localEndTime = command.args.schedule.localEndTime

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockSchedules.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.SCHEDULE_INDEX, scheduleIdx, {persist = true})
  device:set_field(lock_utils.SCHEDULE_LOCAL_START_TIME, localStartTime, {persist = true})
  device:set_field(lock_utils.SCHEDULE_LOCAL_END_TIME, localEndTime, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetYearDaySchedule(
      device, ep,
      scheduleIdx,
      userIdx,
      iso8601_to_epoch(localStartTime),
      iso8601_to_epoch(localEndTime)
    )
  )
end

------------------------------------
-- Set Year Day Schedule Response --
------------------------------------
local function set_year_day_schedule_handler(driver, device, ib, response)
  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local userIdx = device:get_field(lock_utils.USER_INDEX)
  local scheduleIdx = device:get_field(lock_utils.SCHEDULE_INDEX)
  local localStartTime = device:get_field(lock_utils.SCHEDULE_LOCAL_START_TIME)
  local localEndTime = device:get_field(lock_utils.SCHEDULE_LOCAL_END_TIME)
  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  end

  if cmdName == "defaultSchedule" then
    return
  end

  if status == "success" then
    if cmdName == "setYearDaySchedule" then
      add_year_schedule_to_table(device, userIdx, scheduleIdx, localStartTime, localEndTime)
    elseif cmdName == "clearYearDaySchedules" then
      delete_year_schedule_from_table(device, userIdx, scheduleIdx)
    end
  else
    device.log.warn(string.format("Failed to set/clear year day schedule: %s", status))
  end

  -- Update commandResult
  local command_result_info = {
    commandName = cmdName,
    userIndex = userIdx,
    scheduleIndex = scheduleIdx,
    statusCode = status
  }
  device:emit_event(capabilities.lockSchedules.commandResult(
    command_result_info, {state_change = true, visibility = {displayed = false}}
  ))
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

-----------------------------
-- Clear Year Day Schedule --
-----------------------------
local function handle_clear_year_day_schedule(driver, device, command)
  -- Get parameters
  local cmdName = "clearYearDaySchedules"
  local scheduleIdx = command.args.scheduleIndex
  local userIdx = command.args.userIndex

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockSchedules.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.SCHEDULE_INDEX, scheduleIdx, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})

  -- Send command
  -- In SmartThings, Schedule Restrict User is basically allowed to access always.
  -- So, if user delete the year day schedule, enter an infinitely long schedule.
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetYearDaySchedule(
      device, ep,
      scheduleIdx,
      userIdx,
      MIN_EPOCH_S,
      MAX_EPOCH_S
    )
  )
end

----------------
-- Lock Alarm --
----------------
local function alarm_event_handler(driver, device, ib, response)
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
  local opType = ib.data.elements.lock_operation_type
  local opSource = ib.data.elements.operation_source
  local userIdx = ib.data.elements.user_index
  -- TODO: This handler can check fabric index and exclude other fabric events

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
    opType = Lock.unlatched
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

  if userIdx ~= nil then
    userIdx = userIdx.value
  end

  local data_obj = {method = opSource, userIndex = userIdx}
  device:emit_event(opType({data = data_obj, state_change = true}))
end

local function handle_refresh(driver, device, command)
  local req = DoorLock.attributes.LockState:read(device)
  device:send(req)
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

local function handle_set_reader_config(driver, device, command)
  local cmdName = "setReaderConfig"
  local signingKey = command.args.signingKey
  local verificationKey = command.args.verificationKey
  local groupId = command.args.groupId
  local groupResolvingKey = nil
  local aliro_ble_uwb_eps = device:get_endpoints(DoorLock.ID, {feature_bitmap = DoorLock.types.Feature.ALIROBLEUWB})
  if #aliro_ble_uwb_eps > 0 then
    groupResolvingKey = command.args.groupResolvingKey
  end

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.VERIFICATION_KEY, verificationKey, {persist = true})
  device:set_field(lock_utils.GROUP_ID, groupId, {persist = true})
  device:set_field(lock_utils.GROUP_RESOLVING_KEY, groupResolvingKey, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetAliroReaderConfig(
      device, ep,
      hex_string_to_octet_string(signingKey),
      hex_string_to_octet_string(verificationKey),
      hex_string_to_octet_string(groupId), -- Group identification
      hex_string_to_octet_string(groupResolvingKey) -- Group resolving key
    )
  )
end

local function set_aliro_reader_config_handler(driver, device, ib, response)
  -- Get result
  local cmdName = device:get_field(lock_utils.COMMAND_NAME)
  local verificationKey = device:get_field(lock_utils.VERIFICATION_KEY)
  local groupId = device:get_field(lock_utils.GROUP_ID)
  local groupResolvingKey = device:get_field(lock_utils.GROUP_RESOLVING_KEY)

  local status = "success"
  if ib.status == DoorLock.types.DlStatus.FAILURE then
    status = "failure"
  elseif ib.status == DoorLock.types.DlStatus.INVALID_FIELD then
    status = "invalidCommand"
  elseif ib.status == DoorLock.types.DlStatus.SUCCESS then
    if verificationKey ~= nil then
      device:emit_event(capabilities.lockAliro.readerVerificationKey(
        verificationKey,
        {
          state_change = true,
          visibility = {displayed = false}
        }
      ))
    end
    if groupId ~= nil then
      device:emit_event(capabilities.lockAliro.readerGroupIdentifier(
        groupId,
        {
          state_change = true,
          visibility = {displayed = false}
        }
      ))
    end
    if groupResolvingKey ~= nil then
      device:emit_event(capabilities.lockAliro.groupResolvingKey(
        groupResolvingKey,
        {
          state_change = true,
          visibility = {displayed = false}
        }
      ))
    end
  end

  -- Update commandResult
  local command_result_info = {
    commandName = cmdName,
    statusCode = status
  }
  device:emit_event(capabilities.lockAliro.commandResult(
    command_result_info, {state_change = true, visibility = {displayed = false}}
  ))
  device:set_field(lock_utils.BUSY_STATE, false, {persist = true})
end

local function handle_set_card_id(driver, device, command)
  if command.args.cardId ~= nil then
    device:emit_event(capabilities.lockAliro.cardId(command.args.cardId, {visibility = {displayed = false}}))
  end
end

local function handle_set_issuer_key(driver, device, command)
  -- Get parameters
  local cmdName = "setIssuerKey"
  local userIdx = command.args.userIndex
  local userType = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  local issuerKey = command.args.issuerKey
  local reqId = command.args.requestId
  local credential = {
    credential_type = DoorLock.types.CredentialTypeEnum.ALIRO_CREDENTIAL_ISSUER_KEY,
    credential_index = INITIAL_CREDENTIAL_INDEX
  }

  -- Adjustment
  if userIdx == 0 then
    userIdx = nil
  else
    userType = nil
  end

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      requestId = reqId,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.ISSUER_KEY, issuerKey, {persist = true})
  device:set_field(lock_utils.ISSUER_KEY_INDEX, INITIAL_CREDENTIAL_INDEX, {persist = true})
  device:set_field(lock_utils.COMMAND_REQUEST_ID, reqId, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetCredential(
      device, ep,
      DoorLock.types.DataOperationTypeEnum.ADD, -- Data Operation Type: Add(0), Modify(2)
      credential, -- Credential
      hex_string_to_octet_string(issuerKey), -- Credential Data
      userIdx, -- User Index
      nil, -- User Status
      userType -- User Type
    )
  )
end

local function handle_clear_issuer_key(driver, device, command)
  -- Get parameters
  local cmdName = "clearIssuerKey"
  local userIdx = command.args.userIndex
  local reqId = command.args.requestId

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      requestId = reqId,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.COMMAND_REQUEST_ID, reqId, {persist = true})

  -- Get latest aliro table
  local aliro_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockAliro.ID,
    capabilities.lockAliro.credentials.NAME,
    {}
  ))

  -- Find issuer key index
  for index, entry in pairs(aliro_table) do
    if entry.userIndex == userIdx and entry.keyType == "issuerKey" then
      -- Set parameters
      local credential = {
        credential_type = DoorLock.types.CredentialTypeEnum.ALIRO_CREDENTIAL_ISSUER_KEY,
        credential_index = entry.keyIndex,
      }
      -- Send command
      local ep = device:component_to_endpoint(command.component)
      device:send(DoorLock.server.commands.ClearCredential(device, ep, credential))
      break
    end
  end
end

local function handle_set_endpoint_key(driver, device, command)
  -- Get parameters
  local cmdName = "setEndpointKey"
  local userIdx = command.args.userIndex
  local userType = DoorLock.types.UserTypeEnum.UNRESTRICTED_USER
  local keyId = command.args.keyId
  local keyType = command.args.keyType
  local endpointKey = command.args.endpointKey
  local reqId = command.args.requestId
  local dataOpType = DoorLock.types.DataOperationTypeEnum.ADD -- Data Operation Type: Add(0), Modify(2)
  local endpointKeyIndex = INITIAL_CREDENTIAL_INDEX

  -- Min user index of commandResult is 1
  -- 0 should convert to nil before busy check
  if userIdx == 0 then
    userIdx = nil
  end

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      keyId = keyId,
      requestId = reqId,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Adjustment
  if userIdx ~= nil then
    userType = nil

    -- Get latest aliro table
    local aliro_table = utils.deep_copy(device:get_latest_state(
      "main",
      capabilities.lockAliro.ID,
      capabilities.lockAliro.credentials.NAME,
      {}
    ))

    -- Find existing endpoint key
    for index, entry in pairs(aliro_table) do
      if (entry.keyType == "evictableEndpointKey" or entry.keyType == "nonEvictableEndpointKey") and entry.keyId == keyId then
        dataOpType = DoorLock.types.DataOperationTypeEnum.MODIFY
        endpointKeyIndex = entry.keyIndex
        delete_aliro_from_table(device, userIdx, keyType, keyId)
        break
      end
    end
  end

  local credential = {
    credential_type = ALIRO_KEY_TYPE_TO_CRED_ENUM_MAP[keyType],
    credential_index = endpointKeyIndex
  }

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.DEVICE_KEY_ID, keyId, {persist = true})
  device:set_field(lock_utils.ENDPOINT_KEY_TYPE, keyType, {persist = true})
  device:set_field(lock_utils.ENDPOINT_KEY, endpointKey, {persist = true})
  device:set_field(lock_utils.ENDPOINT_KEY_INDEX, endpointKeyIndex, {persist = true})
  device:set_field(lock_utils.COMMAND_REQUEST_ID, reqId, {persist = true})

  -- Send command
  local ep = device:component_to_endpoint(command.component)
  device:send(
    DoorLock.server.commands.SetCredential(
      device, ep,
      dataOpType, -- Data Operation Type: Add(0), Modify(2)
      credential, -- Credential
      hex_string_to_octet_string(endpointKey), -- Credential Data
      userIdx,    -- User Index
      nil,        -- User Status
      userType    -- User Type
    )
  )
end

local function handle_clear_endpoint_key(driver, device, command)
  -- Get parameters
  local cmdName = "clearEndpointKey"
  local userIdx = command.args.userIndex
  local keyId = command.args.keyId
  local keyType = command.args.keyType
  local reqId = command.args.requestId

  -- Check busy state
  if is_busy_state_set(device) then
    local command_result_info = {
      commandName = cmdName,
      userIndex = userIdx,
      keyId = keyId,
      requestId = reqId,
      statusCode = "busy"
    }
    device:emit_event(capabilities.lockAliro.commandResult(
      command_result_info, {state_change = true, visibility = {displayed = false}}
    ))
    return
  end

  -- Save values to field
  device:set_field(lock_utils.COMMAND_NAME, cmdName, {persist = true})
  device:set_field(lock_utils.USER_INDEX, userIdx, {persist = true})
  device:set_field(lock_utils.DEVICE_KEY_ID, keyId, {persist = true})
  device:set_field(lock_utils.ENDPOINT_KEY_TYPE, keyType, {persist = true})
  device:set_field(lock_utils.COMMAND_REQUEST_ID, reqId, {persist = true})

  -- Get latest aliro table
  local aliro_table = utils.deep_copy(device:get_latest_state(
    "main",
    capabilities.lockAliro.ID,
    capabilities.lockAliro.credentials.NAME,
    {}
  ))

  local ep = device:component_to_endpoint(command.component)
  if keyId == nil then
    return
  else
    -- Find aliro credential
    for index, entry in pairs(aliro_table) do
      if entry.userIndex == userIdx and entry.keyId == keyId and entry.keyType == keyType then
        -- Set parameters
        local credential = {
          credential_type = ALIRO_KEY_TYPE_TO_CRED_ENUM_MAP[keyType],
          credential_index = entry.keyIndex,
        }
        -- Send command
        device:send(DoorLock.server.commands.ClearCredential(device, ep, credential))
        break
      end
    end
  end
end

local new_matter_lock_handler = {
  NAME = "New Matter Lock Handler",
  lifecycle_handlers = {
    init = device_init,
    added = device_added,
    doConfigure = do_configure,
    infoChanged = info_changed,
    driverSwitched = driver_switched
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
        [DoorLock.attributes.AliroReaderVerificationKey.ID] = aliro_reader_verification_key_handler,
        [DoorLock.attributes.AliroReaderGroupIdentifier.ID] = aliro_reader_group_id_handler,
        [DoorLock.attributes.AliroExpeditedTransactionSupportedProtocolVersions.ID] = aliro_protocol_versions_handler,
        [DoorLock.attributes.AliroGroupResolvingKey.ID] = aliro_group_resolving_key_handler,
        [DoorLock.attributes.AliroSupportedBLEUWBProtocolVersions.ID] = aliro_supported_ble_uwb_protocol_versions_handler,
        [DoorLock.attributes.AliroBLEAdvertisingVersion.ID] = aliro_ble_advertising_version_handler,
        [DoorLock.attributes.NumberOfAliroCredentialIssuerKeysSupported.ID] = max_aliro_credential_issuer_key_handler,
        [DoorLock.attributes.NumberOfAliroEndpointKeysSupported.ID] = max_aliro_endpoint_key_handler,
      },
      [PowerSource.ID] = {
        [PowerSource.attributes.AttributeList.ID] = handle_power_source_attribute_list,
        [PowerSource.attributes.BatPercentRemaining.ID] = handle_battery_percent_remaining,
        [PowerSource.attributes.BatChargeLevel.ID] = handle_battery_charge_level,
      }
    },
    event = {
      [DoorLock.ID] = {
        [DoorLock.events.DoorLockAlarm.ID] = alarm_event_handler,
        [DoorLock.events.LockOperation.ID] = lock_op_event_handler,
      },
    },
    cmd_response = {
      [DoorLock.ID] = {
        [DoorLock.server.commands.SetUser.ID] = set_user_response_handler,
        [DoorLock.client.commands.GetUserResponse.ID] = get_user_response_handler,
        [DoorLock.server.commands.ClearUser.ID] = clear_user_response_handler,
        [DoorLock.client.commands.SetCredentialResponse.ID] = set_credential_response_handler,
        [DoorLock.server.commands.ClearCredential.ID] = clear_credential_response_handler,
        [DoorLock.server.commands.SetWeekDaySchedule.ID] = set_week_day_schedule_handler,
        [DoorLock.server.commands.ClearWeekDaySchedule.ID] = clear_week_day_schedule_handler,
        [DoorLock.server.commands.SetYearDaySchedule.ID] = set_year_day_schedule_handler,
        [DoorLock.server.commands.SetAliroReaderConfig.ID] = set_aliro_reader_config_handler,
      },
    },
  },
  subscribed_attributes = subscribed_attributes,
  subscribed_events = subscribed_events,
  capability_handlers = {
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.lock.NAME] = handle_lock,
      [capabilities.lock.commands.unlock.NAME] = handle_unlock,
      [capabilities.lock.commands.unlatch.NAME] = handle_unlatch
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
    [capabilities.lockAliro.ID] = {
      [capabilities.lockAliro.commands.setReaderConfig.NAME] = handle_set_reader_config,
      [capabilities.lockAliro.commands.setCardId.NAME] = handle_set_card_id,
      [capabilities.lockAliro.commands.setIssuerKey.NAME] = handle_set_issuer_key,
      [capabilities.lockAliro.commands.clearIssuerKey.NAME] = handle_clear_issuer_key,
      [capabilities.lockAliro.commands.setEndpointKey.NAME] = handle_set_endpoint_key,
      [capabilities.lockAliro.commands.clearEndpointKey.NAME] = handle_clear_endpoint_key,
    },
    [capabilities.refresh.ID] = {[capabilities.refresh.commands.refresh.NAME] = handle_refresh}
  },
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockUsers,
    capabilities.lockCredentials,
    capabilities.lockSchedules,
    capabilities.battery,
    capabilities.batteryLevel
  },
  can_handle = is_new_matter_lock_products
}

return new_matter_lock_handler
