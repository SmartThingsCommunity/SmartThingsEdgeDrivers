--- Table of constants used to index in to device store fields
--- @class Fields
--- @field IPV4 string the ipV4 address of a Hue bridge
--- @field API_KEY string the hue application key acquired from the bridge
--- @field MODEL_ID string Bridge model ID
--- @field BRIDGE_ID string The unique identifier for the bridge (found during discovery)
--- @field BRIDGE_SW_VERSION string The SW Version of the bridge to determine if it supports CLIP V2
--- @field DEVICE_TYPE string Field on all Hue devices that indicates type (currently either "brige" or "light")
--- @field BRIDGE_API string Transient field that holds the HueAPI instance for the bridge
--- @field MIN_DIMMING string Minimum dimming/brightness value accepted by a light
--- @field EVENT_SOURCE string Field on a bridge that stores a handle to the SSE EventSource client.
local Fields = {
  _ADDED = "added",
  _INIT = "init",
  _REFRESH_AFTER_INIT = "force_refresh",
  BRIDGE_API = "bridge_api",
  BRIDGE_ID = "bridgeid",
  BRIDGE_SW_VERSION = "swversion",
  DEVICE_TYPE = "devicetype",
  EVENT_SOURCE = "eventsource",
  GAMUT = "gamut",
  HUE_DEVICE_ID = "hue_device_id",
  IPV4 = "ipv4",
  MIN_DIMMING = "mindim",
  MIN_KELVIN = "mintemp",
  MODEL_ID = "modelid",
  IS_ONLINE = "is_online",
  PARENT_DEVICE_ID = "parent_device_id_local",
  RESOURCE_ID = "rid",
  WRAPPED_HUE = "_wrapped_hue"
}

return Fields
