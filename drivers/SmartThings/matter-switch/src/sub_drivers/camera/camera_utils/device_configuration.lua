-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local button_cfg = require("switch_utils.device_configuration").ButtonCfg
local camera_fields = require "sub_drivers.camera.camera_utils.fields"
local camera_utils = require "sub_drivers.camera.camera_utils.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local device_cfg = require "switch_utils.device_configuration"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

local CameraDeviceConfiguration = {}

function CameraDeviceConfiguration.create_child_devices(driver, device)
  local num_floodlight_eps = 0
  local parent_child_device = false
  for _, ep in ipairs(device.endpoints or {}) do
    if device:supports_server_cluster(clusters.OnOff.ID, ep.endpoint_id) then
      local child_profile = device_cfg.SwitchCfg.assign_profile_for_onoff_ep(device, ep.endpoint_id)
      if child_profile then
        num_floodlight_eps = num_floodlight_eps + 1
        local name = string.format("%s %d", "Floodlight", num_floodlight_eps)
        driver:try_create_device(
          {
            type = "EDGE_CHILD",
            label = name,
            profile = child_profile,
            parent_device_id = device.id,
            parent_assigned_child_key = string.format("%d", ep.endpoint_id),
            vendor_provided_label = name
          }
        )
        parent_child_device = true
      end
    end
  end
  if parent_child_device then
    device:set_field(fields.IS_PARENT_CHILD_DEVICE, true, {persist = true})
    device:set_find_child(switch_utils.find_child)
  end
end

