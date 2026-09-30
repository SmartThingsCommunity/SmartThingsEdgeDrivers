--[[
  Device Wrapper for Capture Logging

  This module wraps device methods to automatically capture IPC communication:
  - emit_event: Captures all outgoing capability events
  - set_field: Captures device state/field changes
  - online/offline: Captures device status changes
  - create/delete: Captures device creation/deletion requests

  Usage:
    Call capture_device_wrapper.wrap_driver(driver) once in driver initialization
    to hook the driver-level device_api (create/delete/online/offline).

    Call capture_device_wrapper.wrap_device_emit_event(device) and
    capture_device_wrapper.wrap_device_set_field(device) from the device
    lifecycle handlers themselves (device_added/device_init) -- these cannot be
    installed via a post-construction `driver.lifecycle_handlers` patch, since
    the driver's lifecycle dispatcher is built from a deep copy of
    `lifecycle_handlers` at construction time.
]]

local capture_logger = require "capture_logger"
local log = require "log"
local json = require "st.json"

local M = {}

-- Store original emit_event method
local original_emit_event = nil

-- Wrapped emit_event that logs before calling original
local function wrapped_emit_event(device, event)
  -- CAPTURE: Log outgoing capability event
  if event and event.capability and event.attribute then
    capture_logger.log_capability_event(
      device.id,
      event.capability,
      event.attribute.NAME or event.attribute,
      event.attribute.value,
      event.component or "main",
      nil  -- state_change_id (could be added later if needed)
    )
  end

  -- Call original emit_event
  return original_emit_event(device, event)
end

-- Wrap a single device's emit_event method.
-- Note: this must be called directly from a lifecycle handler (e.g.
-- LifecycleHandlers.device_added/device_init), NOT installed by monkey-patching
-- `driver.lifecycle_handlers.added` after the driver is constructed. `Driver.init`
-- deep-copies `lifecycle_handlers` into `driver.lifecycle_dispatcher.default_handlers`
-- synchronously during `Driver(...)` construction, and all real dispatch goes through
-- that dispatcher -- so patching `driver.lifecycle_handlers` afterward is a no-op.
function M.wrap_device_emit_event(device)
  if device.emit_event and device.emit_event ~= wrapped_emit_event then
    if not original_emit_event then
      original_emit_event = device.emit_event
    end
    device.emit_event = wrapped_emit_event
  end
end

-- Wrap device_online/device_offline to capture online/offline changes.
-- Note: these are single-argument functions on `driver.device_api` (they take
-- the `device` table itself) -- NOT `try_update_metadata` (a per-device
-- profile/metadata updater with an unrelated signature).
local original_device_online = nil
local original_device_offline = nil

local function wrapped_device_online(device)
  capture_logger.log_device_status(
    device and device.id,
    true,
    "Device online"
  )

  return original_device_online(device)
end

local function wrapped_device_offline(device)
  capture_logger.log_device_status(
    device and device.id,
    false,
    "Device offline"
  )

  return original_device_offline(device)
end

-- Wrap create_device to capture device creation
-- Note: `driver.device_api.create_device` is a single-argument function that
-- takes a JSON-encoded string (see `Driver:try_create_device`), not
-- `(device_api, device_create_tbl)`. Decode defensively for logging and
-- always forward the original argument unchanged.
local original_create_device = nil

local function wrapped_create_device(device_info_json)
  local decode_ok, device_create_tbl = pcall(json.decode, device_info_json)
  if decode_ok and type(device_create_tbl) == "table" then
    capture_logger.log_device_create(
      device_create_tbl.parentDeviceId or "unknown",
      device_create_tbl
    )
  else
    capture_logger.log_device_create("unknown", device_info_json)
  end

  return original_create_device(device_info_json)
end

-- Wrap delete_device to capture device deletion
-- Note: `driver.device_api.delete_device` is a single-argument function
-- (device_uuid), not `(device_api, device_id)`.
local original_delete_device = nil

local function wrapped_delete_device(device_id)
  capture_logger.log_device_delete(device_id)

  return original_delete_device(device_id)
end

-- Wrap the driver to automatically capture device events
function M.wrap_driver(driver)
  log.info("[CAPTURE] Wrapping driver for event capture")

  -- NOTE: per-device hooks (emit_event, set_field) are NOT installed here.
  -- See `M.wrap_device_emit_event` / `M.wrap_device_set_field` -- they must be
  -- called directly from the lifecycle handlers themselves.

  -- Wrap device API methods for online/offline tracking
  if driver.device_api and driver.device_api.device_online then
    if not original_device_online then
      original_device_online = driver.device_api.device_online
    end
    driver.device_api.device_online = wrapped_device_online
  end

  if driver.device_api and driver.device_api.device_offline then
    if not original_device_offline then
      original_device_offline = driver.device_api.device_offline
    end
    driver.device_api.device_offline = wrapped_device_offline
  end
  
  -- Wrap device creation
  if driver.device_api and driver.device_api.create_device then
    if not original_create_device then
      original_create_device = driver.device_api.create_device
    end
    driver.device_api.create_device = wrapped_create_device
  end
  
  -- Wrap device deletion
  if driver.device_api and driver.device_api.delete_device then
    if not original_delete_device then
      original_delete_device = driver.device_api.delete_device
    end
    driver.device_api.delete_device = wrapped_delete_device
  end
  
  log.info("[CAPTURE] Driver wrapping complete")
end

-- Wrap device set_field to capture state changes
function M.wrap_device_set_field(device)
  if device._capture_wrapped then
    return  -- Already wrapped
  end
  
  local original_set_field = device.set_field
  
  device.set_field = function(dev, field, value, opts)
    -- Get old value before setting
    local old_value = dev:get_field(field)
    
    -- Call original
    local result = original_set_field(dev, field, value, opts)
    
    -- CAPTURE: Log field change
    if old_value ~= value then
      capture_logger.log_field_change(
        dev.id,
        field,
        old_value,
        value
      )
    end
    
    return result
  end
  
  device._capture_wrapped = true
end

return M
