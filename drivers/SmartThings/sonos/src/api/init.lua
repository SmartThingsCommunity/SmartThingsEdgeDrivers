local log = require "log"
local SonosRestApi = require "api.rest"

local SONOS_API_KEY_HTTP_HEADER_KEY = 'X-Sonos-Api-Key'

local load_success, keys = pcall(require, "app_key")

if not load_success then
  log.error(string.format("Problem loading API keys: %s", keys))
end

---@type { s1_key: string, oauth_key: string }?
local api_keys = (load_success and keys) or nil


--- @class SonosApi
local SonosApi = {
  -- constants
  DEFAULT_SONOS_PORT = 1443,
  SONOS_API_KEY_HTTP_HEADER_KEY = SONOS_API_KEY_HTTP_HEADER_KEY,

  -- data
  ---@type { s1_key: string, oauth_key: string }?
  api_keys = api_keys,

  -- module re-exports
  RestApi = SonosRestApi
}

--- @enum SonosCapabilities
SonosApi.SonosCapabilities = {
  PLAYBACK = "PLAYBACK",                   --- The player can produce audio. You can target it for playback.
  CLOUD = "CLOUD",                         --- The player can send commands and receive events over the internet.
  HT_PLAYBACK = "HT_PLAYBACK",             --- The player is a home theater source. It can reproduce the audio from a home theater system, typically delivered by S/PDIF or HDMI.
  HT_POWER_STATE = "HT_POWER_STATE",       --- The player can control the home theater power state. For example, it can switch a connected TV on or off.
  AIRPLAY = "AIRPLAY",                     --- The player can host AirPlay streams. This capability is present when the device is advertising AirPlay support.
  LINE_IN = "LINE_IN",                     --- The player has an analog line-in.
  AUDIO_CLIP = "AUDIO_CLIP",               ---  The device is capable of playing audio clip notifications.
  VOICE = "VOICE",                         --- The device supports the voice namespace (not yet implemented by Sonos).
  SPEAKER_DETECTION = "SPEAKER_DETECTION", --- The component device is capable of detecting connected speaker drivers.
  FIXED_VOLUME = "FIXED_VOLUME"            --- The device supports fixed volume.
}

---@param ... unknown
---@return table<string,string>
---@overload fun(use_legacy_api_key: boolean, access_token: string?) table<string,string>
---@overload fun(access_token: string?) table<string,string>
function SonosApi.make_rest_headers(...)
  local api_key = (api_keys and api_keys.oauth_key)
  local maybe_legacy_flag = select(1, ...)
  local maybe_access_token
  if type(select(1, ...) or {}) == "string" then
    maybe_access_token = select(1, ...)
  else
    maybe_access_token = select(2, ...)
  end
  if type(maybe_legacy_flag) == "boolean" and maybe_legacy_flag == true and api_keys then
    api_key = api_keys.s1_key
  end
  local headers = {
    [SONOS_API_KEY_HTTP_HEADER_KEY] = api_key
  }

  if type(maybe_access_token) == "string" then
    headers["Authorization"] = string.format("Bearer %s", maybe_access_token)
  end

  return headers
end

return SonosApi
