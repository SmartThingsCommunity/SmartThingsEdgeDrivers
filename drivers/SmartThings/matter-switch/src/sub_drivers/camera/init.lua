-- Copyright 2025 SmartThings
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-------------------------------------------------------------------------------------
-- Matter Camera Sub Driver
-------------------------------------------------------------------------------------

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local cfg = require "utils.device_configuration"
local switch_utils = require "utils.switch_utils"
local utils = require "st.utils"

local CAMERA_INITIALIZED = "__camera_initialized"
local IS_PARENT_CHILD_DEVICE = "__is_parent_child_device"
local MAX_ENCODED_PIXEL_RATE = "__max_encoded_pixel_rate"
local MAX_FRAMES_PER_SECOND = "__max_frames_per_second"
local MAX_VOLUME_LEVEL = "__max_volume_level"
local MIN_VOLUME_LEVEL = "__min_volume_level"
local OPTIONAL_SUPPORTED_COMPONENT_CAPABILITIES = "__optional_supported_component_capabilities"
local SUPPORTED_RESOLUTIONS = "__supported_resolutions"
local TRIGGERED_ZONES = "__triggered_zones"
local VIEWPORT = "__viewport"

local PAN_IDX = "PAN"
local TILT_IDX = "TILT"
local ZOOM_IDX = "ZOOM"

local pt_range_fields = {
  [PAN_IDX] = { max = "__MAX_PAN" , min = "__MIN_PAN" },
  [TILT_IDX] = { max = "__MAX_TILT" , min = "__MIN_TILT" }
}

local component_map = {
  main = "main",
  statusLed = "statusLed",
  speaker = "speaker",
  microphone = "microphone",
  doorbell = "doorbell"
}

local tri_state_map = {
  [clusters.CameraAvStreamManagement.types.TriStateAutoEnum.OFF] = "off",
  [clusters.CameraAvStreamManagement.types.TriStateAutoEnum.ON] = "on",
  [clusters.CameraAvStreamManagement.types.TriStateAutoEnum.AUTO] = "auto"
}

local subscribed_attributes = {
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

local subscribed_events = {
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

local ON_OFF_LIGHT_DEVICE_TYPE_ID = 0x0100
local DIMMABLE_LIGHT_DEVICE_TYPE_ID = 0x0101
local COLOR_TEMP_LIGHT_DEVICE_TYPE_ID = 0x010C
local EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID = 0x010D

local ABS_PAN_MAX, ABS_PAN_MIN = 180, -180
local ABS_TILT_MAX, ABS_TILT_MIN = 180, -180
local ABS_ZOOM_MAX, ABS_ZOOM_MIN = 100, 1
local ABS_VOL_MAX, ABS_VOL_MIN = 254.0, 0.0

-- Helper Functions

local function is_camera(opts, driver, device)
  local device_lib = require "st.device"
  if device.network_type == device_lib.NETWORK_TYPE_MATTER then
    local version = require "version"
    if version.rpc < 10 or version.api < 16 then
      device.log.warn(string.format("Matter Camera not supported on current firmware version"))
      return false
    end
    for _, ep in ipairs(device.endpoints) do
      for _, dt in ipairs(ep.device_types) do
        if dt.device_type_id == 0x0142 then -- 0x0142 is the Camera device type ID
          return true
        end
      end
    end
  end
  return false
end

local function component_to_endpoint(device, component)
  local camera_eps = device:get_endpoints(clusters.CameraAvStreamManagement.ID)
  table.sort(camera_eps)
  for _, ep in ipairs(camera_eps) do
    if ep ~= 0 then -- 0 is the matter RootNode endpoint
      return ep
    end
  end
  return nil
end

local function get_ptz_map(device)
  local mechanicalPanTiltZoom = capabilities.mechanicalPanTiltZoom
  local ptz_map = {
    [PAN_IDX] = {
      current = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.pan.NAME),
      range = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.panRange.NAME) or
        { minimum = ABS_PAN_MIN, maximum = ABS_PAN_MAX },
      attribute = mechanicalPanTiltZoom.pan
    },
    [TILT_IDX] = {
      current = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.tilt.NAME),
      range = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.tiltRange.NAME) or
        { minimum = ABS_TILT_MIN, maximum = ABS_TILT_MAX },
      attribute = mechanicalPanTiltZoom.tilt
    },
    [ZOOM_IDX] = {
      current = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.zoom.NAME),
      range = device:get_latest_state("main", mechanicalPanTiltZoom.ID, mechanicalPanTiltZoom.zoomRange.NAME) or
        { minimum = ABS_ZOOM_MIN, maximum = ABS_ZOOM_MAX },
      attribute = mechanicalPanTiltZoom.zoom
    }
  }
  return ptz_map
end

local function feature_supported(device, cluster_id, feature_flag)
  return #device:get_endpoints(cluster_id, { feature_bitmap = feature_flag }) > 0
end

local function update_supported_attributes(device, component, capability, attribute)
  local attribute_set = device:get_latest_state(
    component_map.main, capability.ID, capability.supportedAttributes.NAME
  ) or {}
  if not switch_utils.tbl_contains(attribute_set, attribute) then
    local updated_attribute_set = {}
    for _, v in ipairs(attribute_set) do
      table.insert(updated_attribute_set, v)
    end
    table.insert(updated_attribute_set, attribute)
    device:emit_component_event(component, capability.supportedAttributes(updated_attribute_set))
  end
end

local function compute_fps(max_encoded_pixel_rate, width, height, max_fps)
  local fps_step = 15.0
  local fps = math.min(max_encoded_pixel_rate / (width * height), max_fps)
  return math.tointeger(math.floor(fps / fps_step) * fps_step)
end

