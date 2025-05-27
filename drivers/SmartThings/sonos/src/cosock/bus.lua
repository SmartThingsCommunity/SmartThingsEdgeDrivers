---@diagnostic disable: duplicate-doc-alias, duplicate-doc-field, invisible, duplicate-set-field
-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

---@package
---@class cosock.Bus.SubscriptionImpl
local __receiver_mt = {}

---@package
---@class cosock.Bus.SenderImpl
local __sender_mt = {}
local __closed_mt = {}

---@package
---@alias ReceiverId integer

---State that describes the link between an individual receiver handle and the
---singular send/broadcast handle.
---@package
---@class cosock.Bus.Link
---A reference to the receiver associated with this link
---@field package receiver cosock.Bus.Subscription
---The mesage queue for the sender
---@field package queue any[]
---The receiver's cosock waker, `nil` if the receiver is not currently pending
---@field package waker fun()?

---@package
---@class cosock.Bus.Inner
---whether the bus is currently closed. A closed bus will return `nil, "closed"` for
---all operations on any senders or receivers.
---@field package closed boolean
---The set of active/not-closed [Links](lua://cosock.Bus.Link).
---@field package receiver_links table<ReceiverId,cosock.Bus.Link>
---Counter for managing generation of [Receiver ID's](lua://ReceiverId)
---@field package next_receiver_id ReceiverId

---The send/broadcast side of the bus.
---@class cosock.Bus.Sender: cosock.Bus.SenderImpl
---The interior shared state for managing the link between the sender and all receivers
---@field package _bus_inner cosock.Bus.Inner

---The receive side of the sender/broadcaster for the bus.
---@class cosock.Bus.Subscription: cosock.Bus.SubscriptionImpl
---The interior shared state for managing the link between the sender and all receivers
---@field package _bus_inner cosock.Bus.Inner
---The receiver's ID
---@field package id ReceiverId
---Strong reference to this receiver's receiver link to keep the shared weak reference from
---getting GC'd while the receiver itself is still in scope.
---@field package _link cosock.Bus.Link
---The yield timeout limit, in seconds. If unset, will yield forever.
---@field package timeout number?

---@type metatable
---@overload fun(): cosock.Bus.Sender
local __ctor_mt = {
  __call = function()
    local _inner = {
      closed = false,
      receiver_links = setmetatable({}, { __mode = "v" }),
      next_receiver_id = 1,
    }
    return setmetatable({ _bus_inner = _inner }, { __index = __sender_mt })
  end,
}

---An implementation of a Single-Producer, Multiple Consumer "bus".
---
---When the send side of a bus transmits a message, all currently receivers
---that aren't in the `closed` state will receive a copy of the message.
---
---This bus implementation doesn't maintain any history; new subscriptions created
---will only receive messages that are broadcast after their creation, they will not
---receive messages that were broadcast prior to their creation.
---@class cosock.Bus
---@overload fun(): cosock.Bus.Sender
local m = setmetatable({}, __ctor_mt --[[ @as metatable ]])

---Close the receiver.
---@param self cosock.Bus.Subscription
function __receiver_mt:close()
  self._bus_inner.receiver_links[self.id] = nil
  setmetatable(self, { __index = __closed_mt })
end

---Returns the next message unprocessed by this receiver handle.
---If there are no messages available, this receiver will yield
---until a message has been broadcast, or it times out.
---
---@see cosock.Bus.Subscription.settimeout
---
---@param self cosock.Bus.Subscription
---@return any? received the next message unhandled by this subscription handle. Nil on error.
---@return string? err the error string. Nil on success.
function __receiver_mt:receive()
  local link = self._bus_inner.receiver_links[self.id]

  if not link then
    return nil, "closed"
  end

  while true do
    if #link.queue > 0 then
      local event = table.remove(link.queue, 1)
      return event.msg
    elseif self._bus_inner.closed then
      self:close()
      return nil, "closed"
    else
      local _, _, err = coroutine.yield({ self }, nil, self.timeout)
      if err then
        return nil, err
      end
      link.waker = nil
    end
  end
end

---Set timeout on the receive yield.
---@param self cosock.Bus.Subscription
---@param timeout number? the timeout value in seconds. Nil will allow this handle to yield forever until a message arrives.
function __receiver_mt:settimeout(timeout)
  self.timeout = timeout
end

---Interface method utilized by [cosock](lua://cosock) to manage waking.
---@param self cosock.Bus.Subscription
---@param kind "recvr"|"sendr" the receiver kind
---@param waker fun()? the waker
function __receiver_mt:setwaker(kind, waker)
  local existing_waker = self._bus_inner.receiver_links[self.id].waker
  assert(kind == "recvr", "unsupported wake kind: " .. tostring(kind))
  assert(
    existing_waker == nil or waker == nil,
    "waker already set, receive can't be waited on from multiple places at once"
  )
  self._bus_inner.receiver_links[self.id].waker = waker

  -- if messages waiting, immediately wake
  if #self._bus_inner.receiver_links[self.id].queue > 0 and waker then
    waker()
  end
end

---Close the bus. This will also close all currently active subscriptions.
---@param self cosock.Bus.Sender
function __sender_mt:close()
  self._bus_inner.closed = true
  local existing_links = self._bus_inner.receiver_links
  for _, link in pairs(existing_links) do
    if link.waker then
      link.waker()
    end
  end
  self._bus_inner.receiver_links = setmetatable({}, { __mode = "v" })
  setmetatable(self, { __index = __closed_mt })
end

---Broadcast a message to all receivers.
---@param self cosock.Bus.Sender
---@param msg any the message to broadcast
---@return boolean success whether the send succeeded
---@return string? error the error string if `success` is `false`.
function __sender_mt:send(msg)
  if not self._bus_inner.closed then
    -- wapping in table allows `nil` to be sent as a message
    for _, link in pairs(self._bus_inner.receiver_links) do
      table.insert(link.queue, { msg = msg })
      if link.waker then
        link.waker()
      end
    end
    return true
  else
    return false, "closed"
  end
end

---Create a new subscription handle for this bus.
---@param self cosock.Bus.Sender
---@return cosock.Bus.Subscription? receiver the subscription handle. `nil` if this bus is closed.
---@return string? error "closed" if the bus is closed.
function __sender_mt:subscribe()
  if self._bus_inner.closed then
    return nil, "closed"
  end

  ---@type cosock.Bus.SubscriptionImpl
  local rx = setmetatable(
    { _bus_inner = self._bus_inner, id = self._bus_inner.next_receiver_id },
    { __index = __receiver_mt }
  )
  local my_link = { receiver = rx, queue = {}, waker = nil }

  ---@cast rx cosock.Bus.Subscription
  rx._link = my_link
  self._bus_inner.receiver_links[rx.id] = my_link
  self._bus_inner.next_receiver_id = self._bus_inner.next_receiver_id + 1
  return rx
end

local function _closed()
  return nil, "closed"
end

-- no-ops
__closed_mt.settimeout = function() end
__closed_mt.close = function() end

-- methods that should error
__closed_mt.send = _closed
__closed_mt.receive = _closed
__closed_mt.subscribe = _closed

return m
