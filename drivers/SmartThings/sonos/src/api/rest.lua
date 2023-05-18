local json = require 'st.json'

local RestClient = require 'lunchbox.rest'

--- SONOS_API_KEY is a Global added to the environment in the root init.lua.
--- This API key is injected in to the driver at deploy time for production.
--- To use your own API key, add an `app_key.lua` to the `src`
--- directory and have the only code be to `return "YOUR_API_KEY"`
local HEADERS = {
  ['X-Sonos-Api-Key'] = SONOS_API_KEY
}

--- @param response? Response The raw response to process, which can be nil if error is not nil
--- @param err? string the incoming error message
--- @param partial? string the incoming partial data in the event of an error
--- @return any|nil response the processed JSON as a table, nil on error
--- @return string|nil error an error message
--- @return string|nil partial contents of partial read if successful
local function process_rest_response(response, err, partial)
  if err ~= nil then
    return response, err, partial
  elseif response ~= nil and response:get_headers():get_one("content-type") == 'application/json' then
    return json.decode(response:get_body())
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
--- @module 'sonos.api.SonosRestApi'
local SonosRestApi = {}

--- Query a Sonos Group IP address for individual player info
--- @param ip string the IP address of the player
--- @param port integer the port number of the player
--- @return SonosDiscoveryInfo|nil
--- @return string|nil error
function SonosRestApi.get_player_info(ip, port)
  local url = "https://" .. ip .. ":" .. port .. "/api/v1/players/local/info"
  return process_rest_response(RestClient.one_shot_get(url, HEADERS))
end

function SonosRestApi.get_groups_info(ip, port, household)
  local url = string.format("https://%s:%s/api/v1/households/%s/groups", ip, port, household)
  return process_rest_response(RestClient.one_shot_get(url, HEADERS))
end

function SonosRestApi.get_favorites(ip, port, household)
  local url = string.format("https://%s:%s/api/v1/households/%s/favorites", ip, port, household)
  return process_rest_response(RestClient.one_shot_get(url, HEADERS))
end

return SonosRestApi
