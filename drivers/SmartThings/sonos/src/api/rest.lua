local json = require "st.json"
local log = require "log"
local st_utils = require "st.utils"

local RestClient = require "lunchbox.rest"

--- @param response? Response The raw response to process, which can be nil if error is not nil
--- @param err? string the incoming error message
--- @param partial? string the incoming partial data in the event of an error
--- @return any|nil response the processed JSON as a table, nil on error
--- @return string|nil error an error message
--- @return string|nil partial contents of partial read if successful
local function process_rest_response(response, err, partial, err_callback)
  if err == nil and response == nil then
    log.error(
      st_utils.stringify_table({
        resp = response,
        maybe_err = err,
        maybe_partial = partial,
      }, "[SonosRestApi] Unexpected nil for both response and error processing REST reply", false)
    )
  end
  if err ~= nil then
    if type(err_callback) == "function" then
      err_callback(err)
    end
    return response, err, partial
  elseif response ~= nil then
    local headers = response:get_headers()
    if not (headers and headers:get_one("content-type") == "application/json") then
      return nil,
        string.format(
          "Received non-JSON content-type header [%s] when JSON response was expected",
          ((headers and headers:get_one("content-type")) or "no headers")
        )
    else
      local body, get_body_err = response:get_body()
      if not body then
        return nil, get_body_err
      end
      local json_result = table.pack(pcall(json.decode, body))
      local success = table.remove(json_result, 1)

      if not success then
        return nil,
          st_utils.stringify_table(
            { response_body = body, json = json_result },
            "Couldn't decode JSON in REST API Response",
            false
          )
      end

      local rest_response, rest_error, response_partial = table.unpack(json_result)
      return rest_response, rest_error, response_partial
    end
  else
    return nil, "no response or error received"
  end
end

--- A module of pure functions for sending REST payloads to a Sonos speaker.
--- Sonos speakers expose both a REST and WebSocket API. We primarily use the WebSocket
--- API in this edge driver, however there are a handful of REST commands that are
--- useful to issue in order to gather some system information before establishing
--- a websocket connection. This module provides a handful of free functions that
--- make it easy to perform those handful of requests.
---
--- Sonos speakers *do not* support `Connection: Keep-Alive` for REST calls. They will *always*
--- reply with `Connection: Close` in the response headers. So we can't use long-lived TCP sockets
--- or persistent RestClient instances here; we can only use one-shot request/response interactions.
--- @class SonosRestApi
local SonosRestApi = {}

--- Query a Sonos Group IP address for individual player info
---@param url table a URL table created by `net_url`
---@param headers table<string,string>?
---@return SonosDiscoveryInfo|SonosErrorResponse|nil
---@return string|nil error
function SonosRestApi.get_player_info(url, headers)
  url.path = "/api/v1/players/local/info"
  return process_rest_response(RestClient.one_shot_get(url, headers))
end

---@param url table a URL table created by `net_url`
---@param household HouseholdId
---@param headers table<string,string>?
---@return SonosGroupsResponseBody|SonosErrorResponse|nil response
---@return nil|string error
function SonosRestApi.get_groups_info(url, household, headers)
  url.path = string.format("/api/v1/households/%s/groups", household)
  return process_rest_response(RestClient.one_shot_get(url, headers))
end

---@param url table a URL table created by `net_url`
---@param household HouseholdId
---@param headers table<string,string>?
---@return SonosFavoritesResponseBody|SonosErrorResponse|nil response
---@return nil|string error
function SonosRestApi.get_favorites(url, household, headers)
  url.path = string.format("/api/v1/households/%s/favorites", household)
  return process_rest_response(RestClient.one_shot_get(url, headers))
end

return SonosRestApi
