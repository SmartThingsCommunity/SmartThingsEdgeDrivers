-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cluster_base = require "st.matter.cluster_base"
local clusters = require "st.matter.clusters"
local camera_fields = require "sub_drivers.camera.camera_utils.fields"
local switch_fields = require "switch_utils.fields"
local t_utils = require "integration_test.utils"
local test = require "integration_test"
local uint32 = require "st.matter.data_types.Uint32"

test.disable_startup_messages()

local CAMERA_EP = 1

local endpoints = {
  {
    endpoint_id = 0,
    clusters = {
      { cluster_id = clusters.Basic.ID, cluster_type = "SERVER" }
    },
    device_types = {
      { device_type_id = 0x0016, device_type_revision = 1 } -- RootNode
    }
  },
  {
    endpoint_id = CAMERA_EP,
    clusters = {
      {
        cluster_id = clusters.CameraAvStreamManagement.ID,
        feature_map = clusters.CameraAvStreamManagement.types.Feature.VIDEO |
          clusters.CameraAvStreamManagement.types.Feature.PRIVACY |
          clusters.CameraAvStreamManagement.types.Feature.AUDIO |
          clusters.CameraAvStreamManagement.types.Feature.LOCAL_STORAGE |
          clusters.CameraAvStreamManagement.types.Feature.SPEAKER |
          clusters.CameraAvStreamManagement.types.Feature.IMAGE_CONTROL |
          clusters.CameraAvStreamManagement.types.Feature.SPEAKER |
          clusters.CameraAvStreamManagement.types.Feature.HIGH_DYNAMIC_RANGE |
          clusters.CameraAvStreamManagement.types.Feature.NIGHT_VISION |
          clusters.CameraAvStreamManagement.types.Feature.WATERMARK |
          clusters.CameraAvStreamManagement.types.Feature.ON_SCREEN_DISPLAY,
        cluster_type = "SERVER"
      },
      {
        cluster_id = clusters.CameraAvSettingsUserLevelManagement.ID,
        feature_map = clusters.CameraAvSettingsUserLevelManagement.types.Feature.DIGITALPTZ |
          clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_PAN |
          clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_TILT |
          clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_ZOOM |
          clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_PRESETS,
        cluster_type = "SERVER"
      },
      {
        cluster_id = clusters.PushAvStreamTransport.ID,
        cluster_type = "SERVER"
      },
      {
        cluster_id = clusters.ZoneManagement.ID,
        feature_map = clusters.ZoneManagement.types.Feature.TWO_DIMENSIONAL_CARTESIAN_ZONE |
          clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY,
        cluster_type = "SERVER"
      },
      {
        cluster_id = clusters.WebRTCTransportProvider.ID,
        cluster_type = "SERVER"
      },
      {
        cluster_id = clusters.OccupancySensing.ID,
        cluster_type = "SERVER"
      }
    },
    device_types = {
      {device_type_id = switch_fields.DEVICE_TYPE_ID.CAMERA, device_type_revision = 1}
    }
  }
}

local additional_subscriptions = {
  clusters.CameraAvStreamManagement.attributes.HDRModeEnabled,
  clusters.CameraAvStreamManagement.attributes.ImageRotation,
  clusters.CameraAvStreamManagement.attributes.NightVision,
  clusters.CameraAvStreamManagement.attributes.NightVisionIllum,
  clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal,
  clusters.CameraAvStreamManagement.attributes.ImageFlipVertical,
  clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled,
  clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled,
  clusters.CameraAvStreamManagement.attributes.HardPrivacyModeOn,
  clusters.CameraAvStreamManagement.attributes.TwoWayTalkSupport,
  clusters.CameraAvStreamManagement.attributes.SpeakerMuted,
  clusters.CameraAvStreamManagement.attributes.MicrophoneMuted,
  clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel,
  clusters.CameraAvStreamManagement.attributes.SpeakerMaxLevel,
  clusters.CameraAvStreamManagement.attributes.SpeakerMinLevel,
  clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel,
  clusters.CameraAvStreamManagement.attributes.MicrophoneMaxLevel,
  clusters.CameraAvStreamManagement.attributes.MicrophoneMinLevel,
  clusters.CameraAvStreamManagement.attributes.RateDistortionTradeOffPoints,
  clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled,
  clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled,
  clusters.CameraAvStreamManagement.attributes.MaxEncodedPixelRate,
  clusters.CameraAvStreamManagement.attributes.VideoSensorParams,
  clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams,
  clusters.CameraAvStreamManagement.attributes.Viewport,
  clusters.CameraAvStreamManagement.attributes.MinViewportResolution,
  clusters.CameraAvStreamManagement.attributes.AttributeList,
  clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition,
  clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPresets,
  clusters.CameraAvSettingsUserLevelManagement.attributes.MaxPresets,
  clusters.CameraAvSettingsUserLevelManagement.attributes.ZoomMax,
  clusters.CameraAvSettingsUserLevelManagement.attributes.PanMax,
  clusters.CameraAvSettingsUserLevelManagement.attributes.PanMin,
  clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMax,
  clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMin,
  clusters.CameraAvSettingsUserLevelManagement.attributes.DPTZStreams,
  clusters.ZoneManagement.attributes.MaxZones,
  clusters.ZoneManagement.attributes.Zones,
  clusters.ZoneManagement.attributes.Triggers,
  clusters.ZoneManagement.attributes.SensitivityMax,
  clusters.ZoneManagement.attributes.Sensitivity,
  clusters.ZoneManagement.events.ZoneTriggered,
  clusters.ZoneManagement.events.ZoneStopped,
  clusters.OccupancySensing.attributes.Occupancy,
}

