-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"

local SubscriptionMap = {
  subscribed_attributes = {
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
    [capabilities.cameraPrivacyMode.ID] = {
      clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled,
      clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled,
      clusters.CameraAvStreamManagement.attributes.HardPrivacyModeOn
    },
    [capabilities.cameraViewportSettings.ID] = {
      clusters.CameraAvStreamManagement.attributes.MinViewportResolution,
      clusters.CameraAvStreamManagement.attributes.VideoSensorParams,
      clusters.CameraAvStreamManagement.attributes.Viewport
    },
    [capabilities.hdr.ID] = {
      clusters.CameraAvStreamManagement.attributes.HDRModeEnabled,
      clusters.CameraAvStreamManagement.attributes.ImageRotation
    },
    [capabilities.imageControl.ID] = {
      clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal,
      clusters.CameraAvStreamManagement.attributes.ImageFlipVertical
    },
    [capabilities.localMediaStorage.ID] = {
      clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled,
      clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled
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
    [capabilities.mode.ID] = {
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness
    },
    [capabilities.nightVision.ID] = {
      clusters.CameraAvStreamManagement.attributes.NightVision,
      clusters.CameraAvStreamManagement.attributes.NightVisionIllum
    },
    [capabilities.sounds.ID] = {
      clusters.Chime.attributes.InstalledChimeSounds,
      clusters.Chime.attributes.SelectedChime
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
    [capabilities.webrtc.ID] = {
      clusters.CameraAvStreamManagement.attributes.TwoWayTalkSupport
    },
    [capabilities.zoneManagement.ID] = {
      clusters.ZoneManagement.attributes.MaxZones,
      clusters.ZoneManagement.attributes.Zones,
      clusters.ZoneManagement.attributes.Triggers,
      clusters.ZoneManagement.attributes.SensitivityMax,
      clusters.ZoneManagement.attributes.Sensitivity
    },
  },
  subscribed_events = {
    [capabilities.zoneManagement.ID] = {
      clusters.ZoneManagement.events.ZoneTriggered,
      clusters.ZoneManagement.events.ZoneStopped
    }
  },
  conditional_subscriptions = {
    [function(device)
      local fields = require "switch_utils.fields"
      local switch_utils = require "switch_utils.utils"
      return #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.CAMERA) > 0
    end] = { clusters.CameraAvStreamManagement.attributes.AttributeList }
  }
}

return SubscriptionMap
