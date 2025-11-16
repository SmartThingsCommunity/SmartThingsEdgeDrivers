--  Copyright 2021 SmartThings
--
--  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
--  except in compliance with the License. You may obtain a copy of the License at:
--
--      http://www.apache.org/licenses/LICENSE-2.0
--
--  Unless required by applicable law or agreed to in writing, software distributed under the
--  License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
--  either express or implied. See the License for the specific language governing permissions
--  and limitations under the License.

local cosock = require "cosock"
local socket = require "cosock.socket"
local log = require "log"
local utils = require "st.utils"

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
      'MX: 2',
      'ST: urn:schemas-upnp-org:device:MediaRenderer:1',
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
  local timeouttime = socket.gettime() + 3 -- 3 second timeout, `MX` + 1 for network delay
  local res, err = sock:sendto(multicast_msg, multicast_ip, multicast_port)
  if res == nil then
    return nil, "udp sendto failure, " .. (err or "")
  end
  return sock, timeouttime
end

local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%w_-]+): *([%g ]*)\r\n") do
    info[string.lower(k)] = v
  end
  return info
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
      elseif err == "timeout" and sock ~= nil then
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
              if id == msg.device_id then
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
        --timeout managed via select
        -- sock:settimeout(timeout)
        if val then
          local headers = process_response(val)
          if headers["location"] ~= nil then
            local ip, port, id = headers["location"]:match(
                                   "http://([^,/]+):([^/]+)/%a+/BO5EBO5E%-F00D%-F00D%-FEED%-([%g-]+).xml")

            if rip ~= ip and ip ~= nil then
              log.warn(string.format(
                         "disco| recieved response with reported (%s) & source IP (%s) mismatch, ignoring",
                         rip, ip))
            elseif ip and id then
              log.trace("disco| found device:", ip, port, id)
              infos_found[id] = {id = id, ip = ip, raw = val}
              number_found = number_found + 1
              for _, search_id in ipairs(search_ids) do
                if search_id.id == "scan" or search_id.id == id then
                  search_id.reply_tx:send(infos_found[id])
                end
              end
            else
              log.debug(string.format("disco| response from %s isnt a bose device: %s", headers["location"], headers["server"]))
            end
          else
            log.warn_with({hub_logs = true},
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
    log.info_with({ hub_logs = true },
      string.format("disco| response window ended, %s found", number_found))
    Discovery._ctrl_tx:close()
    Discovery._ctrl_tx = nil
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