local function compare_components(synced_components, prev_components)
  if #synced_components ~= #prev_components then
    return false
  end
  for _, component in pairs(synced_components) do
    if (prev_components[component.id] == nil) or
      (#component.capabilities ~= #prev_components[component.id].capabilities) then
      return false
    end
    for _, capability in pairs(component.capabilities) do
      if prev_components[component.id][capability.id] == nil then
        return false
      end
    end
  end
  return true
end

local function compare_optional_capabilities(optional_capabilities, prev_optional_capabilities)
  if #optional_capabilities ~= #prev_optional_capabilities then
    return false
  end
  for _, capability in pairs(optional_capabilities) do
    if not switch_utils.tbl_contains(prev_optional_capabilities, capability) then
      return false
    end
  end
  for _, capability in pairs(prev_optional_capabilities) do
    if not switch_utils.tbl_contains(optional_capabilities, capability) then
      return false
    end
  end
  return true
end

local function subscribe(device)
  if #device:get_endpoints(clusters.CameraAvStreamManagement.ID) > 0 then
    device:add_subscribed_attribute(clusters.CameraAvStreamManagement.attributes.AttributeList)
  end
  for capability, attr_list in pairs(subscribed_attributes) do
    if device:supports_capability_by_id(capability) then
      for _, attr in pairs(attr_list) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  for capability, event_list in pairs(subscribed_events) do
    if device:supports_capability_by_id(capability) then
      for _, event in pairs(event_list) do
        device:add_subscribed_event(event)
      end
    end
  end
  if device:get_field(IS_PARENT_CHILD_DEVICE) then
    local device_type_attribute_map = {
      [ON_OFF_LIGHT_DEVICE_TYPE_ID] = {
        clusters.OnOff.attributes.OnOff
      },
      [DIMMABLE_LIGHT_DEVICE_TYPE_ID] = {
        clusters.OnOff.attributes.OnOff,
        clusters.LevelControl.attributes.CurrentLevel,
        clusters.LevelControl.attributes.MaxLevel,
        clusters.LevelControl.attributes.MinLevel
      },
      [COLOR_TEMP_LIGHT_DEVICE_TYPE_ID] = {
        clusters.OnOff.attributes.OnOff,
        clusters.LevelControl.attributes.CurrentLevel,
        clusters.LevelControl.attributes.MaxLevel,
        clusters.LevelControl.attributes.MinLevel,
        clusters.ColorControl.attributes.ColorTemperatureMireds,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds
      },
      [EXTENDED_COLOR_LIGHT_DEVICE_TYPE_ID] = {
        clusters.OnOff.attributes.OnOff,
        clusters.LevelControl.attributes.CurrentLevel,
        clusters.LevelControl.attributes.MaxLevel,
        clusters.LevelControl.attributes.MinLevel,
        clusters.ColorControl.attributes.ColorTemperatureMireds,
        clusters.ColorControl.attributes.ColorTempPhysicalMaxMireds,
        clusters.ColorControl.attributes.ColorTempPhysicalMinMireds,
        clusters.ColorControl.attributes.CurrentHue,
        clusters.ColorControl.attributes.CurrentSaturation,
        clusters.ColorControl.attributes.CurrentX,
        clusters.ColorControl.attributes.CurrentY
      }
    }
    for _, ep in ipairs(device.endpoints) do
      local id = 0
      for _, dt in ipairs(ep.device_types) do
        id = math.max(id, dt.device_type_id)
      end
      for _, attr in pairs(device_type_attribute_map[id] or {}) do
        device:add_subscribed_attribute(attr)
      end
    end
  end
  device:subscribe()
end

local function init_webrtc(device)
  -- TODO: Check for individual audio/video and talkback features
  if #device:get_endpoints(clusters.WebRTCTransportProvider.ID) > 0 then
    local component = device.profile.components[component_map.main]
    device:emit_component_event(component, capabilities.webrtc.supportedFeatures({
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
  local supported_attributes = {}
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPAN) then
    table.insert(supported_attributes, "pan")
    table.insert(supported_attributes, "panRange")
  end
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MTILT) then
    table.insert(supported_attributes, "tilt")
    table.insert(supported_attributes, "tiltRange")
  end
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MZOOM) then
    table.insert(supported_attributes, "zoom")
    table.insert(supported_attributes, "zoomRange")
  end
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPRESETS) then
    table.insert(supported_attributes, "presets")
    table.insert(supported_attributes, "maxPresets")
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.mechanicalPanTiltZoom.supportedAttributes(supported_attributes))
end

local function init_zone_management(device)
  local supported_features = {}
  if #device:get_endpoints(clusters.ZoneManagement.ID) > 0 then
    table.insert(supported_features, "triggerAugmentation")
  end
  if feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) then
    table.insert(supported_features, "perZoneSensitivity")
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.zoneManagement.supportedFeatures(supported_features))
end

local function init_local_media_storage(device)
  local supported_attributes = {}
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.LOCAL_STORAGE) then
    if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.VIDEO) then
      table.insert(supported_attributes, "localVideoRecording")
    end
    if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.SNAPSHOT) then
      table.insert(supported_attributes, "localSnapshotRecording")
    end
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.localMediaStorage.supportedAttributes(supported_attributes))
end

local function init_audio_recording(device)
  local component = device.profile.components[component_map.main]
  local audio_enabled_state = device:get_latest_state(
    component_map.main, capabilities.audioRecording.ID, capabilities.audioRecording.audioRecording.NAME
  )
  if audio_enabled_state == nil then
    -- Initialize with enabled default if state is unset
    device:emit_component_event(component, capabilities.audioRecording.audioRecording("enabled"))
  end
end

local function init_video_stream_settings(device)
  local supported_features = {}
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.VIDEO) then
    table.insert(supported_features, "liveStreaming")
    table.insert(supported_features, "clipRecording")
    table.insert(supported_features, "perStreamViewports")
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.WATERMARK) then
    table.insert(supported_features, "watermark")
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.ON_SCREEN_DISPLAY) then
    table.insert(supported_features, "onScreenDisplay")
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.videoStreamSettings.supportedFeatures(supported_features))
end

local function init_camera_privacy_mode(device)
  local supported_attributes, supported_commands = {}, {}
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.PRIVACY) then
    table.insert(supported_attributes, "softRecordingPrivacyMode")
    table.insert(supported_attributes, "softLivestreamPrivacyMode")
    table.insert(supported_commands, "setSoftRecordingPrivacyMode")
    table.insert(supported_commands, "setSoftLivestreamPrivacyMode")
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.cameraPrivacyMode.supportedAttributes(supported_attributes))
  device:emit_component_event(component, capabilities.cameraPrivacyMode.supportedCommands(supported_commands))
end

local function match_profile(device, status_light_enabled_present, status_light_brightness_present)
  local optional_supported_component_capabilities = {}
  local main_component_capabilities = {}
  local status_led_component_capabilities = {}
  local speaker_component_capabilities = {}
  local microphone_component_capabilities = {}
  local doorbell_component_capabilities = {}

  if #device:get_endpoints(clusters.WebRTCTransportProvider.ID, {cluster_type = "SERVER"}) > 0 and
    #device:get_endpoints(clusters.WebRTCTransportRequestor.ID, {cluster_type = "CLIENT"}) > 0 then
    table.insert(main_component_capabilities, capabilities.webrtc.ID)
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.VIDEO) then
    table.insert(main_component_capabilities, capabilities.videoCapture2.ID)
    table.insert(main_component_capabilities, capabilities.cameraViewportSettings.ID)
    if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.LOCAL_STORAGE) then
      table.insert(main_component_capabilities, capabilities.localMediaStorage.ID)
    end
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.AUDIO) then
    table.insert(main_component_capabilities, capabilities.audioRecording.ID)
    table.insert(microphone_component_capabilities, capabilities.audioMute.ID)
    table.insert(microphone_component_capabilities, capabilities.audioVolume.ID)
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.SNAPSHOT) then
    table.insert(main_component_capabilities, capabilities.imageCapture.ID)
    if not switch_utils.tbl_contains(main_component_capabilities, capabilities.localMediaStorage.ID) and
      feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.LOCAL_STORAGE) then
      table.insert(main_component_capabilities, capabilities.localMediaStorage.ID)
    end
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.PRIVACY) then
    table.insert(main_component_capabilities, capabilities.cameraPrivacyMode.ID)
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.SPEAKER) then
    table.insert(speaker_component_capabilities, capabilities.audioMute.ID)
    table.insert(speaker_component_capabilities, capabilities.audioVolume.ID)
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.IMAGE_CONTROL) then
    table.insert(main_component_capabilities, capabilities.imageControl.ID)
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.HIGH_DYNAMIC_RANGE) then
    table.insert(main_component_capabilities, capabilities.hdr.ID)
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.NIGHT_VISION) then
    table.insert(main_component_capabilities, capabilities.nightVision.ID)
  end
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_PAN) or
    feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_TILT) or
    feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_ZOOM) then
    table.insert(main_component_capabilities, capabilities.mechanicalPanTiltZoom.ID)
  end
  if #device:get_endpoints(clusters.ZoneManagement.ID) > 0 then
    table.insert(main_component_capabilities, capabilities.zoneManagement.ID)
  end
  if #device:get_endpoints(clusters.CameraAvSettingsUserLevelManagement.ID) > 0 then
    table.insert(main_component_capabilities, capabilities.videoStreamSettings.ID)
  end
  if #device:get_endpoints(clusters.Chime.ID) > 0 then
    table.insert(main_component_capabilities, capabilities.sounds.ID)
  end
  if #device:get_endpoints(clusters.OccupancySensing.ID) > 0 then
    table.insert(main_component_capabilities, capabilities.motionSensor.ID)
  end
  if status_light_enabled_present then
    table.insert(status_led_component_capabilities, capabilities.switch.ID)
  end
  if status_light_brightness_present then
    table.insert(status_led_component_capabilities, capabilities.mode.ID)
  end
  for _, ep in ipairs(device.endpoints) do
    if switch_utils.tbl_contains(device:get_endpoints(clusters.Switch.ID) or {}, ep.endpoint_id) then
      for _, dt in ipairs(ep.device_types) do
        if dt == 0x0143 then
          table.insert(doorbell_component_capabilities, capabilities.button.ID)
          break
        end
      end
    end
  end

  table.insert(optional_supported_component_capabilities, {component_map.main, main_component_capabilities})
  if #status_led_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {component_map.statusLed, status_led_component_capabilities})
  end
  if #speaker_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {component_map.speaker, speaker_component_capabilities})
  end
  if #microphone_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {component_map.microphone, microphone_component_capabilities})
  end
  if #doorbell_component_capabilities > 0 then
    table.insert(optional_supported_component_capabilities, {component_map.doorbell, doorbell_component_capabilities})
  end

  if not device:get_field(CAMERA_INITIALIZED) or
    not compare_optional_capabilities(optional_supported_component_capabilities, device:get_field(OPTIONAL_SUPPORTED_COMPONENT_CAPABILITIES) or {}) then
    device:try_update_metadata({profile = "matter-camera", optional_component_capabilities = optional_supported_component_capabilities})
    device:set_field(CAMERA_INITIALIZED, true, {persist = true})
    device:set_field(OPTIONAL_SUPPORTED_COMPONENT_CAPABILITIES, optional_supported_component_capabilities, {persist = true})
  end
