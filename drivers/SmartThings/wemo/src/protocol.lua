local parser = require "parser"
local log = require "log"

local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require "socket.ltn12"

local utils = require "st.utils"

local protocol = {}

-- map subscription IDs to device handles
local subscriptions = {}

local request_wrapper = [[<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    %s
  </s:Body>
</s:Envelope>]]

local function get_ip_and_port(device)
    local ip = device:get_field("ip")
    if not ip then log.warn("device ip is not yet known") end

    local port = device:get_field("port")
    if not port then log.warn("device port is not known") end

    return ip, port
end

local function find_interface_ip_for_remote(ip)
  local s = socket:udp()
  s:setpeername(ip, 9) -- port unimportant, use "discard" protocol port for lack of anything better
  local localip, _, _ = s:getsockname()
  s:close()

  return localip
end

-- listen socket channel handler
-- first parameter is driver, which we don't need
function protocol.accept_handler(_, listen_sock)
    local client, accept_err = listen_sock:accept()

    log.trace("accept connection from", client:getpeername())

    if accept_err ~= nil then
        log.info("Hit accept error: " .. accept_err)
        listen_sock:close()
        return
    end

    client:settimeout(1)

    local ip, _, _ = client:getpeername()
    if ip ~= nil then
        do -- Read first line and verify it matches the expect request-line with NOTIFY method type
            local line, err = client:receive()
            if err == nil then
                if line ~= "NOTIFY / HTTP/1.1" then
                    log.warn("Received unexpected " .. line)
                    client:close()
                    return
                end
            else
                log.warn("Hit error on client receive: " .. err)
                client:close()
                return
            end
        end

        local content_length = 0
        local subscriptionid = 0
        do -- Receive all headers until blank line is found, saving off content-length
            local line, err = client:receive()
            if err then
                log.warn("Hit error on client receive: " .. err)
                client:close()
                return
            end

            while line ~= "" do
                local name, value = socket.skip(2, line:find("^(.-):%s*(.*)"))
                if not (name and value) then
                    log.warn("Received malformed response headers")
                    client:close()
                    return
                end

                if string.lower(name) == "content-length" then
                    content_length = tonumber(value)
                end

                if string.lower(name) == "sid" then
                    subscriptionid = value
                end

                line, err  = client:receive()
                if err ~= nil then
                    log.warn("error while receiving headers: " .. err)
                    return
                end
            end

            if content_length == nil or content_length <= 0 then
                log.warn("Failed to parse content-length from headers")
                return
            end
        end


        do -- receive `content_length` bytes as body
            local body = ""
            while #body < content_length do
                local bytes_remaining = content_length - #body
                local recv, err = client:receive(bytes_remaining)
                if err == nil then
                    body = body .. recv
                else
                    log.warn("error while receiving body: " .. err)
                    break
                end
            end

            local device = subscriptions[subscriptionid]
            if not device then
                log.error("received subscription event for unknown subscription", subscriptionid)
                client:close()
                return
            end


            if body ~= nil then
                parser.parse_subscription_resp_xml(device, body)

                -- For now always return 200 OK if we received a request, regardless of potential parsing failures.
                -- Consider returning error code if parsing fails.
                local resp = "HTTP/1.1 200 OK\r\n\r\n";
                client:send(resp);
            else
                log.warn("Received no HTTP body on accepted socket")
            end
        end

        client:close()
    else
        log.warn("Could not get IP from getpeername()")
    end
end

function protocol.poll(_, device)
    local ip, port = get_ip_and_port(device)
    log.debug("protocol.poll() ip is = ", ip)
    log.debug("protocol.poll() port is = ", port)
    if not (ip and port) then
        return
    end

    local reqbody = string.format(request_wrapper,
        [[<u:GetBinaryState xmlns:u="urn:Belkin:service:basicevent:1"></u:GetBinaryState>]]
    )

    local response_chunks = {}

    local resp, code_or_err, _, status_line = http.request {
        url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
        method = "POST",
        sink = ltn12.sink.table(response_chunks),
        source = ltn12.source.string(reqbody),
        headers = {
            ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#GetBinaryState"]],
            ["Content-Type"] = "text/xml",
            ["Host"] =  ip .. ":" .. port,
            ["Content-Length"] = #reqbody
        }
    }

    -- TODO: some retries needed here to get device health if we timeout

    if resp == nil then
        log.warn("Error sending http request: " .. code_or_err)
        
	-- retry
	resp, code_or_err, _, status_line = http.request {
        url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
        method = "POST",
        sink = ltn12.sink.table(response_chunks),
        source = ltn12.source.string(reqbody),
        headers = {
            ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#GetBinaryState"]],
            ["Content-Type"] = "text/xml",
            ["Host"] =  ip .. ":" .. port,
            ["Content-Length"] = #reqbody
            }
        }

        if resp == nil then
           log.warn("Error sending http request: " .. code_or_err)
	   device:offline() -- Mark device as being unavailable/offline
           return
        end
    end

    device:online() -- Mark device as being online

    if code_or_err ~= 200 then
        log.warn("received " .. code_or_err .. " http status response :" .. status_line)
    else
        local resp_body = table.concat(response_chunks)
        parser.parse_get_state_resp_xml(device, resp_body)
    end
