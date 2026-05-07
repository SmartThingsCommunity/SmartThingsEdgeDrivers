-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"

local CameraFields = {}

CameraFields.MAX_ENCODED_PIXEL_RATE = "__max_encoded_pixel_rate"
CameraFields.MAX_FRAMES_PER_SECOND = "__max_frames_per_second"
CameraFields.MAX_VOLUME_LEVEL = "__max_volume_level"
CameraFields.MIN_VOLUME_LEVEL = "__min_volume_level"
CameraFields.SUPPORTED_RESOLUTIONS = "__supported_resolutions"
CameraFields.MAX_RESOLUTION = "__max_resolution"
CameraFields.MIN_RESOLUTION = "__min_resolution"
CameraFields.TRIGGERED_ZONES = "__triggered_zones"
CameraFields.DPTZ_VIEWPORTS = "__dptz_viewports"
CameraFields.STATUS_LIGHT_ENABLED_PRESENT = "__status_light_enabled_present"
CameraFields.STATUS_LIGHT_BRIGHTNESS_PRESENT = "__status_light_brightness_present"

CameraFields.CameraAVSMFeatureMapAttr = { ID = 0xFFFC, cluster = clusters.CameraAvStreamManagement.ID }
CameraFields.CameraAVSULMFeatureMapAttr = { ID = 0xFFFC, cluster = clusters.CameraAvSettingsUserLevelManagement.ID }
CameraFields.ZoneManagementFeatureMapAttr = { ID = 0xFFFC, cluster = clusters.ZoneManagement.ID }

CameraFields.PAN_IDX = "PAN"
CameraFields.TILT_IDX = "TILT"
CameraFields.ZOOM_IDX = "ZOOM"

CameraFields.pt_range_fields = {
  [CameraFields.PAN_IDX] = { max = "__MAX_PAN" , min = "__MIN_PAN" },
  [CameraFields.TILT_IDX] = { max = "__MAX_TILT" , min = "__MIN_TILT" }
}

CameraFields.profile_components = {
  main = "main",
  statusLed = "statusLed",
  speaker = "speaker",
  microphone = "microphone",
  doorbell = "doorbell"
}

CameraFields.tri_state_map = {
  [clusters.CameraAvStreamManagement.types.TriStateAutoEnum.OFF] = "off",
  [clusters.CameraAvStreamManagement.types.TriStateAutoEnum.ON] = "on",
  [clusters.CameraAvStreamManagement.types.TriStateAutoEnum.AUTO] = "auto"
}

CameraFields.ABS_PAN_MAX = 180
CameraFields.ABS_PAN_MIN = -180
CameraFields.ABS_TILT_MAX = 180
CameraFields.ABS_TILT_MIN = -180
CameraFields.ABS_ZOOM_MAX = 100
CameraFields.ABS_ZOOM_MIN = 1
CameraFields.ABS_VOL_MAX = 254.0
CameraFields.ABS_VOL_MIN = 0.0

-- Define defaults for allocating new streams. Note that these are the same values use by the hub.
CameraFields.video_stream_defaults = {
  codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
  min_frame_rate = 30,
  max_frame_rate = 60,
  min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 320, height = 240}),
  max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
  min_bitrate = 10000,
  max_bitrate = 2000000,
  key_frame_interval = 4000,
  watermark_enabled = false,
  on_screen_display_enabled = false
}

return CameraFields
