---@module 'result'

---@class cosock.Stream
local Stream = {}

---@class cosock.Stream.AsyncReceiveStream
---@field protected terminated boolean
---@field protected selectable table
---@field protected receive_fn fun(self: table): any?
local _stream_mt = {}
_stream_mt.__index = _stream_mt

local function __call_impl(stream)
  if stream.terminated then
    return nil, "closed"
  end

  local receive_result = table.pack(stream.receive_fn(stream.selectable))
  if receive_result[1] == nil then
    stream.terminated = true
  end
  return table.unpack(receive_result)
end

---Create a stream from a receive-position selectable, cosock-enabled type; and a function
---that will get the next item from the selectable when it reports that it's
---receive ready.
---
---The stream itself is also select-able; however, the primary intended use for the stream is
---as an async iterator/generator type; the returned table is callable, and each call will return
---a value until the stream has been terminated, in which case subsequent call operations on the able
---will result in a `nil` value.
---
---The function specification can either be a string, in which case it will be treated as
---a key on the selectable table, or it can be a callback that takes the selectable as the
---first argument.
---
---There is also a convenience shorthand for using the string function key format, in the form of dynamically
---currying table keys of the form `wrap_<function name>`, where the function name resolves to a method on
---the target selectable.
---
---For example, if wrapping a table that uses `tbl:receive()` when it is read-ready, you can use the shorthand
---`Stream.wrap_receive(tbl)`.
---
---The item yielding function should return a non-nil for as long as the stream is still valid.
---If the underlying selectable has an error case *that does not invalidate the stream*, then it should
---*not* return `nil, err`, or the stream will be treated as terminated.
---
---@param selectable any a type that implements `setwaker` for `recvr`
---@param receive_fn string|fun(self: table): any?
---@return cosock.Stream.AsyncReceiveStream
function Stream.wrap(selectable, receive_fn)
  if type(receive_fn) == "string" then
    receive_fn = selectable[receive_fn]
  end
  local base_stream = setmetatable({
    terminated = false,
    selectable = selectable,
    receive_fn = receive_fn,
  }, _stream_mt)

  -- We create an index that can pass through to the selectable object, which is
  -- what allows the stream to interact with the cosock runtime via its wrapped
  -- component
  local function index(tbl, key)
    return rawget(tbl, key) or base_stream[key] or selectable[key]
  end

  return setmetatable(base_stream, { __index = index, __call = __call_impl })
end

local function curried_wrap(receive_fn_key)
  return function(selectable)
    return Stream.wrap(selectable, receive_fn_key)
  end
end

Stream = setmetatable(Stream, {
  __index = function(_, key)
    if rawget(Stream, key) ~= nil then
      return rawget(Stream, key)
    end

    local maybe_wrapped_fn = key:match("wrap_([^%s]+)")

    if maybe_wrapped_fn then
      return curried_wrap(maybe_wrapped_fn)
    end
  end,
})

return Stream
