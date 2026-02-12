-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local camera_fields = require "sub_drivers.camera.utils.fields"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

local CameraUtils = {}

function CameraUtils.component_to_endpoint(device, component)
  local camera_eps = device:get_endpoints(clusters.CameraAvStreamManagement.ID)
  table.sort(camera_eps)
  for _, ep in ipairs(camera_eps or {}) do
    if ep ~= 0 then -- 0 is the matter RootNode endpoint
      return ep
    end
  end
  return nil
end

function CameraUtils.update_camera_component_map(device)
  local camera_av_ep_ids = device:get_endpoints(clusters.CameraAvStreamManagement.ID)
  if #camera_av_ep_ids > 0 then
    -- An assumption here: there is only 1 CameraAvStreamManagement cluster on the device (which is all our profile supports)
    local component_map = {}
    if CameraUtils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.AUDIO) then
      component_map.microphone = {
        endpoint_id = camera_av_ep_ids[1],
        cluster_id = clusters.CameraAvStreamManagement.ID,
        attribute_ids = {
          clusters.CameraAvStreamManagement.attributes.MicrophoneMuted.ID,
          clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel.ID,
          clusters.CameraAvStreamManagement.attributes.MicrophoneMaxLevel.ID,
          clusters.CameraAvStreamManagement.attributes.MicrophoneMinLevel.ID,
        },
      }
    end
    if CameraUtils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.VIDEO) then
      component_map.speaker = {
        endpoint_id = camera_av_ep_ids[1],
        cluster_id = clusters.CameraAvStreamManagement.ID,
        attribute_ids = {
          clusters.CameraAvStreamManagement.attributes.SpeakerMuted.ID,
          clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel.ID,
          clusters.CameraAvStreamManagement.attributes.SpeakerMaxLevel.ID,
          clusters.CameraAvStreamManagement.attributes.SpeakerMinLevel.ID,
        },
      }
    end
    device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
  end
end

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

function CameraUtils.profile_changed(synced_components, prev_components)
  if #synced_components ~= #prev_components then
    return true
  end
  for _, component in pairs(synced_components or {}) do
    if (prev_components[component.id] == nil) or
      (#component.capabilities ~= #prev_components[component.id].capabilities) then
      return true
    end
    for _, capability in pairs(component.capabilities or {}) do
      if prev_components[component.id][capability.id] == nil then
        return true
      end
    end
  end
  return false
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

return CameraUtils
