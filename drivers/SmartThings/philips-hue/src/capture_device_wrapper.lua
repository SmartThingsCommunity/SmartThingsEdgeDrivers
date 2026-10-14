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

    Call capture_device_wrapper.wrap_device_set_field(device) from the device
    lifecycle handlers themselves (device_added/device_init). It can't be
    installed via a post-construction `driver.lifecycle_handlers` patch, since
    the lifecycle dispatcher is built from a deep copy of `lifecycle_handlers`
    at construction time.

    Capability events are captured in `emit_component_event_no_cache`
    (handlers/lifecycle_handlers/init.lua), which every Hue device emit goes through.
]]

local capture_logger = require "capture_logger"
local log = require "log"
local json = require "st.json"

local M = {}

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

  -- Per-device hooks are NOT installed here; see the module header.

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

-- Device objects are read-only (assigning a field throws), so we can't mark a
-- device as wrapped on the device itself.
local set_field_wrapped = setmetatable({}, { __mode = "k" })

-- Wrap device set_field to capture state changes. Uses `extend_device`, the
-- framework's supported override hook, because direct assignment to a Device throws.
function M.wrap_device_set_field(device)
  if set_field_wrapped[device] then
    return
  end

  local original_set_field = device.set_field

  device:extend_device("set_field", function(dev, field, value, opts)
    local old_value = dev:get_field(field)
    local result = original_set_field(dev, field, value, opts)

    if old_value ~= value then
      local ok, err = pcall(capture_logger.log_field_change, dev.id, field, old_value, value)
      if not ok then
        log.warn("[CAPTURE] Failed to log field change: " .. tostring(err))
      end
    end

    return result
  end)

  set_field_wrapped[device] = true
end

return M