end

local function initialize_camera_capabilities(device)
  if device:supports_capability(capabilities.webrtc) then
    init_webrtc(device)
  end

  if device:supports_capability(capabilities.mechanicalPanTiltZoom) then
    init_ptz(device)
  end

  if device:supports_capability(capabilities.zoneManagement) then
    init_zone_management(device)
  end

  if device:supports_capability(capabilities.localMediaStorage) then
    init_local_media_storage(device)
  end

  if device:supports_capability(capabilities.audioRecording) then
    init_audio_recording(device)
  end

  if device:supports_capability(capabilities.videoStreamSettings) then
    init_video_stream_settings(device)
  end

  if device:supports_capability(capabilities.cameraPrivacyMode) then
    init_camera_privacy_mode(device)
  end
end

-- Lifecycle Handlers

local function device_init(driver, device)
  device:set_component_to_endpoint_fn(component_to_endpoint)
  if not device:get_field(CAMERA_INITIALIZED) then
    if #device:get_endpoints(clusters.CameraAvStreamManagement.ID) == 0 then
      match_profile(device, false, false)
    end
    local num_floodlight_eps = 0
    local parent_child_device = false
    for _, ep in ipairs(device.endpoints) do
      if device:supports_server_cluster(clusters.OnOff.ID, ep.endpoint_id) then
        local child_profile = cfg.SwitchCfg.assign_child_profile(device, ep.endpoint_id)
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
      device:set_field(IS_PARENT_CHILD_DEVICE, true, {persist = true})
    end
    initialize_camera_capabilities(device)
  end
  if device:get_field(IS_PARENT_CHILD_DEVICE) then
    device:set_find_child(switch_utils.find_child)
  end
  subscribe(device)
end

local function info_changed(driver, device, event, args)
  -- resubscribe and initialize relevant camera capabilities if a modular update has occurred
  if not compare_components(device.profile.components, args.old_st_store.profile.components) then
    initialize_camera_capabilities(device)
    subscribe(device)
  end
end

local function do_configure(driver, device) end

-- Attribute Handlers

local enabled_state_attr_factory = function(attribute)
  return function(driver, device, ib, response)
    local component = device.profile.components[component_map.main]
    device:emit_component_event(component, attribute(ib.data.value and "enabled" or "disabled"))
    if attribute == capabilities.imageControl.imageFlipHorizontal then
      update_supported_attributes(device, component, capabilities.imageControl, "imageFlipHorizontal")
    elseif attribute == capabilities.imageControl.imageFlipVertical then
      update_supported_attributes(device, component, capabilities.imageControl, "imageFlipVertical")
    elseif attribute == capabilities.cameraPrivacyMode.hardPrivacyMode then
      update_supported_attributes(device, component, capabilities.cameraPrivacyMode, "hardPrivacyMode")
    end
  end
end

local night_vision_attr_factory = function(attribute)
  return function(driver, device, ib, response)
    if tri_state_map[ib.data.value] then
      local component = device.profile.components[component_map.main]
      device:emit_component_event(component, attribute(tri_state_map[ib.data.value]))
      if attribute == capabilities.nightVision.illumination then
        local _ = device:get_latest_state(component_map.main, capabilities.nightVision.ID, capabilities.nightVision.supportedAttributes.NAME) or
          device:emit_component_event(component, capabilities.nightVision.supportedAttributes({"illumination"}))
      end
    end
  end
end

local function image_rotation_attr_handler(driver, device, ib, response)
  local degrees = utils.clamp_value(ib.data.value, 0, 359)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.imageControl.imageRotation(degrees))
  update_supported_attributes(device, component, capabilities.imageControl, "imageRotation")
end

local function two_way_talk_support_attr_handler(driver, device, ib, response)
  local two_way_talk_supported = ib.data.value == clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.HALF_DUPLEX or
    ib.data.value == clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.FULL_DUPLEX
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.webrtc.talkback(two_way_talk_supported))
  if two_way_talk_supported then
    device:emit_component_event(component, capabilities.webrtc.talkbackDuplex(
      ib.data.value == clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.HALF_DUPLEX and "halfDuplex" or "fullDuplex"
    ))
  end
end

local muted_attr_factory = function(component)
  return function(driver, device, ib, response)
    local comp = device.profile.components[component]
    device:emit_component_event(comp, capabilities.audioMute.mute(ib.data.value and "muted" or "unmuted"))
  end
end

local volume_level_attr_factory = function(component)
  return function(driver, device, ib, response)
    local max_volume = device:get_field(MAX_VOLUME_LEVEL .. "_" .. component) or ABS_VOL_MAX
    local min_volume = device:get_field(MIN_VOLUME_LEVEL .. "_" .. component) or ABS_VOL_MIN
    -- Convert from [min_volume, max_volume] to [0, 100] before emitting capability
    local limited_range = max_volume - min_volume
    local normalized_volume = utils.round((ib.data.value - min_volume) * 100.0 / limited_range)
    local comp = device.profile.components[component]
    device:emit_component_event(comp, capabilities.audioVolume.volume(normalized_volume))
  end
end

