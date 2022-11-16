local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require "socket.ltn12"
local log = require "log"
local tablefind = require "util".tablefind
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%g]+): ([%g ]*)\r\n") do
    info[string.lower(k)] = v
  end
  return info
end

local function fetch_device_metadata(url)
  -- Wemo responds with chunked encoding, must use ltn12 sink
  local responsechunks = {}
  local body,status,headers = http.request{
    url = url,
    sink = ltn12.sink.table(responsechunks),
  }

  local response = table.concat(responsechunks)

  log.trace("metadata response status", body, status, headers)

  -- vvvvvvvvvvvvvvvv TODO: errors are coming back as literal string "[string "socket"]:1239: closed"
  -- instead of just "closed", so do a `find` for the error
  if string.find(status, "closed") then
  -- ^^^^^^^^^^^^^^^^
    log.debug("socket closed unexpectedly, this is usually due to bug in wemo's server, try parsing anyway")
    -- this workaround is required because wemo doesn't send the required zero-length chunk
    -- at the end of it `Text-Encoding: Chunked` HTTP message, it just closes the socket,
    -- so ignore closed errors
  elseif status ~= 200 then
    log.error("metadata request failed ("..tostring(status)..")\n"..response)
    return nil, "request failed: "..tostring(status)
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  xml_parser:parse(response)

  if not handler.root then
    log.error("unable to parse device metadata as xml")
    return nil, "xml parse error"
  end

  local parsed_xml = handler.root

  -- check if we parsed a <root> element
  if not parsed_xml.root then
    return nil
  end

  return {
    name = tablefind(parsed_xml, "root.device.friendlyName"),
    model = tablefind(parsed_xml, "root.device.modelName")
  }
end

local function find(deviceid, callback)
  log.info("making discovery request", deviceid)

  local s = assert(socket.udp(), "create discovery socket")

  local listen_ip = "0.0.0.0"
  local listen_port = 0

  local multicast_ip = "239.255.255.250"
  local multicast_port = 1900
  local multicast_msg = table.concat(
    {
      'M-SEARCH * HTTP/1.1',
      'HOST: 239.255.255.250:1900',
      'MAN: "ssdp:discover"', -- yes, there are really supposed to be quotes in this one
      'MX: 2',
      'ST: ' .. (deviceid or 'urn:Belkin:device:*'),
      '\r\n'
    },
    "\r\n"
  )

  log.trace("discovery request:\n"..multicast_msg)

  -- bind local ip and port
  -- device will unicast back to this ip and port
  assert(s:setsockname(listen_ip, listen_port), "discovery socket setsockname")
  local timeouttime = socket.gettime() + 3 -- 3 second timeout, `MX` + 1 for network delay

  local ids_found = {} -- used to filter duplicates
  local number_found = 0

  assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
  while true do
    local time_remaining = math.max(0, timeouttime-socket.gettime())
    s:settimeout(time_remaining)
    local val, rip, _ = s:receivefrom()
    if val then
      local headers = process_response(val)
      local ip, port = headers["location"]:match("http://([^,/]+):([^/]+)")
      local id = headers["usn"]

      log.trace("discovery response from:", rip, headers["usn"])

      if rip ~= ip then
        log.warn("recieved discovery response with reported & source IP mismatch, ignoring")
        log.debug(rip, "!=", ip)
      elseif ip and port and id and not ids_found[id] then
        ids_found[id] = true
        number_found = number_found + 1

        local meta = fetch_device_metadata(headers["location"])

        if not meta then
          meta = {}
        end

	-- the ID in the response is a substring of the search ID, check if they match (if search ID set)
	local is_correct_responder = deviceid and string.find(deviceid, id, nil, "plaintext")

	if (not deviceid) or is_correct_responder then
          callback({id = id,
                    ip = ip,
                    port = port,
                    raw = headers,
                    name = meta.name,
                    model = meta.model
                    })

          if deviceid then
            -- just looking for a single device
            break
          end
        end
      end
    elseif rip == "timeout" then
      break
    else
      error(string.format("error receving discovery replies: %s", rip))
    end
  end
  s:close()
  log.info(string.format("discovery response window ended, %s found", number_found))
end

return {
  find = find,
}
