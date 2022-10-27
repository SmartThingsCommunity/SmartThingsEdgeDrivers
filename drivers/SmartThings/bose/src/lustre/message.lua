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

---@class Message
---@field type string either "binary" or "text"
---@field data string
local Message = {}
Message.__index = Message

Message.BYTES = "binary"
Message.TEXT = "text"

---@param type string ['binary'|'text']
---@param data string
function Message.new(type, data) return setmetatable({type = type, data = data}, Message) end

return Message