local function create_subscription(device)
  local subscribe_request = clusters.CameraAvStreamManagement.attributes.AttributeList:subscribe(device)
  subscribe_request:merge(cluster_base.subscribe(device, nil, camera_fields.CameraAVSMFeatureMapAttr.cluster,
    camera_fields.CameraAVSMFeatureMapAttr.ID))
  subscribe_request:merge(cluster_base.subscribe(device, nil, camera_fields.CameraAVSULMFeatureMapAttr.cluster,
    camera_fields.CameraAVSULMFeatureMapAttr.ID))
  subscribe_request:merge(cluster_base.subscribe(device, nil, camera_fields.ZoneManagementFeatureMapAttr.cluster,
    camera_fields.ZoneManagementFeatureMapAttr.ID))
  for _, attr in ipairs(additional_subscriptions) do
    subscribe_request:merge(attr:subscribe(device))
  end
  return subscribe_request
end

local expected_metadata = {
  optional_component_capabilities = {
    {"main", {
        "videoCapture2", "cameraViewportSettings", "videoStreamSettings",
        "localMediaStorage", "audioRecording", "cameraPrivacyMode",
        "imageControl", "hdr", "nightVision",
        "mechanicalPanTiltZoom", "zoneManagement", "webrtc",
        "motionSensor",
      }
    },
    {"speaker", {"audioMute", "audioVolume"}},
    {"microphone", {"audioMute", "audioVolume"}}
  },
  profile = "camera"
}

local mock_device_handler_testing = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("camera.yml", { enabled_optional_capabilities = expected_metadata.optional_component_capabilities }),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware = 1, software = 1},
  endpoints = endpoints
})

local function test_init()
  test.mock_device.add_test_device(mock_device_handler_testing)
  mock_device_handler_testing:set_field(switch_fields.profiling_data.STATUS_LIGHT_BRIGHTNESS_PRESENT, false, {persist=true})
  mock_device_handler_testing:set_field(switch_fields.profiling_data.STATUS_LIGHT_ENABLED_PRESENT, false, {persist=true})
  test.socket.device_lifecycle:__queue_receive({ mock_device_handler_testing.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_handler_testing.id, "init" })
  test.socket.matter:__expect_send({ mock_device_handler_testing.id, create_subscription(mock_device_handler_testing) })
  test.socket.device_lifecycle:__queue_receive({ mock_device_handler_testing.id, "doConfigure" })
  mock_device_handler_testing:expect_metadata_update(expected_metadata)
  mock_device_handler_testing:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "Software version change should initialize camera capabilities when profile is unchanged",
  function()
    mock_device_handler_testing:set_field(switch_fields.profiling_data.STATUS_LIGHT_BRIGHTNESS_PRESENT, false)
    mock_device_handler_testing:set_field(switch_fields.profiling_data.STATUS_LIGHT_ENABLED_PRESENT, false)
    local camera_utils = require "sub_drivers.camera.camera_utils.utils"
    camera_utils.optional_capabilities_list_changed = function () return false end -- integration profile ref logic makes this fn inaccurate

    local unchanged_profile = t_utils.get_profile_definition("camera.yml", { enabled_optional_capabilities = expected_metadata.optional_component_capabilities })
    unchanged_profile.id = "00000000-1111-2222-3333-000000000002"
    unchanged_profile.preferences = nil
    test.socket.device_lifecycle:__queue_receive(
      mock_device_handler_testing:generate_info_changed({ matter_version = { hardware = 1, software = 2 }, profile = unchanged_profile })
    )
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Software version change should trigger camera reprofiling when camera endpoint is present",
  function()
    mock_device_handler_testing:set_field(switch_fields.profiling_data.STATUS_LIGHT_BRIGHTNESS_PRESENT, false)
    mock_device_handler_testing:set_field(switch_fields.profiling_data.STATUS_LIGHT_ENABLED_PRESENT, false)
    test.socket.device_lifecycle:__queue_receive(
      mock_device_handler_testing:generate_info_changed({ matter_version = { hardware = 1, software = 2 } })
    )
    mock_device_handler_testing:expect_metadata_update(expected_metadata)
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Camera FeatureMap change should reinitialize capabilities when profile is unchanged",
  function()
    local camera_cfg = require "sub_drivers.camera.camera_utils.device_configuration"
    local reconcile_called = false
    local original_reconcile = camera_cfg.reconcile_profile_and_capabilities
    camera_cfg.reconcile_profile_and_capabilities = function(_)
      reconcile_called = true
      return false
    end
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      cluster_base.build_test_report_data(mock_device_handler_testing, CAMERA_EP, camera_fields.CameraAVSMFeatureMapAttr.cluster, camera_fields.CameraAVSMFeatureMapAttr.ID, uint32(0))
    })
    test.wait_for_events()
    camera_cfg.reconcile_profile_and_capabilities = original_reconcile
    assert(reconcile_called, "reconcile_profile_and_capabilities should be called")
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Night Vision reports should generate appropriate events",
  function()
    local cluster_to_capability_map = {
      {cluster = clusters.CameraAvStreamManagement.server.attributes.NightVision, capability = capabilities.nightVision.nightVision},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.NightVisionIllum, capability = capabilities.nightVision.illumination}
    }
    for _, v in ipairs(cluster_to_capability_map) do
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        v.cluster:build_test_report_data(mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.OFF)
      })
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message("main", v.capability("off"))
      )
      if v.capability == capabilities.nightVision.illumination then
        test.socket.capability:__expect_send(
          mock_device_handler_testing:generate_test_message("main", capabilities.nightVision.supportedAttributes({"illumination"}))
        )
      end
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        v.cluster:build_test_report_data(mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.ON)
      })
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message("main", v.capability("on"))
      )
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        v.cluster:build_test_report_data(mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.AUTO)
      })
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message("main", v.capability("auto"))
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Image Rotation reports should generate appropriate events",
  function()
    local utils = require "st.utils"
    local first_value = true
    for angle = 0, 400, 50 do
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        clusters.CameraAvStreamManagement.server.attributes.ImageRotation:build_test_report_data(mock_device_handler_testing, CAMERA_EP, angle)
      })
      local clamped_angle = utils.clamp_value(angle, 0, 359)
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message("main", capabilities.imageControl.imageRotation(clamped_angle))
      )
      if first_value then
        test.socket.capability:__expect_send(
          mock_device_handler_testing:generate_test_message("main", capabilities.imageControl.supportedAttributes({"imageRotation"}))
        )
        first_value = false
      end
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Two Way Talk Support reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.TwoWayTalkSupport:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.HALF_DUPLEX
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.webrtc.talkback(true))
    )
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.webrtc.talkbackDuplex("halfDuplex"))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.TwoWayTalkSupport:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.FULL_DUPLEX
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.webrtc.talkback(true))
    )
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.webrtc.talkbackDuplex("fullDuplex"))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.TwoWayTalkSupport:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.NOT_SUPPORTED
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.webrtc.talkback(false))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Muted reports should generate appropriate events",
  function()
    local cluster_to_component_map = {
      {cluster = clusters.CameraAvStreamManagement.server.attributes.SpeakerMuted, component = "speaker"},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.MicrophoneMuted, component = "microphone"}
    }
    for _, v in ipairs(cluster_to_component_map) do
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        v.cluster:build_test_report_data(mock_device_handler_testing, CAMERA_EP, true)
      })
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message(v.component, capabilities.audioMute.mute("muted"))
      )
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        v.cluster:build_test_report_data(mock_device_handler_testing, CAMERA_EP, false)
      })
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message(v.component, capabilities.audioMute.mute("unmuted"))
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Volume Level reports should generate appropriate events",
  function()
    local max_vol = 200
    local min_vol = 0
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMaxLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMinLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, min_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMaxLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMinLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, min_vol)
    })
    test.wait_for_events()
    local cluster_to_component_map = {
      { cluster = clusters.CameraAvStreamManagement.server.attributes.SpeakerVolumeLevel, component = "speaker"},
      { cluster = clusters.CameraAvStreamManagement.server.attributes.MicrophoneVolumeLevel, component = "microphone"}
    }
    for _, v in ipairs(cluster_to_component_map) do
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        v.cluster:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 130)
      })
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message(v.component, capabilities.audioVolume.volume(65))
      )
      test.socket.matter:__queue_receive({
        mock_device_handler_testing.id,
        v.cluster:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 64)
      })
      test.socket.capability:__expect_send(
        mock_device_handler_testing:generate_test_message(v.component, capabilities.audioVolume.volume(32))
      )
    end
  end,
  {
     min_api_version = 17
  }
)

