-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local fields = require "sensor_utils.fields"

local utils = {}

function utils.get_field_for_endpoint(device, field, endpoint)
  return device:get_field(string.format("%s_%d", field, endpoint))
end

function utils.set_field_for_endpoint(device, field, endpoint, value, additional_params)
  device:set_field(string.format("%s_%d", field, endpoint), value, additional_params)
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

function utils.get_endpoint_info(device, endpoint_id)
  for _, ep in ipairs(device.endpoints) do
    if ep.endpoint_id == endpoint_id then return ep end
  end
  return {}
end

function utils.primary_device_type(ep_info)
  if #ep_info.device_types == 1 then
    -- generically, device types should be unique on an endpoint  
    return ep_info.device_types[1].device_type_id
  else
    for _, dt in ipairs(ep_info.device_types) do
      if dt.device_type_id == fields.DEVICE_TYPE_ID.POWER_SOURCE then
        -- Power Source can be attached to some device types. Ex. Root Node
        return fields.DEVICE_TYPE_ID.POWER_SOURCE
      end
    end
  end
  return ep_info.device_types[1].device_type_id
end

return utils