local max_level_attr_factory= function(component)
  return function(driver, device, ib, response)
    local max_volume = ib.data.value
    local min_volume = device:get_field(MIN_VOLUME_LEVEL .. "_" .. component)
    if max_volume > ABS_VOL_MAX or (min_volume and max_volume <= min_volume) then
      device.log.warn(string.format("Device reported invalid maximum (%d) %s volume level range value", ib.data.value, component))
      max_volume = ABS_VOL_MAX
    end
    device:set_field(MAX_VOLUME_LEVEL .. "_" .. component, max_volume)
  end
end

local min_level_attr_factory = function(component)
  return function(driver, device, ib, response)
    local min_volume = ib.data.value
    local max_volume = device:get_field(MAX_VOLUME_LEVEL .. "_" .. component)
    if min_volume < ABS_VOL_MIN or (max_volume and min_volume >= max_volume) then
      device.log.warn(string.format("Device reported invalid minimum (%d) %s volume level range value", ib.data.value, component))
      min_volume = ABS_VOL_MIN
    end
    device:set_field(MIN_VOLUME_LEVEL .. "_" .. component, min_volume)
  end
end

local function status_light_enabled_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.statusLed]
  device:emit_component_event(component, ib.data.value and capabilities.switch.switch.on() or capabilities.switch.switch.off())
end

local function status_light_brightness_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.statusLed]
  local _ = device:get_latest_state(component_map.statusLed, capabilities.mode.ID, capabilities.mode.supportedModes.NAME) or
    device:emit_component_event(component, capabilities.mode.supportedModes({"low", "medium", "high", "auto"}, {visibility = {displayed = false}}))
  local _ = device:get_latest_state(component_map.statusLed, capabilities.mode.ID, capabilities.mode.supportedArguments.NAME) or
    device:emit_component_event(component, capabilities.mode.supportedArguments({"low", "medium", "high", "auto"}, {visibility = {displayed = false}}))
  local mode = "auto"
  if ib.data.value == clusters.Global.types.ThreeLevelAutoEnum.LOW then
    mode = "low"
  elseif ib.data.value == clusters.Global.types.ThreeLevelAutoEnum.MEDIUM then
    mode = "medium"
  elseif ib.data.value == clusters.Global.types.ThreeLevelAutoEnum.HIGH then
    mode = "high"
  end
  device:emit_component_event(component, capabilities.mode.mode(mode))
end

local function rate_distortion_trade_off_points_attr_handler(driver, device, ib, response)
  local resolutions = {}
  local max_encoded_pixel_rate = device:get_field(MAX_ENCODED_PIXEL_RATE)
  local max_fps = device:get_field(MAX_FRAMES_PER_SECOND)
  local emit_capability = max_encoded_pixel_rate ~= nil and max_fps ~= nil
  for _, v in ipairs(ib.data.elements) do
    local rate_distortion_trade_off_points = v.elements
    local width = rate_distortion_trade_off_points.resolution.elements.width.value
    local height = rate_distortion_trade_off_points.resolution.elements.height.value
    table.insert(resolutions, {
      width = width,
      height = height
    })
    if emit_capability then
      local fps = compute_fps(max_encoded_pixel_rate, width, height, max_fps)
      if fps > 0 then
        resolutions[#resolutions].fps = fps
      end
    end
  end
  if emit_capability then
    local component = device.profile.components[component_map.main]
    device:emit_component_event(component, capabilities.videoStreamSettings.supportedResolutions(resolutions))
  end
  device:set_field(SUPPORTED_RESOLUTIONS, resolutions)
end

local function max_encoded_pixel_rate_attr_handler(driver, device, ib, response)
  local resolutions = device:get_field(SUPPORTED_RESOLUTIONS)
  local max_fps = device:get_field(MAX_FRAMES_PER_SECOND)
  local emit_capability = resolutions ~= nil and max_fps ~= nil
  if emit_capability then
    for _, v in pairs(resolutions) do
      local fps = compute_fps(ib.data.value, v.width, v.height, max_fps)
      if fps > 0 then
        v.fps = fps
      end
    end
    local component = device.profile.components[component_map.main]
    device:emit_component_event(component, capabilities.videoStreamSettings.supportedResolutions(resolutions))
  end
  device:set_field(MAX_ENCODED_PIXEL_RATE, ib.data.value)
end

local function video_sensor_parameters_attr_handler(driver, device, ib, response)
  local resolutions = device:get_field(SUPPORTED_RESOLUTIONS)
  local max_encoded_pixel_rate = device:get_field(MAX_ENCODED_PIXEL_RATE)
  local emit_capability = resolutions ~= nil and max_encoded_pixel_rate ~= nil
  local sensor_width, sensor_height, max_fps
  for _, v in pairs(ib.data.elements) do
    if v.field_id == 0 then
      sensor_width = v.value
    elseif v.field_id == 1 then
      sensor_height = v.value
    elseif v.field_id == 2 then
      max_fps = v.value
    end
  end

  if max_fps then
    local component = device.profile.components[component_map.main]
    if sensor_width and sensor_height then
      device:emit_component_event(component, capabilities.cameraViewportSettings.videoSensorParameters({
        width = sensor_width,
        height = sensor_height,
        maxFPS = max_fps
      }))
    end
    if emit_capability then
      for _, v in pairs(resolutions) do
        local fps = compute_fps(max_encoded_pixel_rate, v.width, v.height, max_fps)
        if fps > 0 then
          v.fps = fps
        end
      end
      device:emit_component_event(component, capabilities.videoStreamSettings.supportedResolutions(resolutions))
    end
    device:set_field(MAX_FRAMES_PER_SECOND, max_fps)
  end
end

local function min_viewport_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.cameraViewportSettings.minViewportResolution({
    width = ib.data.elements.width.value,
    height = ib.data.elements.height.value
  }))
end

local function allocated_video_streams_attr_handler(driver, device, ib, response)
  local streams = {}
  for i, v in ipairs(ib.data.elements) do
    local stream = v.elements
    local video_stream = {
      streamId = stream.video_stream_id.value,
      data = {
        label = "Stream " .. i,
        type = stream.stream_usage.value == clusters.Global.types.StreamUsageEnum.LIVE_VIEW and "liveStream" or "clipRecording",
        resolution = {
          width = stream.min_resolution.elements.width.value,
          height = stream.min_resolution.elements.height.value,
          fps = stream.min_frame_rate.value
        }
      }
    }
    local viewport = device:get_field(VIEWPORT)
    if viewport then
      video_stream.data.viewport = viewport
    end
    if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.WATERMARK) then
      video_stream.data.watermark = stream.watermark_enabled.value and "enabled" or "disabled"
    end
    if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.ON_SCREEN_DISPLAY) then
      video_stream.data.watermark = stream.osd_enabled.value and "enabled" or "disabled"
    end
    table.insert(streams, video_stream)
  end
  if #streams > 0 then
    local component = device.profile.components[component_map.main]
    device:emit_component_event(component, capabilities.videoStreamSettings.videoStreams(streams))
  end
end

local function viewport_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.cameraViewportSettings.defaultViewport({
    upperLeftVertex = { x = ib.data.elements.x1.value, y = ib.data.elements.y2.value },
    lowerRightVertex = { x = ib.data.elements.x2.value, y = ib.data.elements.y1.value },
  }))
end

local function ptz_position_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  local ptz_map = get_ptz_map(device)
  local emit_event = function(idx, value)
    if value ~= ptz_map[idx].current then
      device:emit_component_event(component, ptz_map[idx].attribute(
        utils.clamp_value(value, ptz_map[idx].range.minimum, ptz_map[idx].range.maximum)
      ))
    end
  end
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPAN) then
    emit_event(PAN_IDX, ib.data.elements.pan.value)
  end
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MTILT) then
    emit_event(TILT_IDX, ib.data.elements.tilt.value)
  end
  if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MZOOM) then
    emit_event(ZOOM_IDX, ib.data.elements.zoom.value)
  end