local function receive_rate_distortion_trade_off_points()
  test.socket.matter:__queue_receive({
    mock_device_handler_testing.id,
    clusters.CameraAvStreamManagement.attributes.RateDistortionTradeOffPoints:build_test_report_data(
      mock_device_handler_testing, CAMERA_EP, {
        clusters.CameraAvStreamManagement.types.RateDistortionTradeOffPointsStruct({
          codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
          resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({
            width = 1920,
            height = 1080
          }),
          min_bit_rate = 5000000
        }),
        clusters.CameraAvStreamManagement.types.RateDistortionTradeOffPointsStruct({
          codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.HEVC,
          resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({
            width = 3840,
            height = 2160
          }),
          min_bit_rate = 20000000
        })
      }
    )
  })
end

local function receive_max_encoded_pixel_rate()
  test.socket.matter:__queue_receive({
    mock_device_handler_testing.id,
    clusters.CameraAvStreamManagement.attributes.MaxEncodedPixelRate:build_test_report_data(
      mock_device_handler_testing, CAMERA_EP, 124416000) -- 1080p @ 60 fps or 4K @ 15 fps
  })
end

local function receive_min_viewport()
  test.socket.matter:__queue_receive({
    mock_device_handler_testing.id,
    clusters.CameraAvStreamManagement.attributes.MinViewportResolution:build_test_report_data(
      mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.VideoResolutionStruct({
        width = 1920,
        height = 1080
      })
    )
  })
end

local function receive_video_sensor_params()
  test.socket.matter:__queue_receive({
    mock_device_handler_testing.id,
    clusters.CameraAvStreamManagement.attributes.VideoSensorParams:build_test_report_data(
      mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.VideoSensorParamsStruct({
        sensor_width = 7360,
        sensor_height = 4912,
        max_fps = 60,
        max_hdrfps = 30
      })
    )
  })
end

local function emit_min_viewport()
  test.socket.capability:__expect_send(
    mock_device_handler_testing:generate_test_message("main", capabilities.cameraViewportSettings.minViewportResolution({
      width = 1920,
      height = 1080,
    }))
  )
end

local function emit_video_sensor_parameters()
  test.socket.capability:__expect_send(
    mock_device_handler_testing:generate_test_message("main", capabilities.cameraViewportSettings.videoSensorParameters({
      width = 7360,
      height = 4912,
      maxFPS = 60
    }))
  )
end

local function emit_supported_resolutions()
  test.socket.capability:__expect_send(
    mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.supportedResolutions({
      {
        width = 1920,
        height = 1080,
        fps = 60
      },
      {
        width = 3840,
        height = 2160,
        fps = 15
      },
      {
        width = 7360,
        height = 4912,
        fps = 0
      }
    }))
  )
end

-- Test receiving RateDistortionTradeOffPoints, MaxEncodedPixelRate, and VideoSensorParams in various orders
-- to ensure that cameraViewportSettings and videoStreamSettings capabilities are updated as expected. Note that
-- cameraViewportSettings.videoSensorParameters is set in the VideoSensorParams handler and
-- videoStreamSettings.supportedResolutions is emitted after all three attributes are received.