function CameraDeviceConfiguration.match_profile(device, status_light_enabled_present, status_light_brightness_present)
  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local status_led_component_capabilities = {}
  local speaker_component_capabilities = {}
  local microphone_component_capabilities = {}
  local doorbell_component_capabilities = {}

  local function has_server_cluster_type(cluster)
    return cluster.cluster_type == "SERVER" or cluster.cluster_type == "BOTH"
  end

  local camera_endpoints = switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.CAMERA)
  if #camera_endpoints > 0 then
    local camera_ep = switch_utils.get_endpoint_info(device, camera_endpoints[1])
    for _, ep_cluster in pairs(camera_ep.clusters or {}) do
      if ep_cluster.cluster_id == clusters.CameraAvStreamManagement.ID and has_server_cluster_type(ep_cluster) then
        local clus_has_feature = function(feature_bitmap)
          return clusters.CameraAvStreamManagement.are_features_supported(feature_bitmap, ep_cluster.feature_map)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.VIDEO) then
          table.insert(main_component_capabilities, capabilities.videoCapture2.ID)
          table.insert(main_component_capabilities, capabilities.cameraViewportSettings.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.LOCAL_STORAGE) then
          table.insert(main_component_capabilities, capabilities.localMediaStorage.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.AUDIO) then
          table.insert(main_component_capabilities, capabilities.audioRecording.ID)
          table.insert(microphone_component_capabilities, capabilities.audioMute.ID)
          table.insert(microphone_component_capabilities, capabilities.audioVolume.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.SNAPSHOT) then
          table.insert(main_component_capabilities, capabilities.imageCapture.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.PRIVACY) then
          table.insert(main_component_capabilities, capabilities.cameraPrivacyMode.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.SPEAKER) then
          table.insert(speaker_component_capabilities, capabilities.audioMute.ID)
          table.insert(speaker_component_capabilities, capabilities.audioVolume.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.IMAGE_CONTROL) then
          table.insert(main_component_capabilities, capabilities.imageControl.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.HIGH_DYNAMIC_RANGE) then
          table.insert(main_component_capabilities, capabilities.hdr.ID)
        end
        if clus_has_feature(clusters.CameraAvStreamManagement.types.Feature.NIGHT_VISION) then
          table.insert(main_component_capabilities, capabilities.nightVision.ID)
        end
      elseif ep_cluster.cluster_id == clusters.CameraAvSettingsUserLevelManagement.ID and has_server_cluster_type(ep_cluster) then
        local clus_has_feature = function(feature_bitmap)
          return clusters.CameraAvSettingsUserLevelManagement.are_features_supported(feature_bitmap, ep_cluster.feature_map)
        end
        if clus_has_feature(clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_PAN) or
          clus_has_feature(clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_TILT) or
          clus_has_feature(clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_ZOOM) then
          table.insert(main_component_capabilities, capabilities.mechanicalPanTiltZoom.ID)
        end
        table.insert(main_component_capabilities, capabilities.videoStreamSettings.ID)
      elseif ep_cluster.cluster_id == clusters.ZoneManagement.ID and has_server_cluster_type(ep_cluster) then
        table.insert(main_component_capabilities, capabilities.zoneManagement.ID)
      elseif ep_cluster.cluster_id == clusters.OccupancySensing.ID and has_server_cluster_type(ep_cluster) then
        table.insert(main_component_capabilities, capabilities.motionSensor.ID)
      elseif ep_cluster.cluster_id == clusters.WebRTCTransportProvider.ID and has_server_cluster_type(ep_cluster) and
        #device:get_endpoints(clusters.WebRTCTransportRequestor.ID, {cluster_type = "CLIENT"}) > 0 then
        table.insert(main_component_capabilities, capabilities.webrtc.ID)
      end
    end
  end
  local chime_endpoints = switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.CHIME)
  if #chime_endpoints > 0 then
    table.insert(main_component_capabilities, capabilities.sounds.ID)
  end
  local doorbell_endpoints = switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.DOORBELL)
  if #doorbell_endpoints > 0 then
    table.insert(doorbell_component_capabilities, capabilities.button.ID)
    CameraDeviceConfiguration.update_doorbell_component_map(device, doorbell_endpoints[1])
    button_cfg.configure_buttons(device)
  end
  if status_light_enabled_present then
    table.insert(status_led_component_capabilities, capabilities.switch.ID)
  end
  if status_light_brightness_present then
    table.insert(status_led_component_capabilities, capabilities.mode.ID)
  end

  table.insert(optional_supported_component_capabilities, {camera_fields.profile_components.main, main_component_capabilities})
  if #status_led_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {camera_fields.profile_components.statusLed, status_led_component_capabilities})
  end
  if #speaker_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {camera_fields.profile_components.speaker, speaker_component_capabilities})
  end
  if #microphone_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {camera_fields.profile_components.microphone, microphone_component_capabilities})
  end
  if #doorbell_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {camera_fields.profile_components.doorbell, doorbell_component_capabilities})
  end

  if camera_utils.optional_capabilities_list_changed(optional_supported_component_capabilities, device.profile.components) then
    device:try_update_metadata({profile = "camera", optional_component_capabilities = optional_supported_component_capabilities})
  end
end

local function init_webrtc(device)
  if device:supports_capability(capabilities.webrtc) then
    -- TODO: Check for individual audio/video and talkback features
    local transport_provider_ep_ids = device:get_endpoints(clusters.WebRTCTransportProvider.ID)
    device:emit_event_for_endpoint(transport_provider_ep_ids[1], capabilities.webrtc.supportedFeatures({
      value = {
        bundle = true,
        order = "audio/video",
        audio = "sendrecv",
        video = "recvonly",
        turnSource = "player",
        supportTrickleICE = true
      }
    }))
  end
end

local function init_ptz(device)
  if device:supports_capability(capabilities.mechanicalPanTiltZoom) then
    local supported_attributes = {}
    if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPAN) then
      table.insert(supported_attributes, "pan")
      table.insert(supported_attributes, "panRange")
    end
    if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MTILT) then
      table.insert(supported_attributes, "tilt")
      table.insert(supported_attributes, "tiltRange")
    end
    if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MZOOM) then
      table.insert(supported_attributes, "zoom")
      table.insert(supported_attributes, "zoomRange")
    end
    if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPRESETS) then
      table.insert(supported_attributes, "presets")
      table.insert(supported_attributes, "maxPresets")
    end
    local av_settings_ep_ids = device:get_endpoints(clusters.CameraAvSettingsUserLevelManagement.ID)
    device:emit_event_for_endpoint(av_settings_ep_ids[1], capabilities.mechanicalPanTiltZoom.supportedAttributes(supported_attributes))
  end