end

local function ptz_presets_attr_handler(driver, device, ib, response)
  local presets = {}
  for _, v in ipairs(ib.data.elements) do
    local preset = v.elements
    local pan, tilt, zoom = 0, 0, 1
    if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPAN) then
      pan = preset.settings.elements.pan.value
    end
    if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MTILT) then
      tilt = preset.settings.elements.tilt.value
    end
    if feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MZOOM) then
      zoom = preset.settings.elements.zoom.value
    end
    table.insert(presets, { id = preset.preset_id.value, label = preset.name.value, pan = pan, tilt = tilt, zoom = zoom })
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.mechanicalPanTiltZoom.presets(presets))
end

local function max_presets_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.mechanicalPanTiltZoom.maxPresets(ib.data.value))
end

local function zoom_max_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  if ib.data.value <= ABS_ZOOM_MAX then
    device:emit_component_event(component, capabilities.mechanicalPanTiltZoom.zoomRange({ value = { minimum = 1, maximum = ib.data.value } }))
  else
    device.log.warn(string.format("Device reported invalid maximum zoom (%d)", ib.data.value))
  end
end

local pt_range_attr_handler_factory = function(attribute, limit_field)
  return function(driver, device, ib, response)
    device:set_field(limit_field, ib.data.value)
    local field = string.find(limit_field, "PAN") and "PAN" or "TILT"
    local min = device:get_field(pt_range_fields[field].min)
    local max = device:get_field(pt_range_fields[field].max)
    if min ~= nil and max ~= nil then
      local abs_min = field == "PAN" and ABS_PAN_MIN or ABS_TILT_MIN
      local abs_max = field == "PAN" and ABS_PAN_MAX or ABS_TILT_MAX
      if min < max and min >= abs_min and max <= abs_max then
        local component = device.profile.components[component_map.main]
        device:emit_component_event(component, attribute({ value = { minimum = min, maximum = max } }))
        device:set_field(pt_range_fields[field].min, nil)
        device:set_field(pt_range_fields[field].max, nil)
      else
        device.log.warn(string.format("Device reported invalid minimum (%d) and maximum (%d) %s " ..
          "range values (should be between %d and %d)", min, max, string.lower(field), abs_min, abs_max))
      end
    end
  end
end

local function max_zones_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.zoneManagement.maxZones(ib.data.value))
end

local function zones_attr_handler(driver, device, ib, response)
  local zones = {}
  for _, v in ipairs(ib.data.elements) do
    local zone = v.elements
    local zone_id = zone.zone_id.value
    local zone_type = zone.zone_type.value
    local zone_source = zone.zone_source.value
    local zone_vertices = {}
    if feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.TWO_DIMENSIONAL_CARTESIAN_ZONE) and
      zone_type == clusters.ZoneManagement.types.ZoneTypeEnum.TWODCART_ZONE then
      local zone_name = zone.two_d_cartesian_zone.elements.name.value
      local zone_use = zone.two_d_cartesian_zone.elements.use.value
      for _, vertex in pairs(zone.two_d_cartesian_zone.elements.vertices.elements) do
        table.insert(zone_vertices, {vertex = {x = vertex.elements.x.value, y = vertex.elements.y.value}})
      end
      local zone_uses = {
        [clusters.ZoneManagement.types.ZoneUseEnum.MOTION] = "motion",
        [clusters.ZoneManagement.types.ZoneUseEnum.FOCUS] = "focus",
        [clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY] = "privacy"
      }
      local zone_color = zone.two_d_cartesian_zone.elements.color and zone.two_d_cartesian_zone.elements.color.value or nil
      table.insert(zones, {
        id = zone_id,
        name = zone_name,
        type = "2DCartesian",
        polygonVertices = zone_vertices,
        source = zone_source == clusters.ZoneManagement.types.ZoneSourceEnum.MFG and "manufacturer" or "user",
        use = zone_uses[zone_use],
        color = zone_color
      })
    else
      device.log.warn(string.format("Zone type not currently supported: (%s)", zone_type))
    end
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.zoneManagement.zones({value = zones}))
end

local function triggers_attr_handler(driver, device, ib, response)
  local triggers = {}
  for _, v in ipairs(ib.data.elements) do
    local trigger = v.elements
    table.insert(triggers, {
      zoneId = trigger.zone_id.value,
      initialDuration = trigger.initial_duration.value,
      augmentationDuration = trigger.augmentation_duration.value,
      maxDuration = trigger.max_duration.value,
      blindDuration = trigger.blind_duration.value,
      sensitivity = feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) and trigger.sensitivity.value
    })
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.zoneManagement.triggers(triggers))
end

local function sensitivity_max_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.zoneManagement.sensitivityRange({minimum = 1, maximum = ib.data.value},
    {visibility = {displayed = false}}))
end

local function sensitivity_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.zoneManagement.sensitivity(ib.data.value, {visibility = {displayed = false}}))
end

local function installed_chime_sounds_attr_handler(driver, device, ib, response)
  local installed_chimes = {}
  for _, v in ipairs(ib.data.elements) do
    local chime = v.elements
    table.insert(installed_chimes, {id = chime.chime_id.value, label = chime.name.value})
  end
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.sounds.supportedSounds(installed_chimes, {visibility = {displayed = false}}))
end

local function selected_chime_attr_handler(driver, device, ib, response)
  local component = device.profile.components[component_map.main]
  device:emit_component_event(component, capabilities.sounds.selectedSound(ib.data.value))
end

local function camera_av_stream_management_attribute_list_handler(driver, device, ib, response)
  local status_light_enabled_present, status_light_brightness_present = false, false
  for _, attr in ipairs(ib.data.elements) do
    if attr.value == 0x27 then
      status_light_enabled_present = true
    elseif attr.value == 0x28 then
      status_light_brightness_present = true
    end
  end
  match_profile(device, status_light_enabled_present, status_light_brightness_present)
end

-- Event Handlers

local function zone_triggered_event_handler(driver, device, ib, response)
  local triggered_zones = device:get_field(TRIGGERED_ZONES) or {}
  if not switch_utils.tbl_contains(triggered_zones, ib.data.elements.zone.value) then
    table.insert(triggered_zones, {zoneId = ib.data.elements.zone.value})
    device:set_field(TRIGGERED_ZONES, triggered_zones)
    local component = device.profile.components[component_map.main]
    device:emit_component_event(component, capabilities.zoneManagement.triggeredZones(triggered_zones))
  end
end

local function zone_stopped_event_handler(driver, device, ib, response)
  local triggered_zones = device:get_field(TRIGGERED_ZONES)
  for i, v in pairs(triggered_zones) do
    if v.zoneId == ib.data.elements.zone.value then
      table.remove(triggered_zones, i)
      device:set_field(TRIGGERED_ZONES, triggered_zones)
      local component = device.profile.components[component_map.main]
      device:emit_component_event(component, capabilities.zoneManagement.triggeredZones(triggered_zones))
    end
  end
end

-- Capability Handlers