test.register_coroutine_test(
  "Rate Distortion Trade Off Points, MaxEncodedPixelRate, MinViewport, VideoSensorParams reports should generate appropriate events",
  function()
    receive_rate_distortion_trade_off_points()
    receive_max_encoded_pixel_rate()
    receive_min_viewport()
    emit_min_viewport()
    receive_video_sensor_params()
    emit_video_sensor_parameters()
    emit_supported_resolutions()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Rate Distortion Trade Off Points, MinViewport, VideoSensorParams, MaxEncodedPixelRate reports should generate appropriate events",
  function()
    receive_rate_distortion_trade_off_points()
    receive_min_viewport()
    emit_min_viewport()
    receive_video_sensor_params()
    emit_video_sensor_parameters()
    receive_max_encoded_pixel_rate()
    emit_supported_resolutions()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "MaxEncodedPixelRate, MinViewport, VideoSensorParams, Rate Distortion Trade Off Points reports should generate appropriate events",
  function()
    receive_max_encoded_pixel_rate()
    receive_min_viewport()
    emit_min_viewport()
    receive_video_sensor_params()
    emit_video_sensor_parameters()
    receive_rate_distortion_trade_off_points()
    emit_supported_resolutions()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "PTZ Position reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.PanMax:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 150)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.PanMin:build_test_report_data(mock_device_handler_testing, CAMERA_EP, -150)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.panRange({value = {minimum = -150, maximum = 150}}))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMax:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 80)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMin:build_test_report_data(mock_device_handler_testing, CAMERA_EP, -80)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tiltRange({value = {minimum = -80, maximum = 80}}))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.ZoomMax:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 70)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoomRange({value = {minimum = 1, maximum = 70}}))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {pan = 10, tilt = 20, zoom = 30})
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.pan(10))
    )
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tilt(20))
    )
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoom(30))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "PTZ Presets reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPresets:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {{preset_id = 1, name = "Preset 1", settings = {pan = 10, tilt = 20, zoom = 30}},
                                 {preset_id = 2, name = "Preset 2", settings = {pan = -55, tilt = 80, zoom = 60}}}
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.presets({
        { id = 1, label = "Preset 1", pan = 10, tilt = 20, zoom = 30},
        { id = 2, label = "Preset 2", pan = -55, tilt = 80, zoom = 60}
      }))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Max Presets reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MaxPresets:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 10)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.maxPresets(10))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Max Zones reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.MaxZones:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 10)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.maxZones(10))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Zones reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.Zones:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.ZoneManagement.types.ZoneInformationStruct({
            zone_id = 1,
            zone_type = clusters.ZoneManagement.types.ZoneTypeEnum.TWODCART_ZONE,
            zone_source = clusters.ZoneManagement.types.ZoneSourceEnum.MFG,
            two_d_cartesian_zone = clusters.ZoneManagement.types.TwoDCartesianZoneStruct({
              name = "Zone 1",
              use = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
              vertices = {
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({ x = 0, y = 0 }),
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({ x = 1920, y = 1080 })
              },
              color = "#FFFFFF"
            })
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.zones({
        {
          id = 1,
          name = "Zone 1",
          type = "2DCartesian",
          polygonVertices = {
            {vertex = {x = 0, y = 0}},
            {vertex = {x = 1920, y = 1080}}
          },
          source = "manufacturer",
          use = "motion",
          color = "#FFFFFF"
        }
      }))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Triggers reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.Triggers:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.ZoneManagement.types.ZoneTriggerControlStruct({
            zone_id = 1,
            initial_duration = 8,
            augmentation_duration = 4,
            max_duration = 20,
            blind_duration = 3,
            sensitivity = 4
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.triggers({
        {
          zoneId = 1,
          initialDuration = 8,
          augmentationDuration = 4,
          maxDuration = 20,
          blindDuration = 3,
          sensitivity = 4
        }
      }))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Sensitivity reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.SensitivityMax:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 7)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.sensitivityRange({ minimum = 1, maximum = 7},
        {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.Sensitivity:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 5)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.sensitivity(5, {visibility = {displayed = false}}))
    )
  end,
  {
     min_api_version = 17
  }
)

-- Event Handler UTs

test.register_coroutine_test(
  "Zone events should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.events.ZoneTriggered:build_test_event_report(mock_device_handler_testing, CAMERA_EP, {
        zone = 2,
        reason = clusters.ZoneManagement.types.ZoneEventTriggeredReasonEnum.MOTION
      })
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.triggeredZones({{zoneId = 2}}))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.events.ZoneTriggered:build_test_event_report(mock_device_handler_testing, CAMERA_EP, {
        zone = 3,
        reason = clusters.ZoneManagement.types.ZoneEventTriggeredReasonEnum.MOTION
      })
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.triggeredZones({{zoneId = 2}, {zoneId = 3}}))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.events.ZoneStopped:build_test_event_report(mock_device_handler_testing, CAMERA_EP, {
        zone = 2,
        reason = clusters.ZoneManagement.types.ZoneEventStoppedReasonEnum.ACTION_STOPPED
      })
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.triggeredZones({{zoneId = 3}}))
    )
  end,
  {
     min_api_version = 17
  }
)

-- Capability Handler UTs