end

local function init_zone_management(device)
  if device:supports_capability(capabilities.zoneManagement) then
    local supported_features = {}
    table.insert(supported_features, "triggerAugmentation")
    if camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) then
      table.insert(supported_features, "perZoneSensitivity")
    end
    local zone_management_ep_ids = device:get_endpoints(clusters.ZoneManagement.ID)
    device:emit_event_for_endpoint(zone_management_ep_ids[1], capabilities.zoneManagement.supportedFeatures(supported_features))
  end
end

local function init_local_media_storage(device)
  if device:supports_capability(capabilities.localMediaStorage) then
    local supported_attributes = {}
    if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.VIDEO) then
      table.insert(supported_attributes, "localVideoRecording")
    end
    if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.SNAPSHOT) then
      table.insert(supported_attributes, "localSnapshotRecording")
    end
    local av_stream_management_ep_ids = device:get_endpoints(clusters.CameraAvStreamManagement.ID)
    device:emit_event_for_endpoint(av_stream_management_ep_ids[1], capabilities.localMediaStorage.supportedAttributes(supported_attributes))
  end
end

local function init_audio_recording(device)
  if device:supports_capability(capabilities.audioRecording) then
    local audio_enabled_state = device:get_latest_state(
      camera_fields.profile_components.main, capabilities.audioRecording.ID, capabilities.audioRecording.audioRecording.NAME
    )
    if audio_enabled_state == nil then
      -- Initialize with enabled default if state is unset
      local av_stream_management_ep_ids = device:get_endpoints(clusters.CameraAvStreamManagement.ID)
      device:emit_event_for_endpoint(av_stream_management_ep_ids[1], capabilities.audioRecording.audioRecording("enabled"))
    end
  end
end

local function init_video_stream_settings(device)
  if device:supports_capability(capabilities.videoStreamSettings) then
    local supported_features = {}
    if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.VIDEO) then
      table.insert(supported_features, "liveStreaming")
      table.insert(supported_features, "clipRecording")
      table.insert(supported_features, "perStreamViewports")
    end
    if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.WATERMARK) then
      table.insert(supported_features, "watermark")
    end
    if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.ON_SCREEN_DISPLAY) then
      table.insert(supported_features, "onScreenDisplay")
    end
    local av_stream_management_ep_ids = device:get_endpoints(clusters.CameraAvStreamManagement.ID)
    device:emit_event_for_endpoint(av_stream_management_ep_ids[1], capabilities.videoStreamSettings.supportedFeatures(supported_features))
  end
end

local function init_camera_privacy_mode(device)
  if device:supports_capability(capabilities.cameraPrivacyMode) then
    local supported_attributes, supported_commands = {}, {}
    table.insert(supported_attributes, "softRecordingPrivacyMode")
    table.insert(supported_attributes, "softLivestreamPrivacyMode")
    table.insert(supported_commands, "setSoftRecordingPrivacyMode")
    table.insert(supported_commands, "setSoftLivestreamPrivacyMode")
    local av_stream_management_ep_ids = device:get_endpoints(clusters.CameraAvStreamManagement.ID)
    device:emit_event_for_endpoint(av_stream_management_ep_ids[1], capabilities.cameraPrivacyMode.supportedAttributes(supported_attributes))
    device:emit_event_for_endpoint(av_stream_management_ep_ids[1], capabilities.cameraPrivacyMode.supportedCommands(supported_commands))
  end
end

function CameraDeviceConfiguration.initialize_camera_capabilities(device)
  init_webrtc(device)
  init_ptz(device)
  init_zone_management(device)
  init_local_media_storage(device)
  init_audio_recording(device)
  init_video_stream_settings(device)
  init_camera_privacy_mode(device)
end

function CameraDeviceConfiguration.update_doorbell_component_map(device, ep)
  local component_map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}
  component_map.doorbell = ep
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist = true})
end

return CameraDeviceConfiguration
