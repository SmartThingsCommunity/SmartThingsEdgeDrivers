local cosock = require "cosock"
local socket = require "cosock.socket"
local http = cosock.asyncify "socket.http"
local ltn12 = require "ltn12"
local log = require "log"
local tablefind = require "util".tablefind
local mac_equal = require "util".mac_equal
local utils = require "st.utils"
local xml2lua = require "xml2lua"
local xml_handler = require "xmlhandler.tree"

local ControlMessageTypes = {
  Scan = "scan",
  FindDevice = "findDevice",
}

local ControlMessageBuilders = {
  Scan = function(reply_tx) return { type = ControlMessageTypes.Scan, reply_tx = reply_tx } end,
  FindDevice = function(device_id, reply_tx)
    return { type = ControlMessageTypes.FindDevice, device_id = device_id, reply_tx = reply_tx }
  end,
}

local Discovery = {}

local function send_disco_request()
  local listen_ip = "0.0.0.0"
  local listen_port = 0
  local multicast_ip = "239.255.255.250"
  local multicast_port = 1900
  local multicast_msg = table.concat(
    {
      'M-SEARCH * HTTP/1.1',
      'HOST: 239.255.255.250:1900',
      'MAN: "ssdp:discover"', -- yes, there are really supposed to be quotes in this one
      'MX: 4',
      'ST: urn:Belkin:device:*',
      '\r\n'
    },
    "\r\n"
  )
  local sock, err = socket.udp()
  if sock == nil then
    return nil, "create udp socket failure, " .. (err or "")
  end
  local res, err = sock:setsockname(listen_ip, listen_port)
  if res == nil then
    return nil, "udp setsockname failure, " .. (err or "")
  end
  local timeouttime = socket.gettime() + 5 -- 5 second timeout, `MX` + 1 for network delay

  local res, err = sock:sendto(multicast_msg, multicast_ip, multicast_port)
  if res == nil then
    return nil, "udp sendto failure, " .. (err or "")
  end
  return sock, timeouttime
end

local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%w_-]+):[ ]*([%g ]*)\r\n") do
    info[string.lower(k)] = v
  end
  return info
end

function Discovery.fetch_device_metadata(url)
  -- Wemo responds with chunked encoding, must use ltn12 sink
  local responsechunks = {}
  local _, status, _ = http.request {
    url = url,
    sink = ltn12.sink.table(responsechunks),
  }

  local response = table.concat(responsechunks)

  -- errors are coming back as literal string "[string "socket"]:1239: closed"
  -- instead of just "closed", so do a `find` for the error
  if string.find(status, "closed") then
    log.debug("disco| ignoring unexpected socket close during metadata fetch, try parsing anyway")
    -- this workaround is required because wemo doesn't send the required zero-length chunk
    -- at the end of it `Text-Encoding: Chunked` HTTP message, it just closes the socket,
    -- so ignore closed errors
  elseif status ~= 200 then
    log.error("disco| metadata request failed (" .. tostring(status) .. ")\n" .. response)
    return nil, "request failed: " .. tostring(status)
  end

  local handler = xml_handler:new()
  local xml_parser = xml2lua.parser(handler)
  local success, err = pcall(xml_parser.parse, xml_parser, response)

  if not handler.root or not success then
    log.error("disco| unable to parse device metadata as xml")
    return nil, "xml parse error: " .. (err or "")
  end

  local parsed_xml = handler.root

  -- check if we parsed a <root> element
  if not parsed_xml.root then
    log.error("disco| parsed metadata does not contain a root element")
    return nil
  end

  return {
    name = tablefind(parsed_xml, "root.device.friendlyName"),
    model = tablefind(parsed_xml, "root.device.modelName"),
    mac = tablefind(parsed_xml, "root.device.macAddress"),
    serial_num = tablefind(parsed_xml, "root.device.serialNumber"),
  }
end

