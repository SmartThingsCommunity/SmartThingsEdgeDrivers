local log = require "log"
local discovery_helper = {}

local SERVICE_TYPE = "_Aqara-FP2._tcp"
local DOMAIN = "local"

local fp2_api = require "fp2.api"
local discovery_mdns = require "discovery_mdns"

function discovery_helper.get_dni(driver, ip, discovery_responses)
  local text_list = discovery_mdns.find_text_list_in_mdns_response(driver, ip, discovery_responses)
  for _, text in ipairs(text_list) do
    for key, value in string.gmatch(text, "(%S+)=(%S+)") do
      if key == "mac" then
        return value
      end
    end
  end

  log.error("discovery_helper.get_dni : failed to find dni")
  return nil
end

function discovery_helper.get_service_type_and_domain()
  return SERVICE_TYPE, DOMAIN
end

function discovery_helper.get_device_create_msg(driver, device_dni, device_ip)
  local device_info = fp2_api.get_info(device_ip, fp2_api.labeled_socket_builder(device_dni))

  if not device_info then
    log.warn("failed to create device create msg. device_info is nil.")
    return nil
  end

  local device_label = device_info.label or "Aqara-FP2"
  if device_dni then
    -- To make it easier to distinguish devices, add the last four letters of dni to the label
    -- for example, if device_info.label is "Aqara-FP2" and device_dni is "00:11:22:33:44:55", then device_label will be "Aqara-FP2 (4455)"
    device_label = string.format("%s (%s)", device_label, string.sub(string.gsub(tostring(device_dni), ":", ""), -4))
  end

  local create_device_msg = {
    type = "LAN",
    device_network_id = device_dni,
    label = device_label,
    profile = "aqara-fp2-zoneDetection",
    manufacturer = device_info.manufacturerName,
    model = device_info.modelName,
    vendor_provided_label = device_info.label,
  }
  return create_device_msg
end

function discovery_helper.get_credential(driver, bridge_dni, bridge_ip)
  local credential = fp2_api.get_credential(bridge_ip, fp2_api.labeled_socket_builder(bridge_dni))

  if not credential then
    log.warn("credential is nil")
    return nil
  end

  return "Bearer " .. credential.token
end

function discovery_helper.get_connection_info(driver, device_dni, device_ip, device_info)
  local conn_info = fp2_api.new_device_manager(device_ip, device_info, fp2_api.labeled_socket_builder(device_dni))

  if conn_info == nil then
    log.warn("conn_info is nil")
  end

  return conn_info
end

function discovery_helper.get_device_info(driver, device_dni, device_ip)
  local device_info = fp2_api.get_info(device_ip, fp2_api.labeled_socket_builder(device_dni))

  if device_info == nil then
    log.warn("device_info is nil")
  end

  return device_info
end

return discovery_helper