local set_enabled_factory = function(attribute)
  return function(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    device:send(attribute:write(device, endpoint_id, cmd.args.state == "enabled"))
  end
end

local set_night_vision_factory = function(attribute)
  return function(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    for i, v in pairs(tri_state_map) do
      if v == cmd.args.mode then
        device:send(attribute:write(device, endpoint_id, i))
        return
      end
    end
    device.log.warn(string.format("Capability command sent with unknown value: (%s)", cmd.args.mode))
  end
end

local function handle_set_image_rotation(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local degrees = utils.clamp_value(cmd.args.rotation, 0, 359)
  device:send(clusters.CameraAvStreamManagement.attributes.ImageRotation:write(device, endpoint_id, degrees))
end

local handle_mute_commands_factory = function(command)
  return function(driver, device, cmd)
    local attr = cmd.component == "speaker" and clusters.CameraAvStreamManagement.attributes.SpeakerMuted or
      clusters.CameraAvStreamManagement.attributes.MicrophoneMuted
    local endpoint_id = device:component_to_endpoint(cmd.component)
    local mute_state = false
    if command == capabilities.audioMute.commands.setMute.NAME then
      mute_state = cmd.args.state == "muted"
    elseif command == capabilities.audioMute.commands.mute.NAME then
      mute_state = true
    end
    device:send(attr:write(device, endpoint_id, mute_state))
  end
end

local function handle_set_volume(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local max_volume = device:get_field(MAX_VOLUME_LEVEL .. "_" .. cmd.component) or ABS_VOL_MAX
  local min_volume = device:get_field(MIN_VOLUME_LEVEL .. "_" .. cmd.component) or ABS_VOL_MIN
  -- Convert from [0, 100] to [min_volume, max_volume] before writing attribute
  local volume_range = max_volume - min_volume
  local volume = utils.round(cmd.args.volume * volume_range / 100.0 + min_volume)
  if cmd.component == "speaker" then
    device:send(clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(device, endpoint_id, volume))
  else
    device:send(clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(device, endpoint_id, volume))
  end
end

local function handle_volume_up(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local max_volume = device:get_field(MAX_VOLUME_LEVEL .. "_" .. cmd.component) or ABS_VOL_MAX
  local min_volume = device:get_field(MIN_VOLUME_LEVEL .. "_" .. cmd.component) or ABS_VOL_MIN
  local volume = device:get_latest_state(cmd.component, capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME)
  if not volume or volume >= max_volume then return end
  -- Convert from [0, 100] to [min_volume, max_volume] before writing attribute
  local volume_range = max_volume - min_volume
  local converted_volume = utils.round((volume + 1) * volume_range / 100.0 + min_volume)
  if cmd.component == "speaker" then
    device:send(clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(device, endpoint_id, converted_volume))
  else
    device:send(clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(device, endpoint_id, converted_volume))
  end
end

local function handle_volume_down(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local max_volume = device:get_field(MAX_VOLUME_LEVEL .. "_" .. cmd.component) or ABS_VOL_MAX
  local min_volume = device:get_field(MIN_VOLUME_LEVEL .. "_" .. cmd.component) or ABS_VOL_MIN
  local volume = device:get_latest_state(cmd.component, capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME)
  if not volume or volume <= min_volume then return end
  -- Convert from [0, 100] to [min_volume, max_volume] before writing attribute
  local volume_range = max_volume - min_volume
  local converted_volume = utils.round((volume - 1) * volume_range / 100.0 + min_volume)
  if cmd.component == "speaker" then
    device:send(clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(device, endpoint_id, converted_volume))
  else
    device:send(clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(device, endpoint_id, converted_volume))
  end
end

local function handle_set_mode(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level_auto_value
  if cmd.args.mode == "low" then level_auto_value = "LOW"
  elseif cmd.args.mode == "medium" then level_auto_value = "MEDIUM"
  elseif cmd.args.mode == "high" then level_auto_value = "HIGH"
  else level_auto_value = "AUTO" end
  device:send(clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:write(device, endpoint_id,
    clusters.Global.types.ThreeLevelAutoEnum[level_auto_value]))
end

local function handle_switch_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(device, endpoint_id, true))
end

local function handle_switch_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(device, endpoint_id, false))
end

local function handle_audio_recording(driver, device, cmd)
  -- TODO: Allocate audio stream if it doesn't exist
  local component = device.profile.components[cmd.component]
  device:emit_component_event(component, capabilities.audioRecording.audioRecording(cmd.args.state))
end

local ptz_relative_move_factory = function(index)
  return function (driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    local pan_delta = index == PAN_IDX and cmd.args.delta or 0
    local tilt_delta = index == TILT_IDX and cmd.args.delta or 0
    local zoom_delta = index == ZOOM_IDX and cmd.args.delta or 0
    device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(
      device, endpoint_id, pan_delta, tilt_delta, zoom_delta
    ))
  end
end

local ptz_set_position_factory = function(command)
  return function (driver, device, cmd)
    local ptz_map = get_ptz_map(device)
    if command == capabilities.mechanicalPanTiltZoom.commands.setPanTiltZoom then
      ptz_map[PAN_IDX].current = cmd.args.pan
      ptz_map[TILT_IDX].current = cmd.args.tilt
      ptz_map[ZOOM_IDX].current = cmd.args.zoom
    elseif command == capabilities.mechanicalPanTiltZoom.commands.setPan then
      ptz_map[PAN_IDX].current = cmd.args.pan
    elseif command == capabilities.mechanicalPanTiltZoom.commands.setTilt then
      ptz_map[TILT_IDX].current = cmd.args.tilt
    else
      ptz_map[ZOOM_IDX].current = cmd.args.zoom
    end
    for _, v in pairs(ptz_map) do
      v.current = utils.clamp_value(v.current, v.range.minimum, v.range.maximum)
    end
    local endpoint_id = device:component_to_endpoint(cmd.component)
    device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(device, endpoint_id,
      ptz_map[PAN_IDX].current, ptz_map[TILT_IDX].current, ptz_map[ZOOM_IDX].current
    ))
  end
end

local function handle_save_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSavePreset(
    device, endpoint_id, cmd.args.id, cmd.args.label
  ))
end

local function handle_remove_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRemovePreset(device, endpoint_id, cmd.args.id))
end

local function handle_move_to_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZMoveToPreset(device, endpoint_id, cmd.args.id))
end

local function handle_new_zone(driver, device, cmd)
  local zone_uses = {
    ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
    ["focus"] = feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.FOCUSZONES) and
      clusters.ZoneManagement.types.ZoneUseEnum.FOCUS or clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY,
    ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
  }
  local vertices = {}
  for _, v in pairs(cmd.args.polygonVertices) do
    table.insert(vertices, clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = v.value.x, y = v.value.y}))
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ZoneManagement.server.commands.CreateTwoDCartesianZone(
    device, endpoint_id, clusters.ZoneManagement.types.TwoDCartesianZoneStruct(
      {
        name = cmd.args.name,
        use = zone_uses[cmd.args.use],
        vertices = vertices,
        color = cmd.args.color
      }
    )
  ))
end

