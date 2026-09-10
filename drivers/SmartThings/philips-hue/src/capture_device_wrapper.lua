--[[
  Device Wrapper for Capture Logging
  
  This module wraps device methods to automatically capture IPC communication:
  - emit_event: Captures all outgoing capability events
  - online/offline: Captures device status changes
  
  Usage:
    Call capture_device_wrapper.wrap_driver(driver) in driver initialization
]]

local capture_logger = require "capture_logger"
local log = require "log"

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

-- Wrap device online/offline methods
local original_try_update_metadata = nil

local function wrapped_try_update_metadata(device_api, device_id, update_tbl)
  -- Check if this is an online/offline change
  if update_tbl and update_tbl.online ~= nil then
    capture_logger.log_device_status(
      device_id,
      update_tbl.online,
      "Metadata update"
    )
  end
  
  return original_try_update_metadata(device_api, device_id, update_tbl)
end

-- Wrap create_device to capture device creation
local original_create_device = nil

local function wrapped_create_device(device_api, device_create_tbl)
  capture_logger.log_device_create(
    device_create_tbl.parentDeviceId or "unknown",
    device_create_tbl
  )
  
  return original_create_device(device_api, device_create_tbl)
end

-- Wrap delete_device to capture device deletion
local original_delete_device = nil

local function wrapped_delete_device(device_api, device_id)
  capture_logger.log_device_delete(device_id)
  
  return original_delete_device(device_api, device_id)
end

-- Wrap the driver to automatically capture device events
function M.wrap_driver(driver)
  log.info("[CAPTURE] Wrapping driver for event capture")
  
  -- Wrap device emit_event method
  -- This needs to be done for all devices, so we wrap it in the driver's device_added callback
  local original_device_added = driver.lifecycle_handlers.added
  
  driver.lifecycle_handlers.added = function(driver, device, ...)
    -- Wrap this device's emit_event if not already wrapped
    if device.emit_event and device.emit_event ~= wrapped_emit_event then
      if not original_emit_event then
        original_emit_event = device.emit_event
      end
      device.emit_event = wrapped_emit_event
    end
    
    -- Call original added handler
    if original_device_added then
      return original_device_added(driver, device, ...)
    end
  end
  
  -- Wrap device API methods for online/offline tracking
  if driver.device_api and driver.device_api.try_update_metadata then
    if not original_try_update_metadata then
      original_try_update_metadata = driver.device_api.try_update_metadata
    end
    driver.device_api.try_update_metadata = wrapped_try_update_metadata
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
