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

local sha1 = require "sha1"
local base64 = require "st.base64"
local seeded = false
local function seed_once()
  if seeded then return end
  seeded = true
  math.randomseed(os.time())
end

local WEBSOCKET_SHA_UUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

---Use the Sec-WebSocket-Accept header value to create a
---the corresponding Sec-WebSocket-Accept header value
local function build_accept_from(key) return base64.encode(sha1.binary(key .. WEBSOCKET_SHA_UUID)) end

---Generate a random Sec-WebSocket-Key header value
---@return string
local function generate_key()
  seed_once()
  local bytes = {}
  for _ = 1, 16 do table.insert(bytes, math.random(0, 255)) end
  return base64.encode(string.char(table.unpack(bytes)))
end

return {build_accept_from = build_accept_from, generate_key = generate_key}
