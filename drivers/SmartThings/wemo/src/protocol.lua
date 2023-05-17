local parser = require "parser"
local log = require "log"

local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"

local protocol = {}

local request_wrapper = [[<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    %s
  </s:Body>
</s:Envelope>]]

local function get_ip_and_port(device)
  local ip = device:get_field("ip")
  if not ip then log.warn("proto| device ip is not yet known") end

  local port = device:get_field("port")
  if not port then log.warn("proto| device port is not known") end

  return ip, port
end

--TODO this info should be present in driver.environment_info.hub_ipv4
local function find_interface_ip_for_remote(ip)
  local s = socket:udp()
  s:setpeername(ip, 9) -- port unimportant, use "discard" protocol port for lack of anything better
  local localip, _, _ = s:getsockname()
  s:close()

  return localip
end

function protocol.poll(device)
  local ip, port = get_ip_and_port(device)
  log.debug(string.format("proto| polling %s at %s:%s", device.label, ip, port))
  if not (ip and port) then
    return
  end

  local reqbody = string.format(request_wrapper,
    [[<u:GetBinaryState xmlns:u="urn:Belkin:service:basicevent:1"></u:GetBinaryState>]]
  )

  local response_chunks = {}

  --TODO use luncheon
  local resp, code_or_err, _, status_line = http.request {
    url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
    method = "POST",
    sink = ltn12.sink.table(response_chunks),
    source = ltn12.source.string(reqbody),
    headers = {
      ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#GetBinaryState"]],
      ["Content-Type"] = "text/xml",
      ["Host"] = ip .. ":" .. port,
      ["Content-Length"] = #reqbody
    }
  }

  -- TODO: some retries needed here to get device health if we timeout

  if resp == nil then
    log.warn_with({hub_logs=true},
      string.format("proto| retry sending poll request for %s: %s", device.label, code_or_err))

    -- retry
    resp, code_or_err, _, status_line = http.request {
      url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
      method = "POST",
      sink = ltn12.sink.table(response_chunks),
      source = ltn12.source.string(reqbody),
      headers = {
        ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#GetBinaryState"]],
        ["Content-Type"] = "text/xml",
        ["Host"] = ip .. ":" .. port,
        ["Content-Length"] = #reqbody
      }
    }

    if resp == nil then
      log.warn_with({hub_logs=true},
        string.format("proto| Failed to send poll request to %s: %s", device.label, code_or_err))
      device:offline()
      return
    end
  end

  device:online()

  if code_or_err ~= 200 then
    log.warn(string.format("proto| poll to %s failed with error code %s and status: %s", device.label, code_or_err, status_line))
  else
    local resp_body = table.concat(response_chunks)
    parser.parse_get_state_resp_xml(device, resp_body)
  end
end

function protocol.subscribe(device, listen_ip, listen_port)
  local ip, port = get_ip_and_port(device)
  if not (ip and port) then
    return
  end

  local device_facing_local_ip = find_interface_ip_for_remote(ip)

  local response_body = {}
  local resp, code_or_err, headers, status_line = http.request {
    url = "http://" .. ip .. ":" .. port .. "/upnp/event/basicevent1",
    method = "SUBSCRIBE",
    sink = ltn12.sink.table(response_body),
    headers = {
      ["HOST"] = ip .. ":" .. port,
      ["CALLBACK"] = "<http://" .. device_facing_local_ip .. ":" .. listen_port .. "/>",
      ["NT"] = "upnp:event",
      ["TIMEOUT"] = "Second-5400",
    }
  }

  if resp == nil then
    log.warn_with({hub_logs=true}, string.format("proto| error sending subscribe request to %s: %s", device.label, code_or_err))
    return
  end

  if code_or_err ~= 200 then
    log.warn_with({hub_logs=true},
      string.format("proto| subscribe request to %s failed with error code %s and status: %s", device.label, code_or_err, status_line))
    return
  end

  return headers["sid"]
end

function protocol.unsubscribe(device, sid)
  local ip, port = get_ip_and_port(device)
  if not (ip and port) then
    return
  end

  local response_body = {}
  local resp, code_or_err, _, status_line = http.request {
    url = "http://" .. ip .. ":" .. port .. "/upnp/event/basicevent1",
    method = "UNSUBSCRIBE",
    sink = ltn12.sink.table(response_body),
    headers = {
      ["HOST"] = ip .. ":" .. port,
      ["SID"] = sid,
    }
  }

  if resp == nil then
    log.warn_with({hub_logs=true}, string.format("proto| error sending unsubscribe request to %s: %s", device.label, code_or_err))
    return false
  end

  if code_or_err ~= 200 then
    log.warn_with({hub_logs=true},
      string.format("proto| subscribe request to %s failed with error code %s and status: %s", device.label, code_or_err, status_line))
    return false
  end
  return true
end

function protocol.send_switch_cmd(device, power)
  local ip, port = get_ip_and_port(device)
  if not (ip and port) then
    return
  end

  local body = string.format(request_wrapper,
    [[<m:SetBinaryState xmlns:m="urn:Belkin:service:basicevent:1"><BinaryState>]] ..
    (power and 1 or 0) ..
    [[</BinaryState></m:SetBinaryState>]]
  )

  local response_body = {}

  log.trace(string.format("proto| %s set_switch_state %s", device.label, (power and 1 or 0)))
  local resp, code_or_err, _, status_line = http.request {
    url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
    method = "POST",
    sink = ltn12.sink.table(response_body),
    source = ltn12.source.string(body),
    headers = {
      ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#SetBinaryState"]],
      ["Content-Type"] = "text/xml",
      ["Host"] = ip .. ":" .. port,
      ["Content-Length"] = #body
    }
  }

  if resp == nil or code_or_err ~= 200 then
    log.warn_with({ hub_logs = true }, string.format(
      "proto| %s set_switch_state failed with error code %s and status: %s",
      device.label, code_or_err, status_line
    ))
  end
end

function protocol.send_switch_level_cmd(device, level)
  local ip, port = get_ip_and_port(device)
  if not (ip and port) then
    return
  end

  local body = string.format(request_wrapper,
    [[<m:SetBinaryState xmlns:m="urn:Belkin:service:basicevent:1"><brightness>]] ..
    level ..
    [[</brightness></m:SetBinaryState>]]
  )

  local response_body = {}
  log.trace(string.format("proto| %s set_switch_level %s", device.label, level))
  local resp, code_or_err, _, status_line = http.request {
    url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
    method = "POST",
    sink = ltn12.sink.table(response_body),
    source = ltn12.source.string(body),
    headers = {
      ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#SetBinaryState"]],
      ["Content-Type"] = "text/xml",
      ["Host"] = ip .. ":" .. port,
      ["Content-Length"] = #body
    }
  }

  if resp == nil or code_or_err ~= 200 then
    log.warn_with({ hub_logs = true }, string.format(
      "proto| %s set_switch_level failed with error code %s and status: %s",
      device.label, code_or_err, status_line
    ))
  end
end

return protocol