test.register_coroutine_test(
  "Set night vision commands should send the appropriate commands",
  function()
    local command_to_attribute_map = {
      ["setNightVision"] = clusters.CameraAvStreamManagement.attributes.NightVision,
      ["setIllumination"] = clusters.CameraAvStreamManagement.attributes.NightVisionIllum
    }
    for cmd, attr in pairs(command_to_attribute_map) do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "nightVision", component = "main", command = cmd, args = { "off" } },
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, attr:write(mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.OFF)
      })
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "nightVision", component = "main", command = cmd, args = { "on" } },
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, attr:write(mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.ON)
      })
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "nightVision", component = "main", command = cmd, args = { "auto" } },
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, attr:write(mock_device_handler_testing, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.AUTO)
      })
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set enabled commands should send the appropriate commands",
  function()
    local command_to_attribute_map = {
      ["setHdr"] = { capability = "hdr", attr = clusters.CameraAvStreamManagement.attributes.HDRModeEnabled},
      ["setImageFlipHorizontal"] = { capability = "imageControl", attr = clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal},
      ["setImageFlipVertical"] = { capability = "imageControl", attr = clusters.CameraAvStreamManagement.attributes.ImageFlipVertical},
      ["setSoftLivestreamPrivacyMode"] = { capability = "cameraPrivacyMode", attr = clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled},
      ["setSoftRecordingPrivacyMode"] = { capability = "cameraPrivacyMode", attr = clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled},
      ["setLocalSnapshotRecording"] = { capability = "localMediaStorage", attr = clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled},
      ["setLocalVideoRecording"] = { capability = "localMediaStorage", attr = clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled}
    }
    for i, v in pairs(command_to_attribute_map) do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = v.capability, component = "main", command = i, args = { "enabled" } },
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, v.attr:write(mock_device_handler_testing, CAMERA_EP, true)
      })
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = v.capability, component = "main", command = i, args = { "disabled" } },
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, v.attr:write(mock_device_handler_testing, CAMERA_EP, false)
      })
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set image rotation command should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "imageControl", component = "main", command = "setImageRotation", args = { 10 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.ImageRotation:write(mock_device_handler_testing, CAMERA_EP, 10)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "imageControl", component = "main", command = "setImageRotation", args = { 257 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.ImageRotation:write(mock_device_handler_testing, CAMERA_EP, 257)
    })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set mute commands should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "speaker", command = "setMute", args = { "muted" } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device_handler_testing, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "speaker", command = "setMute", args = { "unmuted" } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device_handler_testing, CAMERA_EP, false)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "speaker", command = "mute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device_handler_testing, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "speaker", command = "unmute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device_handler_testing, CAMERA_EP, false)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "microphone", command = "setMute", args = { "muted" } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device_handler_testing, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "microphone", command = "setMute", args = { "unmuted" } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device_handler_testing, CAMERA_EP, false)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "microphone", command = "mute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device_handler_testing, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioMute", component = "microphone", command = "unmute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device_handler_testing, CAMERA_EP, false)
    })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set Volume command should send the appropriate commands",
  function()
    local max_vol = 200
    local min_vol = 5
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMaxLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMinLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, min_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMaxLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMinLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, min_vol)
    })
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioVolume", component = "speaker", command = "setVolume", args = { 0 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(mock_device_handler_testing, CAMERA_EP, 5)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioVolume", component = "speaker", command = "setVolume", args = { 35 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(mock_device_handler_testing, CAMERA_EP, 73)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioVolume", component = "microphone", command = "setVolume", args = { 77 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(mock_device_handler_testing, CAMERA_EP, 155)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioVolume", component = "microphone", command = "setVolume", args = { 100 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(mock_device_handler_testing, CAMERA_EP, 200)
    })

    ---- test volumeUp command
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 103)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("speaker", capabilities.audioVolume.volume(50))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioVolume", component = "speaker", command = "volumeUp", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(mock_device_handler_testing, CAMERA_EP, 104)
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 104)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("speaker", capabilities.audioVolume.volume(51))
    )

    -- test volumeDown command
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 200)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("microphone", capabilities.audioVolume.volume(100))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "audioVolume", component = "microphone", command = "volumeDown", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(mock_device_handler_testing, CAMERA_EP, 198)
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:build_test_report_data(mock_device_handler_testing, CAMERA_EP, 198)
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("microphone", capabilities.audioVolume.volume(99))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set Relative PTZ commands should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "panRelative", args = { 10 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(mock_device_handler_testing, CAMERA_EP, 10, 0, 0)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "tiltRelative", args = { -35 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(mock_device_handler_testing, CAMERA_EP, 0, -35, 0)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "zoomRelative", args = { 80 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(mock_device_handler_testing, CAMERA_EP, 0, 0, 80)
    })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set PTZ commands should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setPanTiltZoom", args = { 10, 20, 30 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device_handler_testing, CAMERA_EP, 10, 20, 30)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {pan = 10, tilt = 20, zoom = 30})
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.pan(10))
    )
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tilt(20))
    )
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoom(30))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setPan", args = { 50 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device_handler_testing, CAMERA_EP, 50, 20, 30)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {pan = 50, tilt = 20, zoom = 30})
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.pan(50))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setTilt", args = { -44 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device_handler_testing, CAMERA_EP, 50, -44, 30)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {pan = 50, tilt = -44, zoom = 30})
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tilt(-44))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setZoom", args = { 5 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device_handler_testing, CAMERA_EP, 50, -44, 5)
    })
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {pan = 50, tilt = -44, zoom = 5})
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoom(5))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Preset commands should send the appropriate commands",
  function()
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "savePreset", args = { 1, "Preset 1" } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSavePreset(mock_device_handler_testing, CAMERA_EP, 1, "Preset 1")
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "removePreset", args = { 1 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRemovePreset(mock_device_handler_testing, CAMERA_EP, 1)
    })
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "moveToPreset", args = { 2 } },
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZMoveToPreset(mock_device_handler_testing, CAMERA_EP, 2)
    })
  end,
  {
     min_api_version = 17
  }
)


