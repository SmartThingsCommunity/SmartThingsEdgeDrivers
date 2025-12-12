-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"

local CameraFields = {}

CameraFields.MAX_ENCODED_PIXEL_RATE = "__max_encoded_pixel_rate"
CameraFields.MAX_FRAMES_PER_SECOND = "__max_frames_per_second"
CameraFields.MAX_VOLUME_LEVEL = "__max_volume_level"
CameraFields.MIN_VOLUME_LEVEL = "__min_volume_level"
CameraFields.SUPPORTED_RESOLUTIONS = "__supported_resolutions"
CameraFields.TRIGGERED_ZONES = "__triggered_zones"
CameraFields.VIEWPORT = "__viewport"

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

return CameraFields
