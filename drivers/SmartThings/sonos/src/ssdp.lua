local log = require "log"
local socket = require "cosock.socket"
local Stream = require "cosock.stream"
local Headers = require "luncheon.headers"

local SSDP_MULTICAST_IP = "239.255.255.250"
local SSDP_MULTICAST_PORT = 1900
local SSDP_DEFAULT_NUM_SENDS = 5
local SSDP_DEFAULT_MX = 5

--- @alias SsdpSearchTerm string
--- @alias SsdpSearchResponse Headers
--- @alias SsdpSearchMatches SsdpSearchResponse[]

--- @class SsdpSearchTermContext
--- @field public enabled boolean
--- @field public required_headers string[]?
--- @field public validator (fun(match: SsdpSearchResponse): boolean?,string?)?
--- @field public post_processor (fun(match: SsdpSearchResponse): any)?

---@class (exact) SsdpSearchKwargs
---
--- A list of strings containing headers that must be present for the search response to be considered
--- as applying to this search request. These both required search terms and a validator are provided, the
--- required search terms will be checked first.
---@field public required_headers string[]?
---
--- An optional callback that will be run over every response whose search term matches the one provided.
--- It should return `true` if the response is valid. Otherwise, it should return `nil, string` where string is the reason
--- that the validation failed.
---@field public validator (fun(match: SsdpSearchResponse): boolean?,string?)
---
--- An optional callback that will be called on any response to this search term that passes the required headers and
--- validator checks, to transform it in to something else.
---@field public post_processor (fun(match: SsdpSearchResponse): any)?

--- @class (exact) Ssdp
local Ssdp = {}

---Parses the raw UDP response following the SSDP M-Search response spec,
---which is effectively an HTTP/1.1 Header payload.
---@param val string the raw response
---@return Headers? the parsed headers, minus the status line, nil on failure
---@return string? error error message, nil on success
---@diagnostic disable-next-line: inject-field
function Ssdp.parse_raw_response(val)
  -- check first line assuming it's the HTTP Status Line, which if not is invalid
  local status_line = string.match(val, "([^\r\n]*)\r\n")
  if not (status_line and string.match(status_line, "HTTP/1.1 200 OK")) then
    return nil, string.format("SSDP Response HTTP Status Line missing or not '200 OK': %q", status_line)
  end
  -- strip status line from payload
  val = string.gsub(val, "HTTP/1.1 200 OK\r\n", "", 1)

  return Headers.from_chunk(val)
end

