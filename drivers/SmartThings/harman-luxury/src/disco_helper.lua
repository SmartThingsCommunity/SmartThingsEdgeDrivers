local log = require "log"
local net_utils = require "st.net_utils"
local const = require "constants"

local Disco_Helper = {}

local function byte_array_to_plain_text(byte_array)
  local str = ""
  for _, value in pairs(byte_array) do
    str = str .. string.char(value)
  end
  return str
end

local function get_hostname_by_ip(ip, discovery_responses)
  for _, answer_item in pairs(discovery_responses.answers or {}) do
    if answer_item.kind.ARecord ~= nil and answer_item.kind.ARecord.ipv4 == ip then
      return answer_item.name
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

local function get_text_by_srvname(srvname, discovery_responses)
  for _, answer_item in pairs(discovery_responses.answers or {}) do
    if answer_item.kind.TxtRecord ~= nil and answer_item.name == srvname then
      return answer_item.kind.TxtRecord.text
    end
  end
end

local function find_text_in_answers_by_ip(ip, discovery_responses)
  local hostname = get_hostname_by_ip(ip, discovery_responses)
  local srvname = get_srvname_by_hostname(hostname, discovery_responses)
  local text = get_text_by_srvname(srvname, discovery_responses)

  return text
end

local function find_text_list_in_mdns_response(ip, discovery_responses)
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

local function get_parameters(ip, discovery_responses)
  local params = {
    [const.DNI] = "",
    [const.MNID] = "",
    [const.SETUP_ID] = "",
  }
  local text_list = find_text_list_in_mdns_response(ip, discovery_responses)
  for _, text in ipairs(text_list) do
    for key, value in string.gmatch(text, "(%S+)=(%S+)") do
      if key == const.MAC then
        local dni = value:gsub("-", ""):gsub(":", ""):lower()
        log.info(string.format("get_parameters : use mac as dni. mac = %s | dni = %s", value, dni))
        params[const.DNI] = dni
      end
      if key == const.MNID then
        log.info(string.format("get_parameters : mnid = %s", value))
        params[const.MNID] = value
      elseif key == const.SETUP_ID then
        log.info(string.format("get_parameters : setupid = %s", value))
        params[const.SETUP_ID] = value
      end
    end
  end

  if params[const.DNI] == nil then
    log.error("get_parameters : failed to find dni")
    return nil
  else
    return params
  end
end

local function insert_dni_ip_from_answers(filtered_responses, target_table)
  for _, answer in pairs(filtered_responses.answers) do
    local ip

    if answer.kind.ARecord ~= nil then
      ip = answer.kind.ARecord.ipv4
    end

    if ip ~= nil then
      local params = get_parameters(ip, filtered_responses)

      if params ~= nil then
        log.info(string.format("answer_name, arecod = %s, %s", answer.name, answer.kind.ARecord))
        local dni = params[const.DNI]
        local mnid = params[const.MNID]
        local setupid = params[const.SETUP_ID]
        target_table[dni] = {
          ip = ip,
          mnid = mnid,
          setupid = setupid,
        }
      end
    end
  end
end

local function filter_response_by_service_name(service_type, discovery_responses)
  local filtered_responses = {
    found = {},
    answers = {},
  }

  for _, found in pairs(discovery_responses.found or {}) do
    if found.service_info.service_type == service_type then
      table.insert(filtered_responses.found, found)
    end
  end

  for _, answer in pairs(discovery_responses.answers or {}) do
    table.insert(filtered_responses.answers, answer)
  end

  for _, additional in pairs(discovery_responses.additional or {}) do
    table.insert(filtered_responses.answers, additional)
  end

  return filtered_responses
end

local function insert_dni_ip_from_found(filtered_responses, target_table)
  for _, found in pairs(filtered_responses.found) do
    local ip
    log.info(string.format("found_name = %s", tostring(found.service_info.service_type)))
    if found.host_info.address ~= nil and net_utils.validate_ipv4_string(found.host_info.address) then
      ip = found.host_info.address
      log.info(string.format("ip = %s", ip))
    end

    if ip ~= nil then
      local params = get_parameters(ip, filtered_responses)

      if params ~= nil then
        local dni = params[const.DNI]
        local mnid = params[const.MNID]
        local setupid = params[const.SETUP_ID]
        target_table[dni] = {
          ip = ip,
          mnid = mnid,
          setupid = setupid,
        }
      end
    end
  end
end

function Disco_Helper.get_dni_ip_table_from_mdns_responses(service_type, discovery_responses)
  local dni_ip_table = {}

  local filtered_responses = filter_response_by_service_name(service_type, discovery_responses)

  insert_dni_ip_from_found(filtered_responses, dni_ip_table)
  insert_dni_ip_from_answers(filtered_responses, dni_ip_table)

  return dni_ip_table
end

return Disco_Helper