end

function protocol.subscribe(server, device)
    local ip, port = get_ip_and_port(device)
    if not (ip and port) then
        return
    end

    local device_facing_local_ip = find_interface_ip_for_remote(ip)

    if server.listen_ip == nil or server.listen_port == nil then
        log.info("failed to subscribe, no listen server")
        return
    end

    log.debug("subscribing", "<http://" .. device_facing_local_ip .. ":" .. server.listen_port .. "/>")

    local response_body = {}

    local resp, code_or_err, headers, status_line = http.request {
        url = "http://" .. ip .. ":" .. port .. "/upnp/event/basicevent1",
        method = "SUBSCRIBE",
        sink = ltn12.sink.table(response_body),
        headers = {
            ["HOST"] =  ip .. ":" .. port,
            ["CALLBACK"] = "<http://" .. device_facing_local_ip .. ":" .. server.listen_port .. "/>",
            ["NT"] = "upnp:event",
            ["TIMEOUT"] = "Second-5400",
        }
    }

    if resp == nil then
        log.warn("error sending http request: " .. code_or_err)
        return
    end

    if code_or_err ~= 200 then
        log.warn("subcribe failed with error code " .. code_or_err .. " and status: " .. status_line)
        return
    end

    local sid = headers["sid"]
    if sid ~= nil then
        if device:get_field("sid") ~= sid then
            device:set_field("sid", sid)
            subscriptions[sid] = device
	    log.info("["..device.id.."] setup subscription: "..tostring(sid))
        end
    else
        log.warn("no SID header in subscription response")
    end
end

function protocol.unsubscribe(device)
    local ip, port = get_ip_and_port(device)
    if not (ip and port) then
        return
    end

    log.info("Unsubscribing")

    local sid = device:get_field("sid")
    if sid == nil then
        return
    else
        subscriptions[sid] = nil
    end


    local response_body = {}

    local resp, code_or_err, _, status_line = http.request {
        url = "http://" .. ip .. ":" .. port .. "/upnp/event/basicevent1",
        method = "UNSUBSCRIBE",
        sink = ltn12.sink.table(response_body),
        headers = {
            ["HOST"] =  ip .. ":" .. port,
            ["SID"] = sid,
        }
    }

    if resp == nil then
        log.warn("Error sending http request: " .. code_or_err)
        return
    end

    if code_or_err ~= 200 then
        log.warn("Unsubcribe failed with error code " .. code_or_err .. " and status: " .. status_line)
    end
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

    log.trace("make request")
    local resp, code_or_err, _, status_line = http.request {
        url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
        method = "POST",
        sink = ltn12.sink.table(response_body),
        source = ltn12.source.string(body),
        headers = {
            ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#SetBinaryState"]],
            ["Content-Type"] = "text/xml",
            ["Host"] =  ip .. ":" .. port,
            ["Content-Length"] = #body
        }
    }
    log.trace("got response", code_or_err, status_line)

    if resp == nil then
        log.warn("Error sending http request: " .. code_or_err)
        return
    end

    if code_or_err ~= 200 then
        log.warn("Switch command failed with error code " .. code_or_err .. " and status: " .. status_line)
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

    local resp, code_or_err, _, status_line = http.request {
        url = "http://" .. ip .. ":" .. port .. "/upnp/control/basicevent1",
        method = "POST",
        sink = ltn12.sink.table(response_body),
        source = ltn12.source.string(body),
        headers = {
            ["SOAPAction"] = [["urn:Belkin:service:basicevent:1#SetBinaryState"]],
            ["Content-Type"] = "text/xml",
            ["Host"] =  ip .. ":" .. port,
            ["Content-Length"] = #body
        }
    }

    if resp == nil then
        log.warn("Error sending http request: " .. code_or_err)
        return
    end

    if code_or_err ~= 200 then
        log.warn("Switch level command failed with error code " .. code_or_err .. " and status: " .. status_line)
    end
end

return protocol
