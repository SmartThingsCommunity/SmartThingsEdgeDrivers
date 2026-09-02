--[[
  Capture Logger - Structured JSON logging for comprehensive driver behavior capture
  
  This module provides extensive logging capabilities to capture:
  - All network traffic (REST requests/responses, SSE events)
  - All IPC communication (commands, capability events)
  - Device lifecycle events
  - State changes
  
  Logs are written in JSON format with correlation IDs to track request->response chains.
  
  Usage:
    local capture_logger = require "capture_logger"
    capture_logger.log_rest_request(request_id, method, url, headers, body)
    capture_logger.log_rest_response(request_id, status, headers, body, elapsed_ms)
]]

local log = require "log"
local json = require "st.json"
local st_utils = require "st.utils"

local M = {}

-- Configuration
M.enabled = true  -- Set to false to disable capture logging entirely
M.log_to_hub = true  -- Send logs to hub (visible in hub logs)
M.include_sensitive = false  -- Set to true to log API keys and auth tokens (CAUTION!)

-- Counter for generating unique IDs
local id_counter = 0
local function next_id()
  id_counter = id_counter + 1
  return id_counter
end

-- High-resolution timestamp (milliseconds since epoch)
local function timestamp_ms()
  local socket = require "socket"
  if socket and socket.gettime then
    return math.floor(socket.gettime() * 1000)
  end
  return os.time() * 1000
end

-- Safe JSON encoding with fallback
local function safe_json_encode(data)
  local success, result = pcall(json.encode, data)
  if success then
    return result
  else
    return string.format("{\"error\":\"JSON encoding failed: %s\"}", tostring(result))
  end
end

-- Sanitize sensitive data from headers/body if needed
local function sanitize_headers(headers)
  if M.include_sensitive then
    return headers
  end
  
  local sanitized = {}
  for k, v in pairs(headers or {}) do
    local k_lower = string.lower(k)
    if k_lower:find("key") or k_lower:find("auth") or k_lower:find("token") then
      sanitized[k] = "***REDACTED***"
    else
      sanitized[k] = v
    end
  end
  return sanitized
end

-- Core logging function
local function write_log(log_entry)
  if not M.enabled then return end
  
  local json_log = safe_json_encode(log_entry)
  
  if M.log_to_hub then
    log.info_with({ hub_logs = true }, "[CAPTURE] " .. json_log)
  else
    log.info("[CAPTURE] " .. json_log)
  end
end

-- Generate a unique request ID
function M.new_request_id()
  return string.format("req_%d_%d", timestamp_ms(), next_id())
end

-- Generate a unique event ID
function M.new_event_id()
  return string.format("evt_%d_%d", timestamp_ms(), next_id())
end

-- Generate a unique state change ID
function M.new_state_id()
  return string.format("state_%d_%d", timestamp_ms(), next_id())
end

--------------------------------------------------------------------------------
-- NETWORK TRAFFIC LOGGING
--------------------------------------------------------------------------------

--- Log an outgoing REST request
-- @param request_id string Unique request identifier
-- @param method string HTTP method (GET, POST, PUT, etc.)
-- @param url string Full URL or path
-- @param headers table HTTP headers
-- @param body string|table Request body
function M.log_rest_request(request_id, method, url, headers, body)
  local log_entry = {
    type = "NETWORK_OUT",
    subtype = "REST_REQUEST",
    timestamp = timestamp_ms(),
    request_id = request_id,
    method = method,
    url = url,
    headers = sanitize_headers(headers),
    body = body,
  }
  write_log(log_entry)
end

--- Log an incoming REST response
-- @param request_id string Request identifier (matches the request)
-- @param status number HTTP status code
-- @param headers table HTTP response headers
-- @param body string|table Response body
-- @param elapsed_ms number Time elapsed since request (optional)
function M.log_rest_response(request_id, status, headers, body, elapsed_ms)
  local log_entry = {
    type = "NETWORK_IN",
    subtype = "REST_RESPONSE",
    timestamp = timestamp_ms(),
    request_id = request_id,
    status = status,
    headers = sanitize_headers(headers),
    body = body,
    elapsed_ms = elapsed_ms,
  }
  write_log(log_entry)
end

--- Log a REST request error
-- @param request_id string Request identifier
-- @param error_msg string Error message
-- @param context table Additional context about the error
function M.log_rest_error(request_id, error_msg, context)
  local log_entry = {
    type = "NETWORK_ERROR",
    subtype = "REST_ERROR",
    timestamp = timestamp_ms(),
    request_id = request_id,
    error = error_msg,
    context = context,
  }
  write_log(log_entry)
end

