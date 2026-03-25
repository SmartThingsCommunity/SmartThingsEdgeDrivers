-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local security = require "st.security"
local PUB_KEY_PREFIX = "04"

local lock_utils = {
  -- Lock device field names
  LOCK_CODES = "lockCodes",
  CHECKING_CREDENTIAL = "checkingCredential",
  CODE_STATE = "codeState",
  DELETING_CODE = "deletingCode",
  CREDENTIALS_PER_USER = "credsPerUser",
  TOTAL_PIN_USERS = "totalPinUsers",
  SET_CREDENTIAL = "setCredential",
  COTA_CRED = "cotaCred",
  COTA_CODE_NAME = "ST Remote Operation Code",
  COTA_CRED_INDEX = "cotaCredIndex",
  NONFUNCTIONAL = "nonFunctional",
  COTA_READ_INITIALIZED = "cotaReadInitialized",
  BUSY_STATE = "busyState",
  COMMAND_NAME = "commandName",
  USER_NAME = "userName",
  USER_INDEX = "userIndex",
  USER_TYPE = "userType",
  CRED_INDEX = "credentialIndex",
  CRED_DATA = "credentialData",
  SCHEDULE_INDEX = "scheduleIndex",
  SCHEDULE_WEEK_DAYS = "scheduleWeekDays",
  SCHEDULE_START_HOUR = "scheduleStartHour",
  SCHEDULE_START_MINUTE = "scheduleStartMinute",
  SCHEDULE_END_HOUR = "scheduleEndHour",
  SCHEDULE_END_MINUTE = "scheduleEndMinute",
  SCHEDULE_LOCAL_START_TIME = "scheduleLocalStartTime",
  SCHEDULE_LOCAL_END_TIME = "scheduleLocalEndTime",
  VERIFICATION_KEY = "verificationKey",
  GROUP_ID = "groupId",
  GROUP_RESOLVING_KEY = "groupResolvingKey",
  ISSUER_KEY = "issuerKey",
  ISSUER_KEY_INDEX = "issuerKeyIndex",
  ENDPOINT_KEY = "endpointKey",
  ENDPOINT_KEY_INDEX = "endpointKeyIndex",
  ENDPOINT_KEY_TYPE = "endpointKeyType",
  DEVICE_KEY_ID = "deviceKeyId",
  COMMAND_REQUEST_ID = "commandRequestId",
  MODULAR_PROFILE_UPDATED = "__MODULAR_PROFILE_UPDATED",
  ALIRO_READER_CONFIG_UPDATED = "aliroReaderConfigUpdated",
  LATEST_DOOR_LOCK_FEATURE_MAP = "latestDoorLockFeatureMap"
}
local capabilities = require "st.capabilities"
local json = require "st.json"
local utils = require "st.utils"

lock_utils.get_lock_codes = function(device)
  local lc = device:get_field(lock_utils.LOCK_CODES)
  return lc ~= nil and lc or {}
end

function lock_utils.get_code_name(device, code_id)
  if (device:get_field(lock_utils.CODE_STATE) ~= nil
    and device:get_field(lock_utils.CODE_STATE)["setName" .. code_id] ~= nil) then
    -- this means a code set operation succeeded
    return device:get_field(lock_utils.CODE_STATE)["setName" .. code_id]
  elseif (lock_utils.get_lock_codes(device)[code_id] ~= nil) then
    return lock_utils.get_lock_codes(device)[code_id]
  else
    return "Code " .. code_id
  end
end

function lock_utils.get_change_type(device, code_id)
  if (lock_utils.get_lock_codes(device)[code_id] == nil) then
    return code_id .. " set"
  else
    return code_id .. " changed"
  end
end

lock_utils.lock_codes_event = function(device, lock_codes)
  device:set_field(lock_utils.LOCK_CODES, lock_codes, {persist = true})
  device:emit_event(
    capabilities.lockCodes.lockCodes(
      json.encode(utils.deep_copy(lock_codes)), {visibility = {displayed = false}}
    )
  )
end

function lock_utils.reset_code_state(device, code_slot)
  local codeState = device:get_field(lock_utils.CODE_STATE)
  if (codeState ~= nil) then
    codeState["setName" .. code_slot] = nil
    codeState["setCode" .. code_slot] = nil
    device:set_field(lock_utils.CODE_STATE, codeState, {persist = true})
  end
end

function lock_utils.code_deleted(device, code_slot)
  local lock_codes = lock_utils.get_lock_codes(device)
  local event = capabilities.lockCodes.codeChanged(code_slot .. " deleted", {state_change = true})
  event.data = {codeName = lock_utils.get_code_name(device, code_slot)}
  lock_codes[code_slot] = nil
  device:emit_event(event)
  lock_utils.reset_code_state(device, code_slot)
  return lock_codes
end

--[[]]
-- keys are the code slots that ST uses
-- user_index and credential_index are used in the matter commands
--
function lock_utils.get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

