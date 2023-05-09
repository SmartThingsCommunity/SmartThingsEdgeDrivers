local socket = require "cosock.socket"
local log = require "log"
local st_utils = require "st.utils"

SONOS_SSDP_SEARCH_TERM = "urn:smartspeaker-audio:service:SpeakerGroup:1"

--- @module 'sonos.SSDP'
local SSDP = {}

local function process_response(val)
  local info = {}
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)
  for k, v in string.gmatch(val, "([%g]+): ([%g ]*)\r\n") do
    info[string.lower(k)] = v
  end
  return info
end

function SSDP.search(search_term, callback)
  local s = assert(socket.udp(), "create discovery socket")

  local listen_ip = "0.0.0.0"
  local listen_port = 0

  local multicast_ip = "239.255.255.250"
  local multicast_port = 1900
  local multicast_msg = table.concat({
    "M-SEARCH * HTTP/1.1", "HOST: 239.255.255.250:1900",
    "MAN: \"ssdp:discover\"", -- yes, there are really supposed to be quotes in this one
    "MX: 2", "ST: " .. search_term, "\r\n"
  }, "\r\n")

  -- bind local ip and port
  -- device will unicast back to this ip and port
  assert(s:setsockname(listen_ip, listen_port), "discovery socket setsockname")
  local timeouttime = socket.gettime() + 3 -- 3 second timeout, `MX` + 1 for network delay

  -- local deviceid = "placeholder"

  log.debug("sending discovery multicast request")
  assert(s:sendto(multicast_msg, multicast_ip, multicast_port))
  while true do
    local time_remaining = math.max(0, timeouttime - socket.gettime())
    s:settimeout(time_remaining)
    local val, rip, _ = s:receivefrom()

    if val then
      local headers = process_response(val)

      if headers["st"] == search_term and headers["server"]:find("Sonos") then
        local ip =
        headers["location"]:match("http://([^,/]+):[^/]+/.+%.xml")

        local is_group_coordinator, group_id, group_name =
        headers["groupinfo.smartspeaker.audio"]:match("gc=(.*); gid=(.*); gname=\"(.*)\"")

        local household_id = headers["household.smartspeaker.audio"]
        local wss_url = headers["websock.smartspeaker.audio"]

        local group_info = {
          ip = ip,
          is_group_coordinator = (tonumber(is_group_coordinator) == 1),
          group_id = group_id,
          group_name = group_name,
          household_id = household_id,
          wss_url = wss_url
        }

        if rip ~= ip then
          log.warn(string.format(
            "[%s] received discovery response with reported (%s) & source IP (%s) mismatch, ignoring",
            group_id, rip, ip))
          log.debug(rip, "!=", ip)
        elseif ip and is_group_coordinator and group_id and
            group_name and household_id and wss_url then
          if #group_id == 0 then
            log.debug(string.format(
            "Received SSDP response for non-primary Sonos device in a bonded set, skipping; SSDP Response: %s\n",
            st_utils.stringify_table(group_info, nil, false)))
          elseif callback ~= nil then
            if type(callback) == "function" then
              callback(group_info)
            else
              log.warn(string.format(
              "Expected a function in callback argument position for `SSDP.search`, found argument of type %s",
              type(callback)))
            end
          end
        else
          log.warn(
            "Received incomplete Sonos SSDP M-SEARCH Reply, retrying search")
          log.debug(string.format("%s", st_utils.stringify_table(
            group_info, "SSDP Reply", true)))
        end
      end
    elseif rip == "timeout" then
      break
    else
      error(string.format(
        "error receiving discovery replies for search term: %s",
        rip))
    end
  end
  s:close()
end

return SSDP