local function handle_update_zone(driver, device, cmd)
  local zone_uses = {
    ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
    ["focus"] = feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.FOCUSZONES) and
      clusters.ZoneManagement.types.ZoneUseEnum.FOCUS or clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY,
    ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
  }
  if not cmd.args.name or not cmd.args.polygonVertices or not cmd.args.use or not cmd.args.color then
    local zones = device:get_latest_state(
      component_map.main, capabilities.zoneManagement.ID, capabilities.zoneManagement.zones.NAME
    ) or {}
    local found_zone = false
    for _, v in pairs(zones) do
      if v.id == cmd.args.zoneId then
        if not cmd.args.name then cmd.args.name = v.name end
        if not cmd.args.polygonVertices then cmd.args.polygonVertices = v.polygonVertices end
        if not cmd.args.use then cmd.args.use = v.use end
        if not cmd.args.color then cmd.args.color = v.color end -- color may be nil, but it is optional in TwoDCartesianZoneStruct
        found_zone = true
        break
      end
    end
    if not found_zone then
      device.log.warn_with({hub_logs = true}, string.format("Zone does not exist, cannot update the zone."))
      return
    end
  end
  local vertices = {}
  for _, v in pairs(cmd.args.polygonVertices) do
    table.insert(vertices, clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = v.value.x, y = v.value.y}))
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ZoneManagement.server.commands.UpdateTwoDCartesianZone(
    device, endpoint_id, cmd.args.zoneId, clusters.ZoneManagement.types.TwoDCartesianZoneStruct(
      {
        name = cmd.args.name,
        use = zone_uses[cmd.args.use],
        vertices = vertices,
        color = cmd.args.color
      }
    )
  ))
end

local function handle_remove_zone(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ZoneManagement.server.commands.RemoveZone(device, endpoint_id, cmd.args.zoneId))
end

local function handle_create_or_update_trigger(driver, device, cmd)
  if not cmd.args.augmentationDuration or not cmd.args.maxDuration or not cmd.args.blindDuration or
    (feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) and
      not cmd.args.sensitivity) then
    local triggers = device:get_latest_state(
      component_map.main, capabilities.zoneManagement.ID, capabilities.zoneManagement.triggers.NAME
    ) or {}
    local found_trigger = false
    for _, v in pairs(triggers) do
      if v.zoneId == cmd.args.zoneId then
        if not cmd.args.augmentationDuration then cmd.args.augmentationDuration = v.augmentationDuration end
        if not cmd.args.maxDuration then cmd.args.maxDuration = v.maxDuration end
        if not cmd.args.blindDuration then cmd.args.blindDuration = v.blindDuration end
        if feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) and
          not cmd.args.sensitivity then
          cmd.args.sensitivity = v.sensitivity
        end
        found_trigger = true
        break
      end
    end
    if not found_trigger then
      device.log.warn_with({hub_logs = true}, string.format("Missing fields needed to create trigger."))
      return
    end
  end
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ZoneManagement.server.commands.CreateOrUpdateTrigger(
    device, endpoint_id, clusters.ZoneManagement.types.ZoneTriggerControlStruct(
      {
        zone_id = cmd.args.zoneId,
        initial_duration = cmd.args.initialDuration,
        augmentation_duration = cmd.args.augmentationDuration,
        max_duration = cmd.args.maxDuration,
        blind_duration = cmd.args.blindDuration,
        sensitivity = cmd.args.sensitivity
      }
    )
  ))
end

local function handle_remove_trigger(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ZoneManagement.server.commands.RemoveTrigger(device, endpoint_id, cmd.args.zoneId))
end

local function handle_set_sensitivity(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  if not feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) then
    device:send(clusters.ZoneManagement.attributes.Sensitivity:write(device, endpoint_id, cmd.args.id))
  else
    device.log.warn(string.format("Can't set global zone sensitivity setting, per zone sensitivity enabled."))
  end
end

local function handle_play_sound(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.Chime.server.commands.PlayChimeSound(device, endpoint_id))
end

local function handle_set_selected_sound(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.Chime.attributes.SelectedChime:write(device, endpoint_id, cmd.args.id))
end

local function handle_set_stream(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local watermark_enabled, on_screen_display_enabled
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.WATERMARK) then
    watermark_enabled = cmd.args.watermark == "enabled"
  end
  if feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.ON_SCREEN_DISPLAY) then
    on_screen_display_enabled = cmd.args.onScreenDisplay == "enabled"
  end
  device:send(clusters.CameraAvStreamManagement.server.commands.VideoStreamModify(device, endpoint_id,
    cmd.args.streamId, watermark_enabled, on_screen_display_enabled
  ))
end

local function handle_set_default_viewport(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvStreamManagement.attributes.Viewport:write(
    device, endpoint_id, clusters.Global.types.ViewportStruct(
      {
        x1 = cmd.args.upperLeftVertex.x,
        x2 = cmd.args.lowerRightVertex.x,
        y1 = cmd.args.lowerRightVertex.y,
        y2 = cmd.args.upperLeftVertex.y
      }
    )
  ))
end

