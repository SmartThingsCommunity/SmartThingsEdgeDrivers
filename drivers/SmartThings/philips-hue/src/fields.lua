--- Table of constants used to index in to device store fields
--- @class Fields
--- @field IPV4 string the ipV4 address of a Hue bridge
--- @field API_KEY string the hue application key acquired from the bridge
--- @field MODEL_ID string Bridge model ID
--- @field BRIDGE_ID string The unique identifier for the bridge (found during discovery)
--- @field BRIDGE_SW_VERSION string The SW Version of the bridge to determine if it supports CLIP V2
--- @field DEVICE_TYPE string Field on all Hue devices that indicates type, maps to a Hue service rtype.
--- @field BRIDGE_API string Transient field that holds the HueAPI instance for the bridge
--- @field EVENT_SOURCE string Field on a bridge that stores a handle to the SSE EventSource client.
local Fields = {
  _ADDED = "added",
  _INIT = "init",
  _REFRESH_AFTER_INIT = "force_refresh",
  BRIDGE_API = "bridge_api",
  BRIDGE_ID = "bridgeid",
  BRIDGE_SW_VERSION = "swversion",
  BUTTON_INDEX_MAP = "button_rid_to_index",
  DEVICE_TYPE = "devicetype",
  EVENT_SOURCE = "eventsource",
  GAMUT = "gamut",
  HUE_DEVICE_ID = "hue_device_id",
  IPV4 = "ipv4",
  IS_ONLINE = "is_online",
  IS_MULTI_SERVICE = "is_multi_service",
  MIN_KELVIN = "mintemp",
  MAX_KELVIN = "maxtemp",
  MODEL_ID = "modelid",
  PARENT_DEVICE_ID = "parent_device_id_local",
  RESOURCE_ID = "rid",
  RETRY_MIGRATION = "retry_migration",
  WRAPPED_HUE = "_wrapped_hue",
  COLOR_SATURATION = "color_saturation",
  COLOR_HUE = "color_hue",
  SWITCH_STATE = "switch_state_cache",
}

return Fields