test.register_coroutine_test(
  "Zone Management zone commands should send the appropriate commands",
  function()
    local use_map = {
      ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
      ["focus"] = clusters.ZoneManagement.types.ZoneUseEnum.FOCUS,
      ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
    }
    for i, v in pairs(use_map) do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "zoneManagement", component = "main", command = "newZone", args = {
          i .. " zone", {{value = {x = 0, y = 0}}, {value = {x = 1920, y = 1080}} }, i, "#FFFFFF"
        }}
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.CreateTwoDCartesianZone(mock_device_handler_testing, CAMERA_EP,
          clusters.ZoneManagement.types.TwoDCartesianZoneStruct(
            {
              name = i .. " zone",
              use = v,
              vertices = {
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 0, y = 0}),
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 1920, y = 1080})
              },
              color = "#FFFFFF"
            }
          )
        )
      })
    end
    local zone_id = 1
    for i, v in pairs(use_map) do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "zoneManagement", component = "main", command = "updateZone", args = {
          zone_id, "updated " .. i .. " zone", {{value = {x = 50, y = 50}}, {value = {x = 1000, y = 1000}} }, i, "red"
        }}
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.UpdateTwoDCartesianZone(mock_device_handler_testing, CAMERA_EP,
          zone_id,
          clusters.ZoneManagement.types.TwoDCartesianZoneStruct(
            {
              name = "updated " .. i .. " zone",
              use = v,
              vertices = {
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({ x = 50, y = 50 }),
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({ x = 1000, y = 1000 })
              },
              color = "red"
            }
          )
        )
      })
      zone_id = zone_id + 1
    end
    for i = 1, 3 do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "zoneManagement", component = "main", command = "removeZone", args = { i } }
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.RemoveZone(mock_device_handler_testing, CAMERA_EP, i)
      })
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Zone Management zone commands should send the appropriate commands - missing optional color argument",
  function()
    local use_map = {
      ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
      ["focus"] = clusters.ZoneManagement.types.ZoneUseEnum.FOCUS,
      ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
    }
    for i, v in pairs(use_map) do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "zoneManagement", component = "main", command = "newZone", args = {
          i .. " zone", {{value = {x = 0, y = 0}}, {value = {x = 1920, y = 1080}} }, i
        }}
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.CreateTwoDCartesianZone(mock_device_handler_testing, CAMERA_EP,
          clusters.ZoneManagement.types.TwoDCartesianZoneStruct(
            {
              name = i .. " zone",
              use = v,
              vertices = {
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 0, y = 0}),
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 1920, y = 1080})
              },
            }
          )
        )
      })
    end
    local zone_id = 1
    for i, v in pairs(use_map) do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "zoneManagement", component = "main", command = "updateZone", args = {
          zone_id, "updated " .. i .. " zone", {{value = {x = 50, y = 50}}, {value = {x = 1000, y = 1000}} }, i, "red"
        }}
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.UpdateTwoDCartesianZone(mock_device_handler_testing, CAMERA_EP,
          zone_id,
          clusters.ZoneManagement.types.TwoDCartesianZoneStruct(
            {
              name = "updated " .. i .. " zone",
              use = v,
              vertices = {
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({ x = 50, y = 50 }),
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({ x = 1000, y = 1000 })
              },
              color = "red"
            }
          )
        )
      })
      zone_id = zone_id + 1
    end
    for i = 1, 3 do
      test.socket.capability:__queue_receive({
        mock_device_handler_testing.id,
        { capability = "zoneManagement", component = "main", command = "removeZone", args = { i } }
      })
      test.socket.matter:__expect_send({
        mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.RemoveZone(mock_device_handler_testing, CAMERA_EP, i)
      })
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Zone Management trigger commands should send the appropriate commands",
  function()
    -- Create the trigger
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "zoneManagement", component = "main", command = "createOrUpdateTrigger", args = {
        1, 10, 3, 15, 3, 5
      }}
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.CreateOrUpdateTrigger(mock_device_handler_testing, CAMERA_EP, {
        zone_id = 1,
        initial_duration = 10,
        augmentation_duration = 3,
        max_duration = 15,
        blind_duration = 3,
        sensitivity = 5
      })
    })

    -- The device reports the Triggers attribute with the newly created trigger and the capability is updated
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.Triggers:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.ZoneManagement.types.ZoneTriggerControlStruct({
            zone_id = 1, initial_duration = 10, augmentation_duration = 3, max_duration = 15, blind_duration = 3, sensitivity = 5
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.triggers({{
        zoneId = 1, initialDuration = 10, augmentationDuration = 3, maxDuration = 15, blindDuration = 3, sensitivity = 5
      }}))
    )
    test.wait_for_events()

    -- Update trigger, note that some arguments are optional. In this case,
    -- blindDuration is not specified in the capability command.

    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "zoneManagement", component = "main", command = "createOrUpdateTrigger", args = {
          1, 8, 7, 25, 3, 1
      }}
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.CreateOrUpdateTrigger(mock_device_handler_testing, CAMERA_EP, {
        zone_id = 1,
        initial_duration = 8,
        augmentation_duration = 7,
        max_duration = 25,
        blind_duration = 3,
        sensitivity = 1
      })
    })

    -- Remove the trigger
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "zoneManagement", component = "main", command = "removeTrigger", args = { 1 } }
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.RemoveTrigger(mock_device_handler_testing, CAMERA_EP, 1)
    })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Removing a zone with an existing trigger should send RemoveTrigger followed by RemoveZone",
  function()
    -- Create a zone
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "zoneManagement", component = "main", command = "newZone", args = {
        "motion zone", {{value = {x = 0, y = 0}}, {value = {x = 1920, y = 1080}}}, "motion", "#FFFFFF"
      }}
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.CreateTwoDCartesianZone(mock_device_handler_testing, CAMERA_EP,
        clusters.ZoneManagement.types.TwoDCartesianZoneStruct({
          name = "motion zone",
          use = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
          vertices = {
            clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 0, y = 0}),
            clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 1920, y = 1080})
          },
          color = "#FFFFFF"
        })
      )
    })

    -- Create a trigger
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "zoneManagement", component = "main", command = "createOrUpdateTrigger", args = {
        1, 10, 3, 15, 3, 5
      }}
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.CreateOrUpdateTrigger(mock_device_handler_testing, CAMERA_EP, {
        zone_id = 1,
        initial_duration = 10,
        augmentation_duration = 3,
        max_duration = 15,
        blind_duration = 3,
        sensitivity = 5
      })
    })

    -- Receive the Triggers attribute update from the device reflecting the new trigger
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.Triggers:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.ZoneManagement.types.ZoneTriggerControlStruct({
            zone_id = 1, initial_duration = 10, augmentation_duration = 3,
            max_duration = 15, blind_duration = 3, sensitivity = 5
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.triggers({{
        zoneId = 1, initialDuration = 10, augmentationDuration = 3,
        maxDuration = 15, blindDuration = 3, sensitivity = 5
      }}))
    )
    test.wait_for_events()

    -- Receive removeZone command: since a trigger exists for zone 1, RemoveTrigger is sent first, then RemoveZone
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      { capability = "zoneManagement", component = "main", command = "removeZone", args = { 1 } }
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.RemoveTrigger(mock_device_handler_testing, CAMERA_EP, 1)
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.ZoneManagement.server.commands.RemoveZone(mock_device_handler_testing, CAMERA_EP, 1)
    })
    test.wait_for_events()

    -- Receive the updated Zones attribute from the device with the zone removed
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.ZoneManagement.attributes.Zones:build_test_report_data(mock_device_handler_testing, CAMERA_EP, {})
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.zoneManagement.zones({value = {}}))
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "setStream with label and viewport changes should emit capability event",
  function()
    -- Set up an existing stream
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 3,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 3,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = {
              width = 1920,
              height = 1080,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 1920, y = 1080 }
            },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.wait_for_events()
    -- Change label and viewport only
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      {
        capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        3,
        "liveStream",  -- type
        "My Stream",  -- label
        { width = 1920, height = 1080, fps = 30 },  -- resolution
        { upperLeftVertex = {x = 100, y = 100}, lowerRightVertex = {x = 1820, y = 980} },  -- viewport
        "disabled",  -- watermark
        "disabled"  -- onScreenDisplay
      }}
    })
    -- Should send DPTZSetViewport command
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.DPTZSetViewport(mock_device_handler_testing, CAMERA_EP,
        3,
        clusters.Global.types.ViewportStruct({
          x1 = 100,
          x2 = 1820,
          y1 = 100,
          y2 = 980
        })
      )
    })
    -- Should emit updated capability directly, no stream reallocation
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 3,
          data = {
            label = "My Stream",
            type = "liveStream",
            resolution = {
              width = 1920,
              height = 1080,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 100, y = 100 },
              lowerRightVertex = { x = 1820, y = 980 }
            },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "setStream with only watermark/OSD changes should use VideoStreamModify",
  function()
    -- Set up an existing stream
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 1,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 640, height = 360}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 640, height = 360}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = true,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 1,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = {
              width = 640,
              height = 360,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 640, y = 360 }
            },
            watermark = "enabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.wait_for_events()
    -- Change watermark and OSD only
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      {
        capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        1,
        "liveStream",  -- type
        "Stream 1",  -- label
        { width = 640, height = 360, fps = 30 },  -- resolution
        { upperLeftVertex = {x = 0, y = 0}, lowerRightVertex = {x = 640, y = 360} },  -- viewport
        "disabled",  -- watermark
        "enabled"  -- onScreenDisplay
      }}
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.server.commands.VideoStreamModify(mock_device_handler_testing, CAMERA_EP,
        1, false, true
      )
    })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "setStream with only label change should emit capability event",
  function()

    -- Set up existing stream
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 2,
            stream_usage = clusters.Global.types.StreamUsageEnum.RECORDING,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 15,
            max_frame_rate = 30,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1280, height = 720}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1280, height = 720}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 2,
          data = {
            label = "Stream 1",
            type = "clipRecording",
            resolution = {
              width = 1280,
              height = 720,
              fps = 15
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 1280, y = 720 }
            },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.wait_for_events()
    -- Change label only
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      {
        capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        2,
        "clipRecording",  -- type
        "Recording Stream",  -- label
        { width = 1280, height = 720, fps = 15 },  -- resolution
        { upperLeftVertex = {x = 0, y = 0}, lowerRightVertex = {x = 1280, y = 720} },  -- viewport
        "disabled",  -- watermark
        "disabled"  -- onScreenDisplay
      }}
    })
    -- Should emit updated capability directly, no stream reallocation
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 2,
          data = {
            label = "Recording Stream",
            type = "clipRecording",
            resolution = {
              width = 1280,
              height = 720,
              fps = 15
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 1280, y = 720 }
            },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
  end
)