local camera_handler = {
  NAME = "Camera Handler",
  lifecycle_handlers = {
    init = device_init,
    infoChanged = info_changed,
    doConfigure = do_configure,
    driverSwitched = do_configure
  },
  matter_handlers = {
    attr = {
      [clusters.CameraAvStreamManagement.ID] = {
        [clusters.CameraAvStreamManagement.attributes.HDRModeEnabled.ID] = enabled_state_attr_factory(capabilities.hdr.hdr),
        [clusters.CameraAvStreamManagement.attributes.NightVision.ID] = night_vision_attr_factory(capabilities.nightVision.nightVision),
        [clusters.CameraAvStreamManagement.attributes.NightVisionIllum.ID] = night_vision_attr_factory(capabilities.nightVision.illumination),
        [clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal.ID] = enabled_state_attr_factory(capabilities.imageControl.imageFlipHorizontal),
        [clusters.CameraAvStreamManagement.attributes.ImageFlipVertical.ID] = enabled_state_attr_factory(capabilities.imageControl.imageFlipVertical),
        [clusters.CameraAvStreamManagement.attributes.ImageRotation.ID] = image_rotation_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled.ID] = enabled_state_attr_factory(capabilities.cameraPrivacyMode.softRecordingPrivacyMode),
        [clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled.ID] = enabled_state_attr_factory(capabilities.cameraPrivacyMode.softLivestreamPrivacyMode),
        [clusters.CameraAvStreamManagement.attributes.HardPrivacyModeOn.ID] = enabled_state_attr_factory(capabilities.cameraPrivacyMode.hardPrivacyMode),
        [clusters.CameraAvStreamManagement.attributes.TwoWayTalkSupport.ID] = two_way_talk_support_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.SpeakerMuted.ID] = muted_attr_factory(component_map.speaker),
        [clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel.ID] = volume_level_attr_factory(component_map.speaker),
        [clusters.CameraAvStreamManagement.attributes.SpeakerMaxLevel.ID] = max_level_attr_factory(component_map.speaker),
        [clusters.CameraAvStreamManagement.attributes.SpeakerMinLevel.ID] = min_level_attr_factory(component_map.speaker),
        [clusters.CameraAvStreamManagement.attributes.MicrophoneMuted.ID] = muted_attr_factory(component_map.microphone),
        [clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel.ID] = volume_level_attr_factory(component_map.microphone),
        [clusters.CameraAvStreamManagement.attributes.MicrophoneMaxLevel.ID] = max_level_attr_factory(component_map.microphone),
        [clusters.CameraAvStreamManagement.attributes.MicrophoneMinLevel.ID] = min_level_attr_factory(component_map.microphone),
        [clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID] = status_light_enabled_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID] = status_light_brightness_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.RateDistortionTradeOffPoints.ID] = rate_distortion_trade_off_points_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.MaxEncodedPixelRate.ID] = max_encoded_pixel_rate_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.VideoSensorParams.ID] = video_sensor_parameters_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.MinViewportResolution.ID] = min_viewport_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams.ID] = allocated_video_streams_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.Viewport.ID] = viewport_attr_handler,
        [clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled.ID] = enabled_state_attr_factory(capabilities.localMediaStorage.localSnapshotRecording),
        [clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled.ID] = enabled_state_attr_factory(capabilities.localMediaStorage.localVideoRecording),
        [clusters.CameraAvStreamManagement.attributes.AttributeList.ID] = camera_av_stream_management_attribute_list_handler
      },
      [clusters.CameraAvSettingsUserLevelManagement.ID] = {
        [clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition.ID] = ptz_position_attr_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPresets.ID] = ptz_presets_attr_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.MaxPresets.ID] = max_presets_attr_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.ZoomMax.ID] = zoom_max_attr_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.PanMax.ID] = pt_range_attr_handler_factory(capabilities.mechanicalPanTiltZoom.panRange, pt_range_fields[PAN_IDX].max),
        [clusters.CameraAvSettingsUserLevelManagement.attributes.PanMin.ID] = pt_range_attr_handler_factory(capabilities.mechanicalPanTiltZoom.panRange, pt_range_fields[PAN_IDX].min),
        [clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMax.ID] = pt_range_attr_handler_factory(capabilities.mechanicalPanTiltZoom.tiltRange, pt_range_fields[TILT_IDX].max),
        [clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMin.ID] = pt_range_attr_handler_factory(capabilities.mechanicalPanTiltZoom.tiltRange, pt_range_fields[TILT_IDX].min)
      },
      [clusters.ZoneManagement.ID] = {
        [clusters.ZoneManagement.attributes.MaxZones.ID] = max_zones_attr_handler,
        [clusters.ZoneManagement.attributes.Zones.ID] = zones_attr_handler,
        [clusters.ZoneManagement.attributes.Triggers.ID] = triggers_attr_handler,
        [clusters.ZoneManagement.attributes.SensitivityMax.ID] = sensitivity_max_attr_handler,
        [clusters.ZoneManagement.attributes.Sensitivity.ID] = sensitivity_attr_handler,
      },
      [clusters.Chime.ID] = {
        [clusters.Chime.attributes.InstalledChimeSounds.ID] = installed_chime_sounds_attr_handler,
        [clusters.Chime.attributes.SelectedChime.ID] = selected_chime_attr_handler
      }
    },
    event = {
      [clusters.ZoneManagement.ID] = {
        [clusters.ZoneManagement.events.ZoneTriggered.ID] = zone_triggered_event_handler,
        [clusters.ZoneManagement.events.ZoneStopped.ID] = zone_stopped_event_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.hdr.ID] = {
      [capabilities.hdr.commands.setHdr.NAME] = set_enabled_factory(clusters.CameraAvStreamManagement.attributes.HDRModeEnabled)
    },
    [capabilities.nightVision.ID] = {
      [capabilities.nightVision.commands.setNightVision.NAME] = set_night_vision_factory(clusters.CameraAvStreamManagement.attributes.NightVision),
      [capabilities.nightVision.commands.setIllumination.NAME] = set_night_vision_factory(clusters.CameraAvStreamManagement.attributes.NightVisionIllum)
    },
    [capabilities.imageControl.ID] = {
      [capabilities.imageControl.commands.setImageFlipHorizontal.NAME] = set_enabled_factory(clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal),
      [capabilities.imageControl.commands.setImageFlipVertical.NAME] = set_enabled_factory(clusters.CameraAvStreamManagement.attributes.ImageFlipVertical),
      [capabilities.imageControl.commands.setImageRotation.NAME] = handle_set_image_rotation
    },
    [capabilities.cameraPrivacyMode.ID] = {
      [capabilities.cameraPrivacyMode.commands.setSoftLivestreamPrivacyMode.NAME] = set_enabled_factory(clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled),
      [capabilities.cameraPrivacyMode.commands.setSoftRecordingPrivacyMode.NAME] = set_enabled_factory(clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled)
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.setMute.NAME] = handle_mute_commands_factory(capabilities.audioMute.commands.setMute.NAME),
      [capabilities.audioMute.commands.mute.NAME] = handle_mute_commands_factory(capabilities.audioMute.commands.mute.NAME),
      [capabilities.audioMute.commands.unmute.NAME] = handle_mute_commands_factory(capabilities.audioMute.commands.unmute.NAME)
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.setVolume.NAME] = handle_set_volume,
      [capabilities.audioVolume.commands.volumeUp.NAME] = handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = handle_volume_down
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = handle_set_mode
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off
    },
    [capabilities.audioRecording.ID] = {
      [capabilities.audioRecording.commands.setAudioRecording.NAME] = handle_audio_recording
    },
    [capabilities.mechanicalPanTiltZoom.ID] = {
      [capabilities.mechanicalPanTiltZoom.commands.panRelative.NAME] = ptz_relative_move_factory(PAN_IDX),
      [capabilities.mechanicalPanTiltZoom.commands.tiltRelative.NAME] = ptz_relative_move_factory(TILT_IDX),
      [capabilities.mechanicalPanTiltZoom.commands.zoomRelative.NAME] = ptz_relative_move_factory(ZOOM_IDX),
      [capabilities.mechanicalPanTiltZoom.commands.setPan.NAME] = ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setPan),
      [capabilities.mechanicalPanTiltZoom.commands.setTilt.NAME] = ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setTilt),
      [capabilities.mechanicalPanTiltZoom.commands.setZoom.NAME] = ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setZoom),
      [capabilities.mechanicalPanTiltZoom.commands.setPanTiltZoom.NAME] = ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setPanTiltZoom),
      [capabilities.mechanicalPanTiltZoom.commands.savePreset.NAME] = handle_save_preset,
      [capabilities.mechanicalPanTiltZoom.commands.removePreset.NAME] = handle_remove_preset,
      [capabilities.mechanicalPanTiltZoom.commands.moveToPreset.NAME] = handle_move_to_preset
    },
    [capabilities.zoneManagement.ID] = {
      [capabilities.zoneManagement.commands.newZone.NAME] = handle_new_zone,
      [capabilities.zoneManagement.commands.updateZone.NAME] = handle_update_zone,
      [capabilities.zoneManagement.commands.removeZone.NAME] = handle_remove_zone,
      [capabilities.zoneManagement.commands.createOrUpdateTrigger.NAME] = handle_create_or_update_trigger,
      [capabilities.zoneManagement.commands.removeTrigger.NAME] = handle_remove_trigger,
      [capabilities.zoneManagement.commands.setSensitivity.NAME] = handle_set_sensitivity
    },
    [capabilities.sounds.ID] = {
      [capabilities.sounds.commands.playSound.NAME] = handle_play_sound,
      [capabilities.sounds.commands.setSelectedSound.NAME] = handle_set_selected_sound
    },
    [capabilities.videoStreamSettings.ID] = {
      [capabilities.videoStreamSettings.commands.setStream.NAME] = handle_set_stream
    },
    [capabilities.cameraViewportSettings.ID] = {
      [capabilities.cameraViewportSettings.commands.setDefaultViewport.NAME] = handle_set_default_viewport
    },
    [capabilities.localMediaStorage.ID] = {
      [capabilities.localMediaStorage.commands.setLocalSnapshotRecording.NAME] = set_enabled_factory(clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled),
      [capabilities.localMediaStorage.commands.setLocalVideoRecording.NAME] = set_enabled_factory(clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled)
    }
  },
  can_handle = is_camera
}

return camera_handler
