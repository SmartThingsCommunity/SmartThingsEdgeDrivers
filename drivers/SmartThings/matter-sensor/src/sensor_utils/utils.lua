-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local fields = require "sensor_utils.fields"

local utils = {}

-- Sanity check bounds for soil moisture measurement limits (percent)
utils.SOIL_MOISTURE_MIN = 0
utils.SOIL_MOISTURE_MAX = 100

function utils.get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

function utils.set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
end

function utils.get_product_override_field(device, override_key)
  if device.manufacturer_info
  and fields.vendor_overrides[device.manufacturer_info.vendor_id]
  and fields.vendor_overrides[device.manufacturer_info.vendor_id][device.manufacturer_info.product_id]
  then
    return fields.vendor_overrides[device.manufacturer_info.vendor_id][device.manufacturer_info.product_id][override_key]
  end
end

function utils.tbl_contains(array, value)
  if value == nil then return false end
  for _, element in pairs(array or {}) do
    if element == value then
      return true
    end
  end
  return false
end

--- Deeply compare two values.
--- Handles metatables. Can optionally ignore cycle checking and/or function differences.
---
--- @param a any
--- @param b any
--- @param opts table|nil { ignore_functions = boolean, ignore_cycles = boolean }
--- @param seen table|nil
--- @return boolean
function utils.deep_equals(a, b, opts, seen)
  if a == b then return true end -- same object
  if type(a) ~= type(b) then return false end -- different type
  if type(a) == "function" and opts and opts.ignore_functions then return true end
  if type(a) ~= "table" then return false end -- same type but not table, thus was already compared

  -- check for cycles in table references and preserve reference topology.
  if not (opts and opts.ignore_cycles) then
    seen = seen or {}
    seen[a] = seen[a] or {}
    if seen[a][b] then
      return seen[a][b]
    end
    seen[a][b] = true
  end

  -- Compare keys/values from a
  for k, v in pairs(a) do
    if not utils.deep_equals(v, b[k], opts, seen) then
      return false
    end
  end

  -- Ensure b doesn't have extra keys
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end

  -- Compare metatables
  local mt_a = getmetatable(a)
  local mt_b = getmetatable(b)
  return utils.deep_equals(mt_a, mt_b, opts, seen)
end

return utils