function lock_utils.set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

function lock_utils.optional_capabilities_list_changed(new_component_capability_list, previous_component_capability_list)
  local previous_capability_map = {}
  local component_sizes = {}
  local previous_component_count = 0
  for component_name, component in pairs(previous_component_capability_list or {}) do
    previous_capability_map[component_name] = {}
    component_sizes[component_name] = 0
    for _, capability in pairs(component.capabilities or {}) do
      if capability.id ~= "lock" and capability.id ~= "lockAlarm" and capability.id ~= "remoteControlStatus" and
        capability.id ~= "firmwareUpdate" and capability.id ~= "refresh" then
        previous_capability_map[component_name][capability.id] = true
        component_sizes[component_name] = component_sizes[component_name] + 1
      end
    end
    previous_component_count = previous_component_count + 1
  end

  local number_of_components_counted = 0
  for _, new_component_capabilities in pairs(new_component_capability_list or {}) do
    local component_name = new_component_capabilities[1]
    local capability_list = new_component_capabilities[2]
    number_of_components_counted = number_of_components_counted + 1
    if previous_capability_map[component_name] == nil then
      return true
    end
    for _, capability in ipairs(capability_list) do
      if previous_capability_map[component_name][capability] == nil then
        return true
      end
    end
    if #capability_list ~= component_sizes[component_name] then
      return true
    end
  end

  if number_of_components_counted ~= previous_component_count then
    return true
  end

  return false
end

-- This function check busy_state and if busy_state is false, set it to true(current time)
function lock_utils.is_busy_state_set(device)
  local c_time = os.time()
  local busy_state = device:get_field(lock_utils.BUSY_STATE) or false
  if busy_state == false or c_time - busy_state > 10 then
    device:set_field(lock_utils.BUSY_STATE, c_time, {persist = true})
    return false
  else
    return true
  end
end

function lock_utils.hex_string_to_octet_string(hex_string)
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

function lock_utils.create_group_id_resolving_key()
  math.randomseed(os.time())
  local result = string.format("%02x", math.random(0, 255))
  for i = 1, 15 do
    result = result .. string.format("%02x", math.random(0, 255))
  end
  return result
end

function lock_utils.generate_keypair(device)
  local request_opts = {
    key_algorithm = {
      type = "ec",
      curve = "prime256v1"
    },
    signature_algorithm = "sha256",
    return_formats = {
      pem = true,
      der = true
    },
    subject = {
      common_name = "reader config"
    },
    validity_days = 36500,
    x509_extensions = {
      key_usage = {
        critical = true,
        digital_signature = true
      },
      certificate_policies = {
        critical = true,
        policy_2030_5_self_signed_client = true
      }
    }
  }
  local status = security.generate_self_signed_cert(request_opts)
  if not status or not status.key_der then
    device.log.error("generate_self_signed_cert returned no data")
    return nil, nil
  end

  local der = status.key_der
  local privKey, pubKey = nil, nil
  -- Helper: Parse ASN.1 length (handles 1-byte and multi-byte lengths)
  local function get_length(data, start_pos)
    local b = string.byte(data, start_pos)
    if not b then return nil, start_pos end

    if b < 0x80 then
      return b, start_pos + 1
    else
      local num_bytes = b - 0x80
      local len = 0
      for i = 1, num_bytes do
        len = (len * 256) + string.byte(data, start_pos + i)
      end
      return len, start_pos + 1 + num_bytes
    end
  end
  -- Start parsing after the initial SEQUENCE tag (0x30)
  -- Most keys start: [0x30][Length]. We find the first length to find the start of content.
  local _, pos = get_length(der, 2)

  while pos < #der do
    local tag = string.byte(der, pos)
    local len, content_start = get_length(der, pos + 1)
    if not len then break end
    if tag == 0x04 then
      -- PRIVATE KEY: Octet String
      privKey = utils.bytes_to_hex_string(string.sub(der, content_start, content_start + len - 1))
    elseif tag == 0xA1 then
      -- PUBLIC KEY Wrapper: Explicit Tag [1]
      -- Inside 0xA1 is a BIT STRING (0x03)
      local inner_tag = string.byte(der, content_start)
      if inner_tag == 0x03 then
        local bit_len, bit_start = get_length(der, content_start + 1)
        -- BIT STRINGS have a "leading null byte" (unused bits indicator)
        -- We skip that byte (bit_start) and the 0x04 EC prefix to get the raw X/Y coordinates
        local actual_key_start = bit_start + 2
        local actual_key_len = bit_len - 2
        pubKey = PUB_KEY_PREFIX .. utils.bytes_to_hex_string(string.sub(der, actual_key_start, actual_key_start + actual_key_len - 1))
      end
    end
    -- Move pointer to the next tag
    pos = content_start + len
  end

  if not privKey or not pubKey then
    device.log.error("Failed to extract keys from DER")
  end
  return privKey, pubKey
end

return lock_utils