function Discovery.run_discovery_task()
  local ctrl_tx, ctrl_rx = cosock.channel.new()
  Discovery._ctrl_tx = ctrl_tx

  local sock
  local search_ids = {}
  local infos_found = {} -- used to filter duplicates
  local number_found = 0
  local timeout = 1 --give controllers 1 second initially to send multiple requests
  local timeout_epoch
  cosock.spawn(function()
    while true do
      local recv, _, err = socket.select({ ctrl_rx, sock }, nil, timeout)
      if err == "timeout" and sock == nil then
        log.trace("disco| done waiting for search ids, sending ssdp discovery message")
        if sock == nil and #search_ids > 0 then
          sock, timeout_epoch = send_disco_request()
          if sock == nil then
            log.error_with({hub_logs = true}, string.format("disco| ending due to socket error: %s", timeout_epoch))
            break
          end
          timeout = math.max(0, timeout_epoch - socket.gettime())
        else
          log.warn("disco| ending without sending request because no search ids requested")
          break
        end
      elseif err == "timeout" and socket ~= nil then
        break
      end

      --Handle the ctrl channel messages first
      if recv and (recv[1] == ctrl_rx or recv[2] == ctrl_rx) then
        local msg, err = ctrl_rx:receive()
        if msg and msg.type and msg.reply_tx then
          if msg.type == ControlMessageTypes.Scan then
            log.trace("disco| inserting search id:", "scan")
            table.insert(search_ids, { id = "scan", reply_tx = msg.reply_tx })
          end
          if msg.type == ControlMessageTypes.FindDevice then
            log.trace("disco| inserting search id:", msg.device_id)
            table.insert(search_ids, { id = msg.device_id, reply_tx = msg.reply_tx })
            for id, info in pairs(infos_found) do
              if mac_equal(id, msg.device_id) then
                log.trace("disco| searching for previously discovered device:", msg.device_id)
                msg.reply_tx:send(info)
              end
            end
          end
        else
          log.warn(utils.stringify_table(msg or err, "Unexpected Message/Err on Discovery Control Channel", false))
        end

        goto continue
      end

      if recv and (recv[1] == sock or recv[2] == sock) then
        local val, rip, _ = sock:receivefrom()
        timeout = math.max(0, timeout_epoch - socket.gettime())
        -- sock:settimeout(timeout)
        if val then
          local headers = process_response(val)
          if headers["location"] ~= nil then
            local ip, port = headers["location"]:match("http://([^,/]+):([^/]+)")
            if rip ~= ip then
              log.warn("recieved discovery response with reported & source IP mismatch, ignoring")
              log.debug(rip, "!=", ip)
              goto continue
            end
            local meta = Discovery.fetch_device_metadata(headers["location"])
            if not meta or not meta.mac or not ip then
              log.warn(string.format("disco| failed to get ip(%s) or mac(%s) for discovered device, not adding", ip, meta and meta.mac))
              goto continue
            end
            local id = meta.mac

            if ip and port and id and not infos_found[id] then
              infos_found[id] = {
                id = id,
                ip = ip,
                port = port,
                raw = headers,
                name = meta.name,
                model = meta.model,
                serial_num = meta.serial_num,
              }
              number_found = number_found + 1
              log.trace("disco| found device:", ip, port, id)
              for _, search_id in ipairs(search_ids) do
                if search_id.id == "scan" or mac_equal(search_id.id, id) then
                  search_id.reply_tx:send(infos_found[id])
                end
              end
            end
          else
            log.warn_with({ hub_logs = true },
              string.format("disco| response from %s doesn't contain a location header: %s", rip, val))
          end
        else
          error(string.format("error receving discovery replies: %s", rip))
        end
      end
      ::continue::
    end
    for _, search_id in ipairs(search_ids) do
      if search_id.id == "scan" or infos_found[search_id.id] == nil then
        search_id.reply_tx:close()
      end
    end
    if sock then sock:close() end
    if ctrl_rx then ctrl_rx:close() end
    Discovery._ctrl_tx:close()
    Discovery._ctrl_tx = nil
    log.info_with({ hub_logs = true }, string.format("disco| response window ended, %s found", number_found))

    --prepare return values for requested scan ids

  end, "disco task")
end

--This function should only be sending on tx ctrl channel
-- to discovery task to add a deviceID to the disco search
function Discovery.find(deviceid, callback)
  if Discovery._ctrl_tx == nil then
    log.trace("disco| starting discovery cosock task")
    Discovery.run_discovery_task()
  end

  local tx, rx = cosock.channel.new()
  if deviceid then
    Discovery._ctrl_tx:send(ControlMessageBuilders.FindDevice(deviceid, tx))
    local info = rx:receive()
    if not info then
      log.warn("disco| failed to discover the device " .. deviceid)
    end
    callback(info)
    rx:close()
  else
    Discovery._ctrl_tx:send(ControlMessageBuilders.Scan(tx))
    while true do
      local info, err = rx:receive()
      if err == "closed" then
        log.trace("disco| finished scan")
        rx:close()
        break
      end
      if info ~= nil and info.ip ~= nil and info.id ~= nil then
        callback(info)
      else
        log.warn(string.format("disco| unexpected nil info due to %s", err))
      end
    end
  end
end

return Discovery
