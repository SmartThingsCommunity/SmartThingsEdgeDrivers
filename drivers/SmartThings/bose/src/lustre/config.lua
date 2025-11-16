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
--

---@class Config
---@field private _max_queue_size number|nil
---@field private _max_frame_size number
---@field private _max_message_size number
---@field private _accept_unmasked_frames boolean
---@field public extensions table[]
---@field public protocols string[]
---@field private _keep_alive number|nil
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
  self._max_message_size = size or DEFAULT_MAX_MESSAGE
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
  self._max_frames_without_pong = size or DEFAULT_MAX_FRAMES_WITHOUT_PONG
  return self
end

function Config:extension(name, params)
  table.insert(self.extensions, {name = name, params = params})
  return self
end

function Config:protocol(name)
  table.insert(self.protocols, name)
  return self
end

function Config:keep_alive(timeout)
  self._keep_alive = timeout
  return self
end

return Config
