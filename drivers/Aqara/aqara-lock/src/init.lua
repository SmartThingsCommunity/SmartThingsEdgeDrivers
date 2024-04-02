local security = require "st.security"
local ZigbeeDriver = require "st.zigbee"
local data_types = require "st.zigbee.data_types"
local cluster_base = require "st.zigbee.cluster_base"
local capabilities = require "st.capabilities"
local base64 = require "base64"
local credential_utils = require "credential_utils"

local remoteControlStatus = capabilities.remoteControlStatus
local lockCredentialInfo = capabilities["stse.lockCredentialInfo"]
local Battery = capabilities.battery
local Lock = capabilities.lock
local TamperAlert = capabilities.tamperAlert

local PRI_CLU = 0xFCC0
local PRI_ATTR = 0xFFF3
local MFG_CODE = 0x115F

local serial_num = 0
local seq_num = 0

local SHARED_KEY = "__shared_key"
local CLOUD_PUBLIC_KEY = "__cloud_public_key"

local function my_secret_data_handler(driver, device, secret_info)
  -- At time of writing this returns nothind beyond "secret_type = aqara"
  local shared_key = secret_info.shared_key
  local cloud_public_key = secret_info.cloud_public_key

  device:set_field(SHARED_KEY, shared_key, { persist = true })
  device:set_field(CLOUD_PUBLIC_KEY, cloud_public_key, { persist = true })
  credential_utils.save_data(driver)

  if cloud_public_key ~= nil then
    local raw_data = base64.decode(cloud_public_key)
    -- send cloud_pub_key
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRI_CLU, PRI_ATTR, MFG_CODE, data_types.OctetString, "\x3E" .. raw_data))
  end
end

local function device_added(self, device)
  if credential_utils.is_exist_host(device) then
    device:emit_event(remoteControlStatus.remoteControlEnabled('true', { visibility = { displayed = false } }))
  else
    credential_utils.set_host_count(device, 0)
    device:emit_event(remoteControlStatus.remoteControlEnabled('false', { visibility = { displayed = false } }))
  end
  device:emit_event(Battery.battery(100))
  device:emit_event(TamperAlert.tamper("clear", { visibility = { displayed = false } }))
  device:emit_event(Lock.lock("locked"))
  credential_utils.save_data(self)
end

local function toValue(payload, start, length)
  local ret = 0
  for i = start, start + length - 1 do
    ret = (ret << 8) + string.byte(payload, i)
  end
  return ret
end

local function toHex(value, length)
  local ret = string.char(0xFF & value)
  for i = length, 2, -1 do
    ret = string.char(0xFF & (value >> 8 * (i - 1))) .. ret
  end
  return ret
end

local function event_lock_handler(driver, device, evt_name, evt_value)
  if evt_value == 1 then
    device:emit_event(Lock.lock(evt_name))
    device:emit_event(TamperAlert.tamper.clear())
    if credential_utils.is_exist_host(device) then
      device:emit_event(remoteControlStatus.remoteControlEnabled('true', { visibility = { displayed = false } }))
    else
      device:emit_event(remoteControlStatus.remoteControlEnabled('false', { visibility = { displayed = false } }))
    end
  end
end

local function event_unlock_handler(driver, device, evt_name, evt_value)
  local id, label
  id, label = credential_utils.find_userLabel(driver, device, evt_value)
  device:emit_event(Lock.lock.unlocked({ data = { method = evt_name, codeId = id, codeName = label } }))
  device:emit_event(remoteControlStatus.remoteControlEnabled('false', { visibility = { displayed = false } }))
  device:emit_event(TamperAlert.tamper.clear())
end

local function event_door_handler(driver, device, evt_name, evt_value)
  if evt_value == 2 then
    device:emit_event(Lock.lock(evt_name))
    device:emit_event(TamperAlert.tamper.clear())
  elseif evt_value == 4 then
    device:emit_event(TamperAlert.tamper.detected())
  end
end

local function event_battery_handler(driver, device, evt_name, evt_value)
  device:emit_event(Battery.battery(evt_value))
end

local function event_temper_alert_handler(driver, device, evt_name, evt_value)
  device:emit_event(TamperAlert.tamper.detected())
end

local resource_id = {
  { id = "13.31.85", event_name = "locked",       event_handler = event_lock_handler },
  { id = "13.17.85", event_name = "not fully locked", event_handler = event_door_handler },
  { id = "13.48.85", event_name = "manual",       event_handler = event_unlock_handler },
  { id = "13.51.85", event_name = "manual",       event_handler = event_unlock_handler },
  { id = "13.42.85", event_name = "fingerprint",  event_handler = event_unlock_handler },
  { id = "13.43.85", event_name = "keypad",       event_handler = event_unlock_handler },
  { id = "13.44.85", event_name = "rfid",         event_handler = event_unlock_handler },
  { id = "13.45.85", event_name = "bluetooth",    event_handler = event_unlock_handler },
  { id = "13.90.85", event_name = "command",      event_handler = event_unlock_handler },
  { id = "13.46.85", event_name = "keypad",       event_handler = event_unlock_handler },
  { id = "13.56.85", event_name = "",             event_handler = event_battery_handler },
  { id = "13.32.85", event_name = "",             event_handler = event_temper_alert_handler },
}

