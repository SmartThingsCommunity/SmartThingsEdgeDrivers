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
      clusters.CameraAvStreamManagement.attributes.StatusLightEnabled,
      clusters.OnOff.attributes.OnOff
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
    },
    [capabilities.switchLevel.ID] = {
      clusters.LevelControl.attributes.CurrentLevel,
      clusters.LevelControl.attributes.MaxLevel,
      clusters.LevelControl.attributes.MinLevel,
    },
    [capabilities.colorControl.ID] = {
      clusters.ColorControl.attributes.ColorMode,
      clusters.ColorControl.attributes.CurrentHue,
      clusters.ColorControl.attributes.CurrentSaturation,
      clusters.ColorControl.attributes.CurrentX,
      clusters.ColorControl.attributes.CurrentY,
    },
    [capabilities.colorTemperature.ID] = {
      clusters.ColorControl.attributes.ColorTemperatureMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
      clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
    },
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

  local im = require "st.matter.interaction_model"

  local subscribe_request = im.InteractionRequest(im.InteractionRequest.RequestType.SUBSCRIBE, {})
  local devices_seen, capabilities_seen, attributes_seen, events_seen = {}, {}, {}, {}

  if #device:get_endpoints(clusters.CameraAvStreamManagement.ID) > 0 then
    local ib = im.InteractionInfoBlock(nil, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.attributes.AttributeList.ID)
    subscribe_request:with_info_block(ib)
  end

  for _, endpoint_info in ipairs(device.endpoints) do
    local checked_device = switch_utils.find_child(device, endpoint_info.endpoint_id) or device
    if not devices_seen[checked_device.id] then
      switch_utils.populate_subscribe_request_for_device(checked_device, subscribe_request, capabilities_seen, attributes_seen, events_seen,
        camera_subscribed_attributes, camera_subscribed_events
      )
      devices_seen[checked_device.id] = true -- only loop through any device once
    end
  end

  if #subscribe_request.info_blocks > 0 then
    device:send(subscribe_request)
  end
end

return CameraUtils
