local capabilities = require "st.capabilities"
local utils = require "st.utils"

local remoteControlStatus = capabilities.remoteControlStatus
local lockCredentialInfo = capabilities["stse.lockCredentialInfo"]

local credential_utils = {}
local HOST_COUNT = "__host_count"

credential_utils.save_data = function(driver)
  driver.datastore:save()
  driver.datastore:commit()
end

credential_utils.update_remote_control_status = function(driver, device, added)
  local host_cnt = device:get_field(HOST_COUNT) or 0
  if added then
    if host_cnt == 0 then
      device:emit_event(remoteControlStatus.remoteControlEnabled('true', { visibility = { displayed = false } }))
    end
    host_cnt = host_cnt + 1
  else
    if host_cnt > 0 then host_cnt = host_cnt - 1 end

    if host_cnt == 0 then
      device:emit_event(remoteControlStatus.remoteControlEnabled('false', { visibility = { displayed = false } }))
    end
  end

  device:set_field(HOST_COUNT, host_cnt, { persist = true })
  credential_utils.save_data(driver)
end

credential_utils.sync_all_credential_info = function(driver, device, command)
  for _, credentialinfo in ipairs(command.args.credentialInfo) do
    if credentialinfo.userType == "host" then
      credential_utils.update_remote_control_status(driver, device, true)
    end
  end
  device:emit_event(lockCredentialInfo.credentialInfo(command.args.credentialInfo, { visibility = { displayed = false } }))
  credential_utils.save_data(driver)
end

credential_utils.upsert_credential_info = function(driver, device, command)
  if #command.args.credentialInfo == 0 then
    return
  end

  local credentialInfoTable = utils.deep_copy(device:get_latest_state("main", lockCredentialInfo.ID,
    lockCredentialInfo.credentialInfo.NAME, {}))

  for _, credentialinfo in ipairs(command.args.credentialInfo) do
    local exist = false
    for i = 1, #credentialInfoTable, 1 do
      if credentialInfoTable[i].credentialId == credentialinfo.credentialId then
        credentialInfoTable[i] = utils.deep_copy(credentialinfo)
        exist = true
        break
      end
    end

    if exist == false then
      if credentialinfo.userType == "host" then
        credential_utils.update_remote_control_status(driver, device, true)
      end

      table.insert(credentialInfoTable, credentialinfo)
    end
  end

  if credential_utils.is_exist_host(device) == false then
    credential_utils.update_remote_control_status(driver, device, true)
  end

  device:emit_event(lockCredentialInfo.credentialInfo(credentialInfoTable, { visibility = { displayed = false } }))
  credential_utils.save_data(driver)
end

credential_utils.delete_user = function(driver, device, command)
  local credentialInfoTable = utils.deep_copy(device:get_latest_state("main", lockCredentialInfo.ID,
    lockCredentialInfo.credentialInfo.NAME, {}))
  if #credentialInfoTable == 0 then
    return
  end

  local id = tostring(command.args.userId)

  for i = #credentialInfoTable, 1, -1 do
    if id == credentialInfoTable[i].userId then
      if credentialInfoTable[i].userType == "host" then
        credential_utils.update_remote_control_status(driver, device, false)
      end
      table.remove(credentialInfoTable, i)
    end
  end

  device:emit_event(lockCredentialInfo.credentialInfo(credentialInfoTable, { visibility = { displayed = false } }))
  credential_utils.save_data(driver)
end

credential_utils.delete_credential = function(driver, device, command)
  local credentialInfoTable = utils.deep_copy(device:get_latest_state("main", lockCredentialInfo.ID,
    lockCredentialInfo.credentialInfo.NAME, {}))
  if #credentialInfoTable == 0 then
    return
  end

  for i = #credentialInfoTable, 1, -1 do
    if command.args.credentialId == credentialInfoTable[i].credentialId then
      if credentialInfoTable[i].userType == "host" then
        credential_utils.update_remote_control_status(driver, device, false)
      end
      table.remove(credentialInfoTable, i)
      break
    end
  end

  device:emit_event(lockCredentialInfo.credentialInfo(credentialInfoTable, { visibility = { displayed = false } }))
  credential_utils.save_data(driver)
end

credential_utils.find_userLabel = function(driver, device, value)
  local unlockCredentialId = value & 0xFFFF
  local credentialInfoTable = utils.deep_copy(device:get_latest_state("main", lockCredentialInfo.ID,
    lockCredentialInfo.credentialInfo.NAME, {}))
  for _, credentialInfo in ipairs(credentialInfoTable) do
    if credentialInfo.credentialId == unlockCredentialId then
      return credentialInfo.userId, credentialInfo.userLabel
    end
  end
  return nil, nil
end

credential_utils.is_exist_host = function(device)
  local host_cnt = device:get_field(HOST_COUNT) or 0
  return host_cnt > 0 and true or false
end

credential_utils.set_host_count = function(device, value)
  device:set_field(HOST_COUNT, 0, { persist = true })
end

return credential_utils