local function request_generate_shared_key(device)
  device:send(cluster_base.write_manufacturer_specific_attribute(device,
    PRI_CLU, PRI_ATTR, MFG_CODE, data_types.OctetString, "\x2B"))
end

local function lock_state_handler(driver, device, value, zb_rx)
  local shared_key = device:get_field(SHARED_KEY)
  local param = value.value
  local command = string.sub(param, 0, 1)

  if command == "\x3E" then
    -- recv lock_pub_key
    local locks_pub_key = string.sub(param, 2, string.len(param))
    local mn_id = "Id3A"
    local setup_id = "006"
    local product_id = ""
    local res, err = security.get_aqara_secret(device.zigbee_eui, locks_pub_key, "", mn_id, setup_id,
      product_id)
    if res then
      print(res)
    end
  elseif shared_key == nil then
    request_generate_shared_key(device)
  elseif command == "\x93" then
    local opts = { cipher = "aes256-ecb", padding = false }
    local raw_key = base64.decode(shared_key)
    local raw_data = string.sub(param, 2, string.len(param))
    local msg = security.decrypt_bytes(raw_data, raw_key, opts)
    local text = string.sub(msg, 5, string.len(msg))
    local payload = string.sub(text, 4, string.len(text))
    local func_id = toValue(payload, 1, 1) .. "." .. toValue(payload, 2, 1) .. "." .. toValue(payload, 3, 2)
    serial_num = toValue(msg, 3, 2)
    seq_num = string.byte(text, 3)

    for k, v in pairs(resource_id) do
      if func_id == v.id then
        v.event_handler(driver, device, v.event_name, toValue(payload, 6, string.byte(payload, 5)))
        goto finish
      end
    end
    ::finish::
    if serial_num >= 0xFFFF then
      device:send(cluster_base.write_manufacturer_specific_attribute(device,
        PRI_CLU, PRI_ATTR, MFG_CODE, data_types.OctetString, "\x2B"))
    end
  end
end

local function send_msg(device, funcA, funcB, funcC, op_code, length, value)
  local shared_key = device:get_field(SHARED_KEY)
  if shared_key == nil then
    request_generate_shared_key(device)
  else
    local payload = toHex(funcA, 1) .. toHex(funcB, 1) .. toHex(funcC, 2) .. toHex(length, 1) .. toHex(value, length)
    seq_num = seq_num + 1
    local text = "\x00" .. toHex(op_code, 1) .. toHex(seq_num, 1) .. payload
    serial_num = serial_num + 1
    local raw_data = "\x5B" .. toHex(string.len(text), 1) .. toHex(serial_num, 2) .. text
    for i = 1, 4 - (string.len(raw_data) % 4) do
      raw_data = raw_data .. "\x00"
    end

    local opts = { cipher = "aes256-ecb", padding = false }
    local raw_key = base64.decode(shared_key)
    local result = security.encrypt_bytes(raw_data, raw_key, opts)
    local msg = "\x93" .. result
    device:send(cluster_base.write_manufacturer_specific_attribute(device,
      PRI_CLU, PRI_ATTR, MFG_CODE, data_types.OctetString, msg))
  end
end

local function unlock_cmd_handler(driver, device, cmd)
  send_msg(device, 4, 17, 85, 2, 1, 1)
end

local aqara_locks_handler = {
  NAME = "Aqara Doorlock K100",
  supported_capabilities = {
    Lock,
    Battery,
    lockCredentialInfo,
    capabilities.refresh,
  },
  zigbee_handlers = {
    attr = {
      [PRI_CLU] = {
        [PRI_ATTR] = lock_state_handler
      }
    }
  },
  capability_handlers = {
    [lockCredentialInfo.ID] = {
      [lockCredentialInfo.commands.syncAll.NAME] = credential_utils.sync_all_credential_info,
      [lockCredentialInfo.commands.upsert.NAME] = credential_utils.upsert_credential_info,
      [lockCredentialInfo.commands.deleteUser.NAME] = credential_utils.delete_user,
      [lockCredentialInfo.commands.deleteCredential.NAME] = credential_utils.delete_credential
    },
    [capabilities.lock.ID] = {
      [capabilities.lock.commands.unlock.NAME] = unlock_cmd_handler
    }
  },
  lifecycle_handlers = {
    added = device_added
  },
  secret_data_handlers = {
    [security.SECRET_KIND_AQARA] = my_secret_data_handler
  }
}

local aqara_locks_driver = ZigbeeDriver("aqara_locks_k100", aqara_locks_handler)
aqara_locks_driver:run()
