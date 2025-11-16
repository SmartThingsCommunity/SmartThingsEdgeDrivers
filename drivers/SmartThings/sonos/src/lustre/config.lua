---@class Config
---The configuration of a websocket provided at connection time
---
---@field private _max_queue_size number|nil
---@field private _max_frame_size number
---@field private _max_message_size number
---@field private _accept_unmasked_frames boolean
---@field public extensions table[]
---@field public protocols string[]
---@field private _keep_alive number|nil
---@field private _extra_headers table[]
local Config = {}
Config.__index = Config

local DEFAULT_MAX_FRAME = 16 * 1024 * 1024
local DEFAULT_MAX_MESSAGE = 64 * 1024 * 1024
local DEFAULT_MAX_FRAMES_WITHOUT_PONG = 4

---Construct a default configurations
---@return Config
function Config.default()
  return setmetatable({
    _max_queue_size = nil,
    _max_frame_size = DEFAULT_MAX_FRAME,
    max_message_size = DEFAULT_MAX_MESSAGE,
    _max_frames_without_pong = DEFAULT_MAX_FRAMES_WITHOUT_PONG,
    _accept_unmasked_frames = false,
    extensions = {},
    protocols = {},
    _keep_alive = nil,
    _extra_headers = {}
  }, Config)
end

---Set the max message queue size
---@param size number|nil
---@return Config
function Config:max_queue_size(size)
  self._max_queue_size = size
  return self
end

---Set the max message size (Default 64mb)
---@param size number|nil
---@return Config
function Config:max_message_size(size)
  self._max_message_size =
    size or DEFAULT_MAX_MESSAGE
  return self
end

---Set the max frame size (Default 16mb)
---@param size number|nil
---@return Config
function Config:max_frame_size(size)
  self._max_frame_size = size or DEFAULT_MAX_FRAME
  return self
end

---Set the max frames that can be received while waiting for a pong (Default 4)
---@param size number|nil
---@return Config
function Config:max_frames_without_pong(size)
  self._max_frames_without_pong =
    size or DEFAULT_MAX_FRAMES_WITHOUT_PONG
  return self
end

---Add an entry to the enabled extensions
---@param name string
---@param params string[]
---@return Config
function Config:extension(name, params)
  table.insert(self.extensions,
    {name = name, params = params})
  return self
end

---Add an entry to the enabled protocols
---@param name string
---@return Config
function Config:protocol(name)
  table.insert(self.protocols, name)
  return self
end

---Set the keep alive value in number of seconds. This will control
---how often an idle websocket will send a "ping" frame
---@param timeout any
---@return Config
function Config:keep_alive(timeout)
  self._keep_alive = timeout
  return self
end

function Config:header(key, value)
  self._extra_headers[key] = value
  return self
end

return Config