---@param headers Headers the headers to check
---@param keys_to_check string[] list of header keys whose presence should be validated
---@return boolean success true if all headers are present, false if not
---@return string[] missing the headers that are missing
---@diagnostic disable-next-line: inject-field
function Ssdp.check_headers_contain(headers, keys_to_check)
  local missing = {}
  for _, header_key in ipairs(keys_to_check) do
    if headers:get_one(header_key) == nil then
      table.insert(missing, header_key)
    end
  end

  return (#missing == 0), missing
end

--- @class AsyncSearchResultStream
--- @field package scanning boolean
--- @field package handle SsdpSearchHandle
--- @field package queries_sent integer
--- @field package num_multicast_queries integer
--- @field package search_start_time integer
--- @field package elapsed_since_last_send integer
--- @field package prev_send_timestamp integer
local _stream_mt = {}
_stream_mt.__index = _stream_mt

---@param self AsyncSearchResultStream
---@return Result<any,string>? Will return Ok(...) with new results, or Err(...) for an internal error that shouldn't terminate the generator
---@return nil|string reason reason for iteration termination
function _stream_mt:next()
  if not (self.scanning and self.handle) then
    return nil, "invalid state"
  end

  -- SSDP spec recommends sending 3-5 queries, 1 second apart. We allow for
  -- the number of sends to be configurable via `self.num_multicast_queries.
  -- We retain an interval of 1 second. Since this is an iterator implementation,
  -- we statefully update some time-keeping in the table every time the iterator is called,
  -- opening the loop with a multicast query if one second has elapsed.
  local should_send = self.queries_sent <= self.num_multicast_queries and self.elapsed_since_last_send >= 1
  if should_send then
    log.trace("Performing M-SEARCH Multicast")
    self.handle:multicast_m_search()
    self.queries_sent = self.queries_sent + 1
    self.elapsed_since_last_send = 0
    self.prev_send_timestamp = socket.gettime()
  else
    self.elapsed_since_last_send = (socket.gettime() - self.prev_send_timestamp)
  end

  local recv_ready, _, select_err = socket.select({ self.handle }, nil, self.handle.time_remaining)

  if select_err == "timeout" then
    local next_time_remaining = math.max(0, self.handle.search_end_time - socket.gettime())
    -- timeout + done criteria
    if next_time_remaining == 0 and self.queries_sent >= self.num_multicast_queries then
      log.trace("All queries sent and search time limit has elapsed, terminating search result stream")
      return nil, "complete"
    end
    -- timeout, done criteria *not* satisfied
    return Err("timeout"), nil
  end

  if select_err and select_err ~= "timeout" then
    return Err(string.format("select error: %s", select_err)), nil
  end

  if not (type(recv_ready) == "table" and recv_ready[1] == self.handle) then
    return Err("SSDP Search Handle not returned in recv table from socket.select"), nil
  end

  local maybe_response = self.handle:next_msearch_response()
  if maybe_response == nil and self.queries_sent >= self.num_multicast_queries then
    return nil, "complete"
  end

  return maybe_response
end

---@class SsdpSearchHandle
---@field package sock table the wrapped udp socket
---@field private inner_sock table reference to the raw luasocket held on to by the udp socket
---@field package mx integer the MX value for the search handle, shared by all terms registered with this instance.
---@field package search_terms table<SsdpSearchTerm, SsdpSearchTermContext>
---@field package search_end_time integer?
---@field package time_remaining integer?
local _ssdp_mt = {}
_ssdp_mt.__index = _ssdp_mt

function _ssdp_mt:get_current_mx_seconds()
  return self.mx
end

---Registers a new search term in the "enabled" configuration, meaning that stepping the searcher will
---multicast that term in requests, when necessary, and look for responses on UDP receive.
---@param term SsdpSearchTerm
---@param kwargs SsdpSearchKwargs
function _ssdp_mt:register_search_term(term, kwargs)
  self.search_terms[term] = {
    enabled = false,
    required_headers = (kwargs and kwargs.required_headers) or {},
    post_processor = kwargs and kwargs.post_processor,
    validator = kwargs and kwargs.validator
  }
end

---Sets an already registered search term as enabled. Search requests for this term will be sent,
---and replies that match this term will be processed during respone handling.
---@param term SsdpSearchTerm
function _ssdp_mt:enable_search_term(term)
  if self.search_terms[term] == nil then
    log.warn(string.format("Attempt to disable unregistered search term %s, ignoring", term))
  end

  self.search_terms[term].enabled = true
end

---Keeps the search term registered with the instance, but disable it. Search requests will
---not be sent, and replies for this term will be ignored during handling of responses.
---@param term SsdpSearchTerm
function _ssdp_mt:disable_search_term(term)
  if self.search_terms[term] == nil then
    log.warn(string.format("Attempt to disable unregistered search term %s, ignoring", term))
  end

  self.search_terms[term].enabled = false
end

--- Multicasts an M-SEARCH query for all registered search terms. If this happens, a timeout
--- based on the MX value will be applied to future select/read calls.
---
--- This function is semi-reentrant; if you call `multicast_m_search` before the search time
--- of the previous broadcast has elapsed, then another search query will be broadcast and
--- the search end time will be pushed out based on the `mx` parameter, extending the amount of
--- time that `receive_m_search_response` will return results with a timeout.
function _ssdp_mt:multicast_m_search()
  for term, _ in pairs(self.search_terms) do
    local multicast_msg = table.concat({
      "M-SEARCH * HTTP/1.1",
      "HOST: 239.255.255.250:1900",
      'MAN: "ssdp:discover"', -- yes, there are really supposed to be quotes in this one
      string.format("MX: %s", self.mx),
      string.format("ST: %s", term),
      "\r\n"
    }, "\r\n")

    local _, send_err = self.sock:sendto(multicast_msg, SSDP_MULTICAST_IP, SSDP_MULTICAST_PORT)
    if send_err then
      log.error(string.format("Send error broadcasting search terms: %s", send_err))
    end
  end
  self.search_end_time = socket.gettime() + (self.mx + 1)
  self.time_remaining = self.mx + 1
  self:settimeout(self.time_remaining)
end

--- If `multicast_m_search()` has been called, handle the next M-SEARCH response while the MX
--- window is active.
---
--- Return an `Ok` with a response on success, and an `Err` with message on failure.
--- If the search is complete, returns `nil`.
---
---`Ok` on success, `Err` on failure, `nil` if the search is complete. If a post processor is
---registered for the search term, the `Ok` will contain the transformed value. Otherwise, the
---parsed HTTP headers will be returned.
---@return Result<SsdpSearchResponse|any,string>?
function _ssdp_mt:next_msearch_response()
  local time_remaining = (self.search_end_time and math.max(0, self.search_end_time - socket.gettime())) or nil
  self.time_remaining = time_remaining
  self.sock:settimeout(time_remaining)

  local response, recv_ip_or_err, _ = self.sock:receivefrom()

  if recv_ip_or_err == "timeout" and time_remaining == 0 then
    self.search_end_time = nil
    return nil
  end

  if response == nil then
    return Err(string.format("UDP receive error: %s", recv_ip_or_err))
  end

  local headers, parse_err = Ssdp.parse_raw_response(response)

  if parse_err then
    return Err(string.format("parse error: %s", parse_err))
  end

  if headers == nil then
    return Err("SSDP M-Search reply contained no header lines")
  end

  local response_search_term = headers:get_one("st")

  if not (type(response_search_term) == "string" and self.search_terms[response_search_term]) then
    return Err(string.format("SSDP Reply search term %s didn't match any registered search terms", response_search_term))
  end

  -- SSDP replies will have a `Location:` header that contains a URI, and *can* contain `AL:` header(s)
  -- that point to alternative locations. We'll check them all for an IP address that matches the IP we got
  -- back from receivefrom. Technically, Location or AL could be hostnames intead of IP's. But since we
  -- don't have access to DNS in edge drivers, we don't generalize our logic for that, and we'd treat
  -- a hostname as a mismatch.
  local possible_locations = {}
  local location_candidates = table.pack(headers:get_one("location"), table.unpack(headers:get_all("al") or {}))

  if #location_candidates < 1 then
    return
        Err(string.format("Unable to locate any Location or AL header lines in SSDP response for term %s",
          response_search_term))
  end

  for _, location in ipairs(location_candidates) do
    local location_host_match = location:match("http://([^,/]+):[^/]+/.+%.xml")
    if location_host_match ~= nil then
      possible_locations[location_host_match] = location
    end
  end

  if possible_locations[recv_ip_or_err] == nil then
    return
        Err(string.format("IP addres [%s] from socket receivefrom doesn't match any of the reply locations: %s",
          table.concat(location_candidates, ", ")))
  end

  local ctx_for_response = self.search_terms[response_search_term]

  if ctx_for_response == nil then
    return Err(string.format("Search term %s doesn't have a valid handler context", response_search_term))
  end

  if ctx_for_response.required_headers and #(ctx_for_response.required_headers) > 0 then
    local success, missing = Ssdp.check_headers_contain(headers, ctx_for_response.required_headers)

    if not success then
      return Err(string.format("Response for term %s was missing headers: %s", response_search_term,
        table.concat(missing, ", ")))
    end
  end

  if type(ctx_for_response.validator) == "function" then
    local valid, reason = ctx_for_response.validator(headers)
    if not valid then
      return Err(string.format("Response to search term %s failed validation with reason: %s", response_search_term,
        reason))
    end
  end

  if type(ctx_for_response.post_processor) == "function" then
    return Ok(ctx_for_response.post_processor(headers))
  end

  return Ok(headers)
end

---@param kind "recvr"|"sendr"
---@param waker fun()|nil
function _ssdp_mt:setwaker(kind, waker)
  assert(kind == "recvr",
    string.format("setwaker: SSDP search can only wake on receive readiness, got unsupported wake kind: %s.", kind))

  assert(self.waker_ref == nil or waker == nil,
    "Waker already set, cannot await SSDP serach instance from multiple locations.")

  self.waker_ref = waker
  self._wake = function(ssdp_search_wrapper, wake_kind, ...)
    assert(wake_kind == "recvr",
      string.format("wake: SSDP search can only wake on receive readiness, got unsupported wake kind: %s.", wake_kind))
    if type(ssdp_search_wrapper.waker_ref) == "function" then
      ssdp_search_wrapper.waker_ref(...)
      ssdp_search_wrapper.waker_ref = nil
      return true
    else
      log.warn("Attempted to wake SSDP search socket with no waker set")
      return false
    end
  end
end

function _ssdp_mt:settimeout(timeout)
  assert(timeout == nil or type(timeout) == "number",
    string.format("expected number|nil, for timeout, received %s", type(timeout)))
  self.timeout = timeout
  self.sock:settimeout(timeout)
end

---Create an async stream of results for a given search term configuration. Requires being
---inside a [`cosock`](lua://cosock) async runtime.
---
---The returned table is an iterator; it is "callable", and each call is a cosock-enabled
---async function that will yield [`Result`s](lua://Result) until scan is complete.
---
---It can be used in a `for` loop, just like any other iterator, as long as you're within the
---cosock runtime.
---
---@return AsyncSearchResultStream stream the search stream if it was constructed successfully, nil on failure
function _ssdp_mt:as_stream()
  local now = socket.gettime()

  local ssdp_stream_impl = setmetatable({
    handle = self,
    scanning = true,
    num_multicast_queries = SSDP_DEFAULT_NUM_SENDS,
    queries_sent = 0,
    search_start_time = now,
    prev_send_timestamp = 0,
    elapsed_since_last_send = 1,
  }, _stream_mt)

  return Stream.wrap_next(ssdp_stream_impl) --[[ @as AsyncSearchResultStream ]]
end

---Creates a new SSDP Search Handle Instance.
---
---Optional MX value. The same MX value will be used for all search terms. If you need different MX values for different terms,
---you should create multiple instances.
---@param mx integer? Defaults to [`SSDP_DEFAULT_MX`](lua://SSDP_DEFAULT_MX)
---
---@return SsdpSearchHandle? the search handle on success, nil on failure
---@return string? error the error if the instance cannot be created.
---@diagnostic disable-next-line: inject-field
function Ssdp.new_search_instance(mx)
  local udp_sock, sock_err = socket.udp()
  if sock_err or not udp_sock then
    log.error(string.format("Error opening UDP socket for SSDP search: %s", sock_err))
    return nil, "sock_err"
  end

  local listen_ip = "0.0.0.0"
  local listen_port = 0

  local _, bind_err = udp_sock:setsockname(listen_ip, listen_port)

  if bind_err then
    log.error(string.format("Unable to bind UDP socket for SSDP search: %s", bind_err))
    return nil, bind_err
  end

  return
      setmetatable(
        { search_terms = {}, sock = udp_sock, inner_sock = udp_sock.inner_sock, mx = mx or SSDP_DEFAULT_MX, search_end_time = nil },
        _ssdp_mt), nil
end

return Ssdp