--- Log SSE connection establishment
-- @param connection_id string Unique connection identifier
-- @param url string SSE endpoint URL
-- @param headers table Connection headers
function M.log_sse_connect(connection_id, url, headers)
  local log_entry = {
    type = "NETWORK_OUT",
    subtype = "SSE_CONNECT",
    timestamp = timestamp_ms(),
    connection_id = connection_id,
    url = url,
    headers = sanitize_headers(headers),
  }
  write_log(log_entry)
end

--- Log SSE connection established successfully
-- @param connection_id string Connection identifier
-- @param status number HTTP status code from handshake
function M.log_sse_open(connection_id, status)
  local log_entry = {
    type = "NETWORK_IN",
    subtype = "SSE_OPEN",
    timestamp = timestamp_ms(),
    connection_id = connection_id,
    status = status,
  }
  write_log(log_entry)
end

--- Log an incoming SSE event
-- @param connection_id string Connection identifier
-- @param event_id string Unique event identifier
-- @param event_type string Event type (from SSE 'event:' field)
-- @param event_data string|table Event data
function M.log_sse_event(connection_id, event_id, event_type, event_data)
  local log_entry = {
    type = "NETWORK_IN",
    subtype = "SSE_EVENT",
    timestamp = timestamp_ms(),
    connection_id = connection_id,
    event_id = event_id,
    event_type = event_type,
    data = event_data,
  }
  write_log(log_entry)
end

--- Log SSE connection close
-- @param connection_id string Connection identifier
-- @param reason string Reason for close
function M.log_sse_close(connection_id, reason)
  local log_entry = {
    type = "NETWORK_EVENT",
    subtype = "SSE_CLOSE",
    timestamp = timestamp_ms(),
    connection_id = connection_id,
    reason = reason,
  }
  write_log(log_entry)
end

--- Log SSE reconnection attempt
-- @param connection_id string Connection identifier
-- @param attempt_number number Reconnection attempt count
function M.log_sse_reconnect(connection_id, attempt_number)
  local log_entry = {
    type = "NETWORK_OUT",
    subtype = "SSE_RECONNECT",
    timestamp = timestamp_ms(),
    connection_id = connection_id,
    attempt = attempt_number,
  }
  write_log(log_entry)
end

--------------------------------------------------------------------------------
-- IPC LOGGING
--------------------------------------------------------------------------------

--- Log an incoming command from the hub
-- @param device_id string Device identifier
-- @param command string Command name
-- @param args table Command arguments
-- @param component string Component name
function M.log_command_received(device_id, command, args, component)
  local log_entry = {
    type = "IPC_IN",
    subtype = "COMMAND",
    timestamp = timestamp_ms(),
    device_id = device_id,
    command = command,
    args = args,
    component = component or "main",
  }
  write_log(log_entry)
end

--- Log an outgoing capability event to the hub
-- @param device_id string Device identifier
-- @param capability string Capability name
-- @param attribute string Attribute name
-- @param value any Attribute value
-- @param component string Component name
-- @param state_change_id string Optional correlation to a state change
function M.log_capability_event(device_id, capability, attribute, value, component, state_change_id)
  local log_entry = {
    type = "IPC_OUT",
    subtype = "CAPABILITY_EVENT",
    timestamp = timestamp_ms(),
    device_id = device_id,
    capability = capability,
    attribute = attribute,
    value = value,
    component = component or "main",
    state_change_id = state_change_id,
  }
  write_log(log_entry)
end

--- Log a device lifecycle event
-- @param device_id string Device identifier
-- @param lifecycle_event string Event type (added, init, removed, infoChanged)
-- @param details table Additional details about the event
function M.log_lifecycle_event(device_id, lifecycle_event, details)
  local log_entry = {
    type = "IPC_EVENT",
    subtype = "LIFECYCLE",
    timestamp = timestamp_ms(),
    device_id = device_id,
    lifecycle_event = lifecycle_event,
    details = details,
  }
  write_log(log_entry)
end

--- Log device online/offline status change
-- @param device_id string Device identifier
-- @param online boolean Online status
-- @param reason string Reason for status change
function M.log_device_status(device_id, online, reason)
  local log_entry = {
    type = "IPC_OUT",
    subtype = "DEVICE_STATUS",
    timestamp = timestamp_ms(),
    device_id = device_id,
    online = online,
    reason = reason,
  }
  write_log(log_entry)
end

--- Log device creation request
-- @param parent_device_id string Parent device ID
-- @param device_details table Device creation details
function M.log_device_create(parent_device_id, device_details)
  local log_entry = {
    type = "IPC_OUT",
    subtype = "DEVICE_CREATE",
    timestamp = timestamp_ms(),
    parent_device_id = parent_device_id,
    device_details = device_details,
  }
  write_log(log_entry)
