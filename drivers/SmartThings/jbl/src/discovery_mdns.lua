local log = require "log"
local mdns = require "st.mdns"
local net_utils = require "st.net_utils"
local st_utils = require "st.utils"

local discovery_mdns = {}

local function byte_array_to_plain_text(byte_array)
  return string.char(table.unpack(byte_array))
end

local function get_text_by_srvname(srvname, discovery_responses)
  for _, answer_item in pairs(discovery_responses.answers or {}) do
    if answer_item.kind.TxtRecord ~= nil and answer_item.name == srvname then
      return answer_item.kind.TxtRecord.text
    end
  end
end

local function get_srvname_by_hostname(hostname, discovery_responses)
  for _, answer_item in pairs(discovery_responses.answers or {}) do
    if answer_item.kind.SrvRecord ~= nil and answer_item.kind.SrvRecord.target == hostname then
      return answer_item.name
    end
  end
end

local function get_hostname_by_ip(ip, discovery_responses)
  for _, answer_item in pairs(discovery_responses.answers or {}) do
    if answer_item.kind.ARecord ~= nil and answer_item.kind.ARecord.ipv4 == ip then
      return answer_item.name
    end
  end
end

local function find_text_in_answers_by_ip(ip, discovery_responses)
  local hostname = get_hostname_by_ip(ip, discovery_responses)
  local srvname = get_srvname_by_hostname(hostname, discovery_responses)
  local text = get_text_by_srvname(srvname, discovery_responses)

  return text
end

function discovery_mdns.find_text_list_in_mdns_response(driver, ip, discovery_responses)
  local text_list = {}

  for _, found_item in pairs(discovery_responses.found or {}) do
    if found_item.host_info.address == ip then
      for _, raw_text_array in pairs(found_item.txt.text or {}) do
        local text_item = byte_array_to_plain_text(raw_text_array)
        table.insert(text_list, text_item)
      end
    end
  end

  local answer_text = find_text_in_answers_by_ip(ip, discovery_responses)
  for _, text_item in pairs(answer_text or {}) do
    table.insert(text_list, text_item)
  end
  return text_list
end

local function filter_response_by_service_name(service_type, domain, discovery_responses)
  local filtered_responses = {
    answers = {},
    found = {}
  }

  for _, answer in pairs(discovery_responses.answers or {}) do
    table.insert(filtered_responses.answers, answer)
  end

  for _, additional in pairs(discovery_responses.additional or {}) do
    table.insert(filtered_responses.answers, additional)
  end

  for _, found in pairs(discovery_responses.found or {}) do
    if found.service_info.service_type == service_type then
      table.insert(filtered_responses.found, found)
    end
  end

  return filtered_responses
end

local function insert_dni_ip_from_answers(driver, filtered_responses, target_table)
  for _, answer in pairs(filtered_responses.answers) do
    local dni, ip
    log.info("answer_name, arecod = " .. tostring(answer.name) .. ", " .. tostring(answer.kind.ARecord))

    if answer.kind.ARecord ~= nil then
      ip = answer.kind.ARecord.ipv4
    end

    if ip ~= nil then
      dni = driver.discovery_helper.get_dni(driver, ip, filtered_responses)

      if dni ~= nil then
        target_table[dni] = ip
      end
    end
  end
end

local function insert_dni_ip_from_found(driver, filtered_responses, target_table)
  for _, found in pairs(filtered_responses.found) do
    local dni, ip
    log.info("found_name = " .. tostring(found.service_info.service_type))
    if found.host_info.address ~= nil and net_utils.validate_ipv4_string(found.host_info.address) then
      log.info("ip = " .. tostring(found.host_info.address))
      ip = found.host_info.address
    end

    if ip ~= nil then
      dni = driver.discovery_helper.get_dni(driver, ip, filtered_responses)

      if dni ~= nil then
        target_table[dni] = ip
      end
    end
  end
end

local function get_dni_ip_table_from_mdns_responses(driver, service_type, domain, discovery_responses)
  local dni_ip_table = {}

  local filtered_responses = filter_response_by_service_name(service_type, domain, discovery_responses)

  log.debug(st_utils.stringify_table(filtered_responses, "[get_dni_ip_table(...)] Filtered Responses", true))

  insert_dni_ip_from_answers(driver, filtered_responses, dni_ip_table)
  insert_dni_ip_from_found(driver, filtered_responses, dni_ip_table)

  return dni_ip_table
end

function discovery_mdns.find_ip_table_by_mdns(driver)
  log.info("discovery_mdns.find_device_ips")

  local service_type, domain = driver.discovery_helper.get_service_type_and_domain()
  local discovery_responses = mdns.discover(service_type, domain) or { found = {} }

  log.debug(st_utils.stringify_table(discovery_responses, "Raw mDNS Discovery Response", true))

  local dni_ip_table = get_dni_ip_table_from_mdns_responses(driver, service_type, domain, discovery_responses)

  return dni_ip_table
end

return discovery_mdns