test.register_coroutine_test(
  "setStream with only viewport change should send DPTZSetViewport command",
  function()

    -- Set up existing stream
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 5,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 3840, height = 2160}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 3840, height = 2160}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = true,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 5,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = {
              width = 3840,
              height = 2160,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 3840, y = 2160 }
            },
            watermark = "disabled",
            onScreenDisplay = "enabled"
          }
        }
      }))
    )
    test.wait_for_events()
    -- Change only viewport
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      {
        capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        5,
        "liveStream",  -- type
        "Stream 1",  -- label
        { width = 3840, height = 2160, fps = 30 },  -- resolution
        { upperLeftVertex = {x = 500, y = 500}, lowerRightVertex = {x = 3340, y = 1660} },  -- viewport
        "disabled",  -- watermark
        "enabled"  -- onScreenDisplay
      }}
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.DPTZSetViewport(mock_device_handler_testing, CAMERA_EP,
        5,
        clusters.Global.types.ViewportStruct({
          x1 = 500,
          x2 = 3340,
          y1 = 500,
          y2 = 1660
        })
      )
    })
    -- Should emit updated capability directly, no stream reallocation
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 5,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = {
              width = 3840,
              height = 2160,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 500, y = 500 },
              lowerRightVertex = { x = 3340, y = 1660 }
            },
            watermark = "disabled",
            onScreenDisplay = "enabled"
          }
        }
      }))
    )
  end
)

