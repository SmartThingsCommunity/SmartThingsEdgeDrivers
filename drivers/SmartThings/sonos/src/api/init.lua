local log = require "log"
local SonosRestApi = require "api.rest"

local SONOS_API_KEY_HTTP_HEADER_KEY = "X-Sonos-Api-Key"

local load_success, keys = pcall(require, "app_key")

if not load_success then
  log.error(string.format("Problem loading API keys: %s", keys))
end

local __loaded_keys = (load_success and keys) or nil

---@type { s1_key: string, oauth_key: string }?
local api_keys

if type(__loaded_keys) == "string" then
  api_keys = {
    s1_key = __loaded_keys,
  }
else
  api_keys = __loaded_keys
end

--- @class SonosApi
local SonosApi = {
  -- constants
  DEFAULT_SONOS_PORT = 1443,
  SONOS_API_KEY_HTTP_HEADER_KEY = SONOS_API_KEY_HTTP_HEADER_KEY,

  -- data
  ---@type { s1_key: string, oauth_key: string }?
  api_keys = api_keys,

  -- module re-exports
  RestApi = SonosRestApi,
}

--- Get the HTTP Headers with the correct API Key and Bearer Token
--- values.
---@param api_key string
---@param access_token string? if nil, no Authorization header will be set
---@return table<string,string>
function SonosApi.make_headers(api_key, access_token)
  local headers = { [SONOS_API_KEY_HTTP_HEADER_KEY] = api_key or (api_keys and api_keys.s1_key) }
  if type(access_token) == "string" then
    headers["Authorization"] = string.format("Bearer %s", access_token)
  end

  return headers
end

return SonosApi