end

--- Log device deletion request
-- @param device_id string Device identifier
function M.log_device_delete(device_id)
  local log_entry = {
    type = "IPC_OUT",
    subtype = "DEVICE_DELETE",
    timestamp = timestamp_ms(),
    device_id = device_id,
  }
  write_log(log_entry)
end

--------------------------------------------------------------------------------
-- STATE CHANGE LOGGING
--------------------------------------------------------------------------------

--- Log a driver datastore change
-- @param key string Datastore key
-- @param old_value any Previous value
-- @param new_value any New value
function M.log_datastore_change(key, old_value, new_value)
  local log_entry = {
    type = "STATE_CHANGE",
    subtype = "DATASTORE",
    timestamp = timestamp_ms(),
    key = key,
    old_value = old_value,
    new_value = new_value,
  }
  write_log(log_entry)
end

--- Log a device field change
-- @param device_id string Device identifier
-- @param field string Field name
-- @param old_value any Previous value
-- @param new_value any New value
function M.log_field_change(device_id, field, old_value, new_value)
  local log_entry = {
    type = "STATE_CHANGE",
    subtype = "DEVICE_FIELD",
    timestamp = timestamp_ms(),
    device_id = device_id,
    field = field,
    old_value = old_value,
    new_value = new_value,
  }
  write_log(log_entry)
end

--- Log discovery cache update
-- @param cache_key string Cache key
-- @param data any Cache data
function M.log_discovery_cache(cache_key, data)
  local log_entry = {
    type = "STATE_CHANGE",
    subtype = "DISCOVERY_CACHE",
    timestamp = timestamp_ms(),
    cache_key = cache_key,
    data = data,
  }
  write_log(log_entry)
end

--------------------------------------------------------------------------------
-- DISCOVERY & NETWORK OPERATIONS
--------------------------------------------------------------------------------

--- Log mDNS discovery attempt
-- @param scan_id string Unique scan identifier
function M.log_mdns_scan_start(scan_id)
  local log_entry = {
    type = "DISCOVERY",
    subtype = "MDNS_SCAN_START",
    timestamp = timestamp_ms(),
    scan_id = scan_id,
  }
  write_log(log_entry)
end

--- Log mDNS discovery result
-- @param scan_id string Scan identifier
-- @param results table Discovery results
function M.log_mdns_scan_result(scan_id, results)
  local log_entry = {
    type = "DISCOVERY",
    subtype = "MDNS_SCAN_RESULT",
    timestamp = timestamp_ms(),
    scan_id = scan_id,
    results = results,
  }
  write_log(log_entry)
end

--- Log connection state change
-- @param connection_type string Type of connection (REST, SSE)
-- @param state string New state (connecting, connected, disconnected, error)
-- @param details table Additional details
function M.log_connection_state(connection_type, state, details)
  local log_entry = {
    type = "NETWORK_EVENT",
    subtype = "CONNECTION_STATE",
    timestamp = timestamp_ms(),
    connection_type = connection_type,
    state = state,
    details = details,
  }
  write_log(log_entry)
end

--------------------------------------------------------------------------------
-- TIMING & PERFORMANCE
--------------------------------------------------------------------------------

--- Log operation timing
-- @param operation string Operation name
-- @param duration_ms number Duration in milliseconds
-- @param metadata table Additional metadata
function M.log_timing(operation, duration_ms, metadata)
  local log_entry = {
    type = "TIMING",
    subtype = "OPERATION",
    timestamp = timestamp_ms(),
    operation = operation,
    duration_ms = duration_ms,
    metadata = metadata,
  }
  write_log(log_entry)
end

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

--- Log a custom event with arbitrary structure
-- @param event_type string Event type
-- @param data table Event data
function M.log_custom(event_type, data)
  local log_entry = {
    type = "CUSTOM",
    subtype = event_type,
    timestamp = timestamp_ms(),
    data = data,
  }
  write_log(log_entry)
end

--- Enable capture logging
function M.enable()
  M.enabled = true
  log.info("[CAPTURE] Capture logging enabled")
end

--- Disable capture logging
function M.disable()
  M.enabled = false
  log.info("[CAPTURE] Capture logging disabled")
end

--- Log initialization info
function M.log_init()
  local log_entry = {
    type = "SYSTEM",
    subtype = "CAPTURE_INIT",
    timestamp = timestamp_ms(),
    message = "Capture logger initialized",
    config = {
      enabled = M.enabled,
      log_to_hub = M.log_to_hub,
      include_sensitive = M.include_sensitive,
    }
  }
  write_log(log_entry)
end

-- Initialize on load
M.log_init()

return M