test.register_coroutine_test(
  "setStream with resolution change should trigger reallocation",
  function()

    -- Set up existing stream
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 1,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1280, height = 720}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1280, height = 720}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = true,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 1,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = {
              width = 1280,
              height = 720,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 1280, y = 720 }
            },
            watermark = "enabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.wait_for_events()
    -- Change resolution and reallocate stream
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      {
        capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        1,
        "liveStream",  -- type
        "HD Stream",  -- label
        { width = 1920, height = 1080, fps = 30 },  -- resolution
        { upperLeftVertex = {x = 0, y = 0}, lowerRightVertex = {x = 1280, y = 720} },  -- viewport
        "enabled",  -- watermark
        "disabled"  -- onScreenDisplay
      }}
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 1,
          data = {
            label = "HD Stream",
            type = "liveStream",
            resolution = {
              width = 1280,
              height = 720,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 1280, y = 720 }
            },
            watermark = "enabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.server.commands.VideoStreamDeallocate(mock_device_handler_testing, CAMERA_EP, 1)
    })
    test.socket.matter:__expect_send({
      mock_device_handler_testing.id, clusters.CameraAvStreamManagement.server.commands.VideoStreamAllocate(mock_device_handler_testing, CAMERA_EP,
        clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
        clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
        30,
        60,
        clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
        clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
        10000,
        2000000,
        4000,
        true,
        false
      )
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 1,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 1,
          data = {
            label = "HD Stream",
            type = "liveStream",
            resolution = {
              width = 1920,
              height = 1080,
              fps = 30
            },
            viewport = {
              upperLeftVertex = { x = 0, y = 0 },
              lowerRightVertex = { x = 1920, y = 1080 }
            },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
  end
)

test.register_coroutine_test(
  "Stream label should persist across attribute reports",
  function()

    -- Set up existing stream
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 3,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 640, height = 480}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 640, height = 480}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 3,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = { width = 640, height = 480, fps = 30 },
            viewport = { upperLeftVertex = { x = 0, y = 0 }, lowerRightVertex = { x = 640, y = 480 } },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.wait_for_events()
    -- Change label
    test.socket.capability:__queue_receive({
      mock_device_handler_testing.id,
      {
        capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        3,
        "liveStream",  -- type
        "My Camera",  -- label
        { width = 640, height = 480, fps = 30 },  -- resolution
        { upperLeftVertex = {x = 0, y = 0}, lowerRightVertex = {x = 640, y = 480} },  -- viewport
        "disabled",  -- watermark
        "disabled"  -- onScreenDisplay
      }}
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 3,
          data = {
            label = "My Camera",
            type = "liveStream",
            resolution = { width = 640, height = 480, fps = 30 },
            viewport = { upperLeftVertex = { x = 0, y = 0 }, lowerRightVertex = { x = 640, y = 480 } },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.wait_for_events()
    -- Simulate another AllocatedVideoStreams report
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 3,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 640, height = 480}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 640, height = 480}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    -- Should preserve the custom label from capability state
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 3,
          data = {
            label = "My Camera",
            type = "liveStream",
            resolution = { width = 640, height = 480, fps = 30 },
            viewport = { upperLeftVertex = { x = 0, y = 0 }, lowerRightVertex = { x = 640, y = 480 } },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
  end
)

test.register_coroutine_test(
  "DPTZStreams attribute should update viewports in capability",
  function()

    -- Set up multiple existing streams
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 1,
            stream_usage = clusters.Global.types.StreamUsageEnum.LIVE_VIEW,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 30,
            max_frame_rate = 60,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1920, height = 1080}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = false,
            reference_count = 0
          }),
          clusters.CameraAvStreamManagement.types.VideoStreamStruct({
            video_stream_id = 2,
            stream_usage = clusters.Global.types.StreamUsageEnum.RECORDING,
            video_codec = clusters.CameraAvStreamManagement.types.VideoCodecEnum.H264,
            min_frame_rate = 15,
            max_frame_rate = 30,
            min_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1280, height = 720}),
            max_resolution = clusters.CameraAvStreamManagement.types.VideoResolutionStruct({width = 1280, height = 720}),
            min_bit_rate = 10000,
            max_bit_rate = 10000,
            key_frame_interval = 4000,
            watermark_enabled = false,
            osd_enabled = false,
            reference_count = 0
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 1,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = { width = 1920, height = 1080, fps = 30 },
            viewport = { upperLeftVertex = { x = 0, y = 0 }, lowerRightVertex = { x = 1920, y = 1080 } },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        },
        {
          streamId = 2,
          data = {
            label = "Stream 2",
            type = "clipRecording",
            resolution = { width = 1280, height = 720, fps = 15 },
            viewport = { upperLeftVertex = { x = 0, y = 0 }, lowerRightVertex = { x = 1280, y = 720 } },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.socket.matter:__queue_receive({
      mock_device_handler_testing.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.DPTZStreams:build_test_report_data(
        mock_device_handler_testing, CAMERA_EP, {
          clusters.CameraAvSettingsUserLevelManagement.types.DPTZStruct({
            video_stream_id = 1,
            viewport = clusters.Global.types.ViewportStruct({
              x1 = 200,
              x2 = 1720,
              y1 = 100,
              y2 = 980
            })
          }),
          clusters.CameraAvSettingsUserLevelManagement.types.DPTZStruct({
            video_stream_id = 2,
            viewport = clusters.Global.types.ViewportStruct({
              x1 = 50,
              x2 = 1230,
              y1 = 50,
              y2 = 670
            })
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device_handler_testing:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
        {
          streamId = 1,
          data = {
            label = "Stream 1",
            type = "liveStream",
            resolution = { width = 1920, height = 1080, fps = 30 },
            viewport = { upperLeftVertex = { x = 200, y = 100 }, lowerRightVertex = { x = 1720, y = 980 } },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        },
        {
          streamId = 2,
          data = {
            label = "Stream 2",
            type = "clipRecording",
            resolution = { width = 1280, height = 720, fps = 15 },
            viewport = { upperLeftVertex = { x = 50, y = 50 }, lowerRightVertex = { x = 1230, y = 670 } },
            watermark = "disabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
  end
)

test.run_registered_tests()
