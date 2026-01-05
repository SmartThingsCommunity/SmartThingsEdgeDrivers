-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local camera_fields = require "sub_drivers.camera.camera_utils.fields"
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

function CameraUtils.optional_capabilities_list_changed(optional_capabilities, prev_component_list)
  local prev_optional_capabilities = {}
  for idx, comp in pairs(prev_component_list or {}) do
    local cap_list = {}
    for _, capability in pairs(comp.capabilities or {}) do
      table.insert(cap_list, capability.id)
    end
    table.insert(prev_optional_capabilities, {idx, cap_list})
  end
  if #optional_capabilities ~= #prev_optional_capabilities then
    return true
  end
  for _, capability in pairs(optional_capabilities or {}) do
    if not switch_utils.tbl_contains(prev_optional_capabilities, capability) then
      return true
    end
  end
  for _, capability in pairs(prev_optional_capabilities or {}) do
    if not switch_utils.tbl_contains(optional_capabilities, capability) then
      return true
    end
  end
  return false
end

function CameraUtils.subscribe(device)
  local camera_subscribed_attributes = {
    [capabilities.hdr.ID] = {
      clusters.CameraAvStreamManagement.attributes.HDRModeEnabled,
      clusters.CameraAvStreamManagement.attributes.ImageRotation
    },
    [capabilities.nightVision.ID] = {
      clusters.CameraAvStreamManagement.attributes.NightVision,
      clusters.CameraAvStreamManagement.attributes.NightVisionIllum
    },
    [capabilities.imageControl.ID] = {
      clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal,
      clusters.CameraAvStreamManagement.attributes.ImageFlipVertical
    },
    [capabilities.cameraPrivacyMode.ID] = {
      clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled,
      clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled,
      clusters.CameraAvStreamManagement.attributes.HardPrivacyModeOn
    },
    [capabilities.webrtc.ID] = {
      clusters.CameraAvStreamManagement.attributes.TwoWayTalkSupport
    },
    [capabilities.mechanicalPanTiltZoom.ID] = {
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPresets,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MaxPresets,
      clusters.CameraAvSettingsUserLevelManagement.attributes.ZoomMax,
      clusters.CameraAvSettingsUserLevelManagement.attributes.PanMax,
      clusters.CameraAvSettingsUserLevelManagement.attributes.PanMin,
      clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMax,
      clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMin
    },
    [capabilities.audioMute.ID] = {
      clusters.CameraAvStreamManagement.attributes.SpeakerMuted,
      clusters.CameraAvStreamManagement.attributes.MicrophoneMuted
    },
    [capabilities.audioVolume.ID] = {
      clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel,
      clusters.CameraAvStreamManagement.attributes.SpeakerMaxLevel,
      clusters.CameraAvStreamManagement.attributes.SpeakerMinLevel,
      clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel,
      clusters.CameraAvStreamManagement.attributes.MicrophoneMaxLevel,
      clusters.CameraAvStreamManagement.attributes.MicrophoneMinLevel
    },
    [capabilities.mode.ID] = {
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness
    },
    [capabilities.switch.ID] = {
      clusters.CameraAvStreamManagement.attributes.StatusLightEnabled
    },
    [capabilities.videoStreamSettings.ID] = {
      clusters.CameraAvStreamManagement.attributes.RateDistortionTradeOffPoints,
      clusters.CameraAvStreamManagement.attributes.MaxEncodedPixelRate,
      clusters.CameraAvStreamManagement.attributes.VideoSensorParams,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams
    },
    [capabilities.zoneManagement.ID] = {
      clusters.ZoneManagement.attributes.MaxZones,
      clusters.ZoneManagement.attributes.Zones,
      clusters.ZoneManagement.attributes.Triggers,
      clusters.ZoneManagement.attributes.SensitivityMax,
      clusters.ZoneManagement.attributes.Sensitivity
    },
    [capabilities.sounds.ID] = {
      clusters.Chime.attributes.InstalledChimeSounds,
      clusters.Chime.attributes.SelectedChime
    },
    [capabilities.localMediaStorage.ID] = {
      clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled,
      clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled
    },
    [capabilities.cameraViewportSettings.ID] = {
      clusters.CameraAvStreamManagement.attributes.MinViewportResolution,
      clusters.CameraAvStreamManagement.attributes.VideoSensorParams,
      clusters.CameraAvStreamManagement.attributes.Viewport
    },
    [capabilities.motionSensor.ID] = {
      clusters.OccupancySensing.attributes.Occupancy
    }
  }
  local camera_subscribed_events = {
    [capabilities.zoneManagement.ID] = {
      clusters.ZoneManagement.events.ZoneTriggered,
      clusters.ZoneManagement.events.ZoneStopped
    },
    [capabilities.button.ID] = {
      clusters.Switch.events.InitialPress,
      clusters.Switch.events.LongPress,
      clusters.Switch.events.ShortRelease,
      clusters.Switch.events.MultiPressComplete
    }
  }

  for capability, attr_list in pairs(camera_subscribed_attributes) do
    if device:supports_capability_by_id(capability) then
      for _, attr in pairs(attr_list) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  for capability, event_list in pairs(camera_subscribed_events) do
    if device:supports_capability_by_id(capability) then
      for _, event in pairs(event_list) do
        device:add_subscribed_event(event)
      end
    end
  end

  -- match_profile is called from the CameraAvStreamManagement AttributeList handler,
  -- so the subscription needs to be added here first
  if #device:get_endpoints(clusters.CameraAvStreamManagement.ID) > 0 then
    device:add_subscribed_attribute(clusters.CameraAvStreamManagement.attributes.AttributeList)
  end

  -- Add subscription for attributes specific to child devices
  if device:get_field(fields.IS_PARENT_CHILD_DEVICE) then
    for _, ep in ipairs(device.endpoints or {}) do
      local id = 0
      for _, dt in ipairs(ep.device_types or {}) do
        if dt.device_type_id ~= fields.DEVICE_TYPE_ID.GENERIC_SWITCH then
          id = math.max(id, dt.device_type_id)
        end
      end
      for _, attr in pairs(fields.device_type_attribute_map[id] or {}) do
        device:add_subscribed_attribute(attr)
      end
    end
  end

  local im = require "st.matter.interaction_model"
  local subscribed_attributes = device:get_field("__subscribed_attributes") or {}
  local subscribed_events = device:get_field("__subscribed_events") or {}
  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  for _, attributes in pairs(subscribed_attributes) do
    for _, ib in pairs(attributes) do
      subscribe_request:with_info_block(ib)
    end
  end
  for _, events in pairs(subscribed_events) do
    for _, ib in pairs(events) do
      subscribe_request:with_info_block(ib)
    end
  end
  if #subscribe_request.info_blocks > 0 then
    device:send(subscribe_request)
  end
end

return CameraUtils
