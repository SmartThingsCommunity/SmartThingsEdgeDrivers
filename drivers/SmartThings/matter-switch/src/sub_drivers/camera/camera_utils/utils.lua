-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local camera_fields = require "sub_drivers.camera.camera_utils.fields"
local capabilities = require "st.capabilities"
local switch_utils = require "switch_utils.utils"

local CameraUtils = {}

function CameraUtils.get_ptz_map(device)
  local mechanicalPanTiltZoom = capabilities.mechanicalPanTiltZoom
  local ptz_map = {
    [camera_fields.PAN_IDX] = {
      current = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.pan.NAME),
      range = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.panRange.NAME) or
        { minimum = camera_fields.ABS_PAN_MIN, maximum = camera_fields.ABS_PAN_MAX },
      attribute = mechanicalPanTiltZoom.pan
    },
    [camera_fields.TILT_IDX] = {
      current = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.tilt.NAME),
      range = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.tiltRange.NAME) or
        { minimum = camera_fields.ABS_TILT_MIN, maximum = camera_fields.ABS_TILT_MAX },
      attribute = mechanicalPanTiltZoom.tilt
    },
    [camera_fields.ZOOM_IDX] = {
      current = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.zoom.NAME),
      range = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.zoomRange.NAME) or
        { minimum = camera_fields.ABS_ZOOM_MIN, maximum = camera_fields.ABS_ZOOM_MAX },
      attribute = mechanicalPanTiltZoom.zoom
    }
  }
  return ptz_map
end

function CameraUtils.feature_supported(device, cluster_id, feature_flag)
  return #device:get_endpoints(cluster_id, { feature_bitmap = feature_flag }) > 0
end

function CameraUtils.update_supported_attributes(device, ib, capability, attribute)
  local attribute_set = device:get_latest_state(
    camera_fields.profile_components.main, capability.ID, capability.supportedAttributes.NAME
  ) or {}
  if not switch_utils.tbl_contains(attribute_set, attribute) then
    local updated_attribute_set = {}
    for _, v in ipairs(attribute_set) do
      table.insert(updated_attribute_set, v)
    end
    table.insert(updated_attribute_set, attribute)
    device:emit_event_for_endpoint(ib, capability.supportedAttributes(updated_attribute_set))
  end
end

function CameraUtils.compute_fps(max_encoded_pixel_rate, width, height, max_fps)
  local fps_step = 15.0
  local fps = math.min(max_encoded_pixel_rate / (width * height), max_fps)
  return math.tointeger(math.floor(fps / fps_step) * fps_step)
end

function CameraUtils.build_supported_resolutions(device, max_encoded_pixel_rate, max_fps)
  local resolutions = {}
  local added_resolutions = {}

  local function add_resolution(width, height)
    local key = width .. "x" .. height
    if not added_resolutions[key] then
      local resolution = { width = width, height = height }
      resolution.fps = CameraUtils.compute_fps(max_encoded_pixel_rate, width, height, max_fps)
      table.insert(resolutions, resolution)
      added_resolutions[key] = true
    end
  end

  local min_resolution = device:get_field(camera_fields.MIN_RESOLUTION)
  if min_resolution then
    add_resolution(min_resolution.width, min_resolution.height)
  end

  local trade_off_resolutions = device:get_field(camera_fields.SUPPORTED_RESOLUTIONS)
  for _, v in pairs(trade_off_resolutions or {}) do
    add_resolution(v.width, v.height)
  end

  local max_resolution = device:get_field(camera_fields.MAX_RESOLUTION)
  if max_resolution then
    add_resolution(max_resolution.width, max_resolution.height)
  end

  return resolutions
end

function CameraUtils.optional_capabilities_list_changed(new_component_capability_list, previous_component_capability_list)
  local previous_capability_map = {}
  local component_sizes = {}

  local previous_component_count = 0
  for component_name, component in pairs(previous_component_capability_list or {}) do
    previous_capability_map[component_name] = {}
    component_sizes[component_name] = 0
    for _, capability in pairs(component.capabilities or {}) do
      if capability.id ~= "firmwareUpdate" and capability.id ~= "refresh" then
        previous_capability_map[component_name][capability.id] = true
        component_sizes[component_name] = component_sizes[component_name] + 1
      end
    end
    previous_component_count = previous_component_count + 1
  end

  local number_of_components_counted = 0
  for _, new_component_capabilities in pairs(new_component_capability_list or {}) do
    local component_name = new_component_capabilities[1]
    local capability_list = new_component_capabilities[2]

    number_of_components_counted = number_of_components_counted + 1

    if previous_capability_map[component_name] == nil then
      return true
    end

    for _, capability in ipairs(capability_list) do
      if previous_capability_map[component_name][capability] == nil then
        return true
      end
    end

    if #capability_list ~= component_sizes[component_name] then
      return true
    end
  end

  if number_of_components_counted ~= previous_component_count then
    return true
  end

  return false
end

function CameraUtils.update_component_to_endpoint_map(device, component, endpoint_mapping)
  local fields = require "switch_utils.fields"
  local component_endpoint_map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}
  component_endpoint_map[component] = endpoint_mapping
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_endpoint_map, { persist = true })
end

return CameraUtils
