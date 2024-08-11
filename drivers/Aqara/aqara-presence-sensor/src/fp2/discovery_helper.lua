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
    log.error(string.format("failed to create device create msg. device_info is nil."))
    return nil
  end

  local create_device_msg = {
    type = "LAN",
    device_network_id = device_dni,
    label = device_info.label,
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
    log.error("credential is nil")
    return nil
  end

  return "Bearer " .. credential.token
end

function discovery_helper.get_connection_info(driver, device_dni, device_ip, device_info)
  local conn_info = fp2_api.new_device_manager(device_ip, device_info, fp2_api.labeled_socket_builder(device_dni))

  if conn_info == nil then
    log.error("conn_info is nil")
  end

  return conn_info
end

function discovery_helper.get_device_info(driver, device_dni, device_ip)
  local device_info = fp2_api.get_info(device_ip, fp2_api.labeled_socket_builder(device_dni))

  if device_info == nil then
    log.error("device_info is nil")
  end

  return device_info
end

return discovery_helper
