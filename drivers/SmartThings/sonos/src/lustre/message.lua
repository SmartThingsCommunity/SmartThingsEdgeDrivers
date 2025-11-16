---@class Message
---@field public type string either "binary" or "text"
---@field public data string
local Message = {}
Message.__index = Message

Message.BYTES = "binary"
Message.TEXT = "text"

---A websocket message for sending or receiving
---@param type string ["binary"|"text"] The type of message
---@param data string The message body
function Message.new(type, data)
  return setmetatable({type = type, data = data},
    Message)
end

return Message
