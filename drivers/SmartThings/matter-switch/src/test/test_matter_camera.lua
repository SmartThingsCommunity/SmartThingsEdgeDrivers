-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local t_utils = require "integration_test.utils"
local test = require "integration_test"

test.disable_startup_messages()

local CAMERA_EP, FLOODLIGHT_EP, CHIME_EP, DOORBELL_EP = 1, 2, 3, 4

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("camera.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware = 1, software = 1},
  endpoints = {
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
            clusters.CameraAvStreamManagement.types.Feature.PRIVACY |
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
          feature_map = clusters.CameraAvSettingsUserLevelManagement.types.Feature.MECHANICAL_PAN |
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
          cluster_id = clusters.WebRTCTransportRequestor.ID,
          cluster_type = "CLIENT"
        },
        {
          cluster_id = clusters.OccupancySensing.ID,
          cluster_type = "SERVER"
        }
      },
      device_types = {
        {device_type_id = 0x0142, device_type_revision = 1} -- Camera
      }
    },
    {
      endpoint_id = FLOODLIGHT_EP,
      clusters = {
        {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
        {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
        {cluster_id = clusters.ColorControl.ID, cluster_type = "BOTH", feature_map = 30}
      },
      device_types = {
        {device_type_id = 0x010D, device_type_revision = 2} -- Extended Color Light
      }
    },
    {
      endpoint_id = CHIME_EP,
      clusters = {
        {
          cluster_id = clusters.Chime.ID,
          cluster_type = "SERVER"
        },
      },
      device_types = {
        {device_type_id = 0x0146, device_type_revision = 1} -- Chime
      }
    },
    {
      endpoint_id = DOORBELL_EP,
      clusters = {
        {
          cluster_id = clusters.Switch.ID,
          feature_map = clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_MULTI_PRESS |
            clusters.Switch.types.SwitchFeature.MOMENTARY_SWITCH_LONG_PRESS,
          cluster_type = "SERVER",
        }
      },
      device_types = {
        {device_type_id = 0x0143, device_type_revision = 1} -- Doorbell
      }
    }
  }
})

local subscribe_request
local subscribed_attributes = {
  clusters.CameraAvStreamManagement.attributes.AttributeList,
  clusters.CameraAvStreamManagement.attributes.StatusLightEnabled,
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
  clusters.ColorControl.attributes.CurrentY,
  clusters.ColorControl.attributes.ColorMode,
}

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  local floodlight_child_device_data = {
    profile = t_utils.get_profile_definition("light-color-level.yml"),
    device_network_id = string.format("%s:%d", mock_device.id, FLOODLIGHT_EP),
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", FLOODLIGHT_EP)
  }
  test.mock_device.add_test_device(test.mock_device.build_test_child_device(floodlight_child_device_data))
  mock_device:expect_device_create({
    type = "EDGE_CHILD",
    label = "Floodlight 1",
    profile = "light-color-level",
    parent_device_id = mock_device.id,
    parent_assigned_child_key = string.format("%d", FLOODLIGHT_EP)
  })
  subscribe_request = subscribed_attributes[1]:subscribe(mock_device)
  for i, attr in ipairs(subscribed_attributes) do
    if i > 1 then subscribe_request:merge(attr:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

local additional_subscribed_attributes = {
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
  clusters.CameraAvStreamManagement.attributes.StatusLightBrightness,
  clusters.CameraAvStreamManagement.attributes.StatusLightEnabled,
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
  clusters.Chime.attributes.InstalledChimeSounds,
  clusters.Chime.attributes.SelectedChime,
  clusters.ZoneManagement.attributes.MaxZones,
  clusters.ZoneManagement.attributes.Zones,
  clusters.ZoneManagement.attributes.Triggers,
  clusters.ZoneManagement.attributes.SensitivityMax,
  clusters.ZoneManagement.attributes.Sensitivity,
  clusters.ZoneManagement.events.ZoneTriggered,
  clusters.ZoneManagement.events.ZoneStopped,
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
  clusters.ColorControl.attributes.CurrentY,
  clusters.OccupancySensing.attributes.Occupancy,
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.MultiPressComplete
}

local expected_metadata = {
  optional_component_capabilities = {
    {
      "main",
      {
        "videoCapture2",
        "cameraViewportSettings",
        "localMediaStorage",
        "audioRecording",
        "cameraPrivacyMode",
        "imageControl",
        "hdr",
        "nightVision",
        "mechanicalPanTiltZoom",
        "videoStreamSettings",
        "zoneManagement",
        "webrtc",
        "motionSensor",
        "sounds",
      }
    },
    {
      "statusLed",
      {
        "switch",
        "mode"
      }
    },
    {
      "speaker",
      {
        "audioMute",
        "audioVolume"
      }
    },
    {
      "microphone",
      {
        "audioMute",
        "audioVolume"
      }
    },
    {
      "doorbell",
      {
        "button"
      }
    }
  },
  profile = "camera"
}

local function update_device_profile()
  local uint32 = require "st.matter.data_types.Uint32"
  test.socket.matter:__queue_receive({
    mock_device.id,
    clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device, CAMERA_EP, {
      uint32(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID),
      uint32(clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID)
    })
  })
  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, DOORBELL_EP)})
  mock_device:expect_metadata_update(expected_metadata)
  local updated_device_profile = t_utils.get_profile_definition(
    "camera.yml", {enabled_optional_capabilities = expected_metadata.optional_component_capabilities}
  )
  test.wait_for_events()
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = updated_device_profile }))
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.webrtc.supportedFeatures(
      {audio="sendrecv", bundle=true, order="audio/video", supportTrickleICE=true, turnSource="player", video="recvonly"}
    ))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.supportedAttributes(
      {"pan", "panRange", "tilt", "tiltRange", "zoom", "zoomRange", "presets", "maxPresets"}
    ))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.zoneManagement.supportedFeatures(
      {"triggerAugmentation", "perZoneSensitivity"}
    ))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.localMediaStorage.supportedAttributes(
      {"localVideoRecording"}
    ))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.audioRecording.audioRecording("enabled"))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.videoStreamSettings.supportedFeatures(
      {"liveStreaming", "clipRecording", "perStreamViewports", "watermark", "onScreenDisplay"}
    ))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.cameraPrivacyMode.supportedAttributes(
      {"softRecordingPrivacyMode", "softLivestreamPrivacyMode"}
    ))
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.cameraPrivacyMode.supportedCommands(
      {"setSoftRecordingPrivacyMode", "setSoftLivestreamPrivacyMode"}
    ))
  )
  for _, attr in ipairs(additional_subscribed_attributes) do
    subscribe_request:merge(attr:subscribe(mock_device))
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
  test.socket.matter:__expect_send({mock_device.id, clusters.Switch.attributes.MultiPressMax:read(mock_device, DOORBELL_EP)})
  test.socket.capability:__expect_send(mock_device:generate_test_message("doorbell", capabilities.button.button.pushed({state_change = false})))
end

-- Matter Handler UTs

test.register_coroutine_test(
  "Reports mapping to EnabledState capability data type should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    local cluster_to_capability_map = {
      {cluster = clusters.CameraAvStreamManagement.server.attributes.HDRModeEnabled, capability = capabilities.hdr.hdr},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.ImageFlipHorizontal, capability = capabilities.imageControl.imageFlipHorizontal},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.ImageFlipVertical, capability = capabilities.imageControl.imageFlipVertical},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.SoftRecordingPrivacyModeEnabled, capability = capabilities.cameraPrivacyMode.softRecordingPrivacyMode},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.SoftLivestreamPrivacyModeEnabled, capability = capabilities.cameraPrivacyMode.softLivestreamPrivacyMode},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.HardPrivacyModeOn, capability = capabilities.cameraPrivacyMode.hardPrivacyMode},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.LocalSnapshotRecordingEnabled, capability = capabilities.localMediaStorage.localSnapshotRecording},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.LocalVideoRecordingEnabled, capability = capabilities.localMediaStorage.localVideoRecording}
    }
    for _, v in ipairs(cluster_to_capability_map) do
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, true)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", v.capability("enabled"))
      )
      if v.capability == capabilities.imageControl.imageFlipHorizontal then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.imageControl.supportedAttributes({"imageFlipHorizontal"}))
        )
      elseif v.capability == capabilities.imageControl.imageFlipVertical then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.imageControl.supportedAttributes({"imageFlipHorizontal", "imageFlipVertical"}))
        )
      elseif v.capability == capabilities.cameraPrivacyMode.hardPrivacyMode then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.cameraPrivacyMode.supportedAttributes({"softRecordingPrivacyMode", "softLivestreamPrivacyMode", "hardPrivacyMode"}))
        )
      end
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, false)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", v.capability("disabled"))
      )
    end
  end
)

test.register_coroutine_test(
  "Night Vision reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    local cluster_to_capability_map = {
      {cluster = clusters.CameraAvStreamManagement.server.attributes.NightVision, capability = capabilities.nightVision.nightVision},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.NightVisionIllum, capability = capabilities.nightVision.illumination}
    }
    for _, v in ipairs(cluster_to_capability_map) do
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.OFF)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", v.capability("off"))
      )
      if v.capability == capabilities.nightVision.illumination then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.nightVision.supportedAttributes({"illumination"}))
        )
      end
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.ON)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", v.capability("on"))
      )
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.AUTO)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", v.capability("auto"))
      )
    end
  end
)

test.register_coroutine_test(
  "Image Rotation reports should generate appropriate events",
  function()
    local utils = require "st.utils"
    update_device_profile()
    test.wait_for_events()
    local first_value = true
    for angle = 0, 400, 50 do
      test.socket.matter:__queue_receive({
        mock_device.id,
        clusters.CameraAvStreamManagement.server.attributes.ImageRotation:build_test_report_data(mock_device, CAMERA_EP, angle)
      })
      local clamped_angle = utils.clamp_value(angle, 0, 359)
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", capabilities.imageControl.imageRotation(clamped_angle))
      )
      if first_value then
        test.socket.capability:__expect_send(
          mock_device:generate_test_message("main", capabilities.imageControl.supportedAttributes({"imageRotation"}))
        )
        first_value = false
      end
    end
  end
)

test.register_coroutine_test(
  "Two Way Talk Support reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.TwoWayTalkSupport:build_test_report_data(
        mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.HALF_DUPLEX
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.webrtc.talkback(true))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.webrtc.talkbackDuplex("halfDuplex"))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.TwoWayTalkSupport:build_test_report_data(
        mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.FULL_DUPLEX
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.webrtc.talkback(true))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.webrtc.talkbackDuplex("fullDuplex"))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.TwoWayTalkSupport:build_test_report_data(
        mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.NOT_SUPPORTED
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.webrtc.talkback(false))
    )
  end
)

test.register_coroutine_test(
  "Muted reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    local cluster_to_component_map = {
      {cluster = clusters.CameraAvStreamManagement.server.attributes.SpeakerMuted, component = "speaker"},
      {cluster = clusters.CameraAvStreamManagement.server.attributes.MicrophoneMuted, component = "microphone"}
    }
    for _, v in ipairs(cluster_to_component_map) do
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, true)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(v.component, capabilities.audioMute.mute("muted"))
      )
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, false)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(v.component, capabilities.audioMute.mute("unmuted"))
      )
    end
  end
)

test.register_coroutine_test(
  "Volume Level reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    local max_vol = 200
    local min_vol = 0
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMaxLevel:build_test_report_data(mock_device, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMinLevel:build_test_report_data(mock_device, CAMERA_EP, min_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMaxLevel:build_test_report_data(mock_device, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMinLevel:build_test_report_data(mock_device, CAMERA_EP, min_vol)
    })
    test.wait_for_events()
    local cluster_to_component_map = {
      { cluster = clusters.CameraAvStreamManagement.server.attributes.SpeakerVolumeLevel, component = "speaker"},
      { cluster = clusters.CameraAvStreamManagement.server.attributes.MicrophoneVolumeLevel, component = "microphone"}
    }
    for _, v in ipairs(cluster_to_component_map) do
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, 130)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(v.component, capabilities.audioVolume.volume(65))
      )
      test.socket.matter:__queue_receive({
        mock_device.id,
        v.cluster:build_test_report_data(mock_device, CAMERA_EP, 64)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message(v.component, capabilities.audioVolume.volume(32))
      )
    end
  end
)

test.register_coroutine_test(
  "Status Light Enabled reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:build_test_report_data(mock_device, CAMERA_EP, true)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.switch.switch.on())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:build_test_report_data(mock_device, CAMERA_EP, false)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.switch.switch.off())
    )
  end
)

test.register_coroutine_test(
  "Status Light Brightness reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:build_test_report_data(
        mock_device, CAMERA_EP, clusters.Global.types.ThreeLevelAutoEnum.LOW)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.supportedModes(
        {"low", "medium", "high", "auto"}, {visibility = {displayed = false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.supportedArguments(
        {"low", "medium", "high", "auto"}, {visibility = {displayed = false}})
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.mode("low"))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:build_test_report_data(
        mock_device, CAMERA_EP, clusters.Global.types.ThreeLevelAutoEnum.MEDIUM)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.mode("medium"))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:build_test_report_data(
        mock_device, CAMERA_EP, clusters.Global.types.ThreeLevelAutoEnum.HIGH)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.mode("high"))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:build_test_report_data(
        mock_device, CAMERA_EP, clusters.Global.types.ThreeLevelAutoEnum.AUTO)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.mode("auto"))
    )
  end
)

local function receive_rate_distortion_trade_off_points()
  test.socket.matter:__queue_receive({
    mock_device.id,
    clusters.CameraAvStreamManagement.attributes.RateDistortionTradeOffPoints:build_test_report_data(
      mock_device, CAMERA_EP, {
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
    mock_device.id,
    clusters.CameraAvStreamManagement.attributes.MaxEncodedPixelRate:build_test_report_data(
      mock_device, CAMERA_EP, 124416000) -- 1080p @ 60 fps or 4K @ 15 fps
  })
end

local function receive_video_sensor_params()
  test.socket.matter:__queue_receive({
    mock_device.id,
    clusters.CameraAvStreamManagement.attributes.VideoSensorParams:build_test_report_data(
      mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.VideoSensorParamsStruct({
        sensor_width = 7360,
        sensor_height = 4912,
        max_fps = 60,
        max_hdrfps = 30
      })
    )
  })
end

local function emit_video_sensor_parameters()
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.cameraViewportSettings.videoSensorParameters({
      width = 7360,
      height = 4912,
      maxFPS = 60
    }))
  )
end

local function emit_supported_resolutions()
  test.socket.capability:__expect_send(
    mock_device:generate_test_message("main", capabilities.videoStreamSettings.supportedResolutions({
      {
        width = 1920,
        height = 1080,
        fps = 60
      },
      {
        width = 3840,
        height = 2160,
        fps = 15
      }
    }))
  )
end

-- Test receiving RateDistortionTradeOffPoints, MaxEncodedPixelRate, and VideoSensorParams in various orders
-- to ensure that cameraViewportSettings and videoStreamSettings capabilities are updated as expected. Note that
-- cameraViewportSettings.videoSensorParameters is set in the VideoSensorParams handler and
-- videoStreamSettings.supportedResolutions is emitted after all three attributes are received.

test.register_coroutine_test(
  "Rate Distortion Trade Off Points, MaxEncodedPixelRate, VideoSensorParams reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    receive_rate_distortion_trade_off_points()
    receive_max_encoded_pixel_rate()
    receive_video_sensor_params()
    emit_video_sensor_parameters()
    emit_supported_resolutions()
  end
)

test.register_coroutine_test(
  "Rate Distortion Trade Off Points, VideoSensorParams, MaxEncodedPixelRate reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    receive_rate_distortion_trade_off_points()
    receive_video_sensor_params()
    emit_video_sensor_parameters()
    receive_max_encoded_pixel_rate()
    emit_supported_resolutions()
  end
)

test.register_coroutine_test(
  "MaxEncodedPixelRate, VideoSensorParams, Rate Distortion Trade Off Points reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    receive_max_encoded_pixel_rate()
    receive_video_sensor_params()
    emit_video_sensor_parameters()
    receive_rate_distortion_trade_off_points()
    emit_supported_resolutions()
  end
)

test.register_coroutine_test(
  "PTZ Position reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.PanMax:build_test_report_data(mock_device, CAMERA_EP, 150)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.PanMin:build_test_report_data(mock_device, CAMERA_EP, -150)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.panRange({value = {minimum = -150, maximum = 150}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMax:build_test_report_data(mock_device, CAMERA_EP, 80)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMin:build_test_report_data(mock_device, CAMERA_EP, -80)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tiltRange({value = {minimum = -80, maximum = 80}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.ZoomMax:build_test_report_data(mock_device, CAMERA_EP, 70)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoomRange({value = {minimum = 1, maximum = 70}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device, CAMERA_EP, {pan = 10, tilt = 20, zoom = 30})
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.pan(10))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tilt(20))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoom(30))
    )
  end
)

test.register_coroutine_test(
  "PTZ Presets reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPresets:build_test_report_data(
        mock_device, CAMERA_EP, {{preset_id = 1, name = "Preset 1", settings = {pan = 10, tilt = 20, zoom = 30}},
                                 {preset_id = 2, name = "Preset 2", settings = {pan = -55, tilt = 80, zoom = 60}}}
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.presets({
        { id = 1, label = "Preset 1", pan = 10, tilt = 20, zoom = 30},
        { id = 2, label = "Preset 2", pan = -55, tilt = 80, zoom = 60}
      }))
    )
  end
)

test.register_coroutine_test(
  "Max Presets reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MaxPresets:build_test_report_data(mock_device, CAMERA_EP, 10)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.maxPresets(10))
    )
  end
)

test.register_coroutine_test(
  "Max Zones reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.attributes.MaxZones:build_test_report_data(mock_device, CAMERA_EP, 10)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.zoneManagement.maxZones(10))
    )
  end
)

test.register_coroutine_test(
  "Zones reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.attributes.Zones:build_test_report_data(
        mock_device, CAMERA_EP, {
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
      mock_device:generate_test_message("main", capabilities.zoneManagement.zones({
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
  end
)

test.register_coroutine_test(
  "Triggers reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.attributes.Triggers:build_test_report_data(
        mock_device, CAMERA_EP, {
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
      mock_device:generate_test_message("main", capabilities.zoneManagement.triggers({
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
  end
)

test.register_coroutine_test(
  "Sensitivity reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.attributes.SensitivityMax:build_test_report_data(mock_device, CAMERA_EP, 7)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.zoneManagement.sensitivityRange({ minimum = 1, maximum = 7},
        {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.attributes.Sensitivity:build_test_report_data(mock_device, CAMERA_EP, 5)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.zoneManagement.sensitivity(5, {visibility = {displayed = false}}))
    )
  end
)

test.register_coroutine_test(
  "Chime reports should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Chime.attributes.InstalledChimeSounds:build_test_report_data(mock_device, CAMERA_EP, {
        clusters.Chime.types.ChimeSoundStruct({chime_id = 1, name = "Sound 1"}),
        clusters.Chime.types.ChimeSoundStruct({chime_id = 2, name = "Sound 2"})
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.sounds.supportedSounds({
        {id = 1, label = "Sound 1"},
        {id = 2, label = "Sound 2"},
      }, {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Chime.attributes.SelectedChime:build_test_report_data(mock_device, CAMERA_EP, 2)
    })
    test.socket.capability:__expect_send(mock_device:generate_test_message("main", capabilities.sounds.selectedSound(2)))
  end
)

-- Event Handler UTs

test.register_coroutine_test(
  "Zone events should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.events.ZoneTriggered:build_test_event_report(mock_device, CAMERA_EP, {
        zone = 2,
        reason = clusters.ZoneManagement.types.ZoneEventTriggeredReasonEnum.MOTION
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.zoneManagement.triggeredZones({{zoneId = 2}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.events.ZoneTriggered:build_test_event_report(mock_device, CAMERA_EP, {
        zone = 3,
        reason = clusters.ZoneManagement.types.ZoneEventTriggeredReasonEnum.MOTION
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.zoneManagement.triggeredZones({{zoneId = 2}, {zoneId = 3}}))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ZoneManagement.events.ZoneStopped:build_test_event_report(mock_device, CAMERA_EP, {
        zone = 2,
        reason = clusters.ZoneManagement.types.ZoneEventStoppedReasonEnum.ACTION_STOPPED
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.zoneManagement.triggeredZones({{zoneId = 3}}))
    )
  end
)

test.register_coroutine_test(
  "Button events should generate appropriate events",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.server.events.InitialPress:build_test_event_report(mock_device, DOORBELL_EP, {new_position = 1})
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.Switch.server.events.MultiPressComplete:build_test_event_report(mock_device, DOORBELL_EP, {
        new_position = 1,
        total_number_of_presses_counted = 2,
        previous_position = 0
      })
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("doorbell", capabilities.button.button.double({state_change = true}))
    )
  end
)

-- Capability Handler UTs

test.register_coroutine_test(
  "Set night vision commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    local command_to_attribute_map = {
      ["setNightVision"] = clusters.CameraAvStreamManagement.attributes.NightVision,
      ["setIllumination"] = clusters.CameraAvStreamManagement.attributes.NightVisionIllum
    }
    for cmd, attr in pairs(command_to_attribute_map) do
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "nightVision", component = "main", command = cmd, args = { "off" } },
      })
      test.socket.matter:__expect_send({
        mock_device.id, attr:write(mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.OFF)
      })
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "nightVision", component = "main", command = cmd, args = { "on" } },
      })
      test.socket.matter:__expect_send({
        mock_device.id, attr:write(mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.ON)
      })
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "nightVision", component = "main", command = cmd, args = { "auto" } },
      })
      test.socket.matter:__expect_send({
        mock_device.id, attr:write(mock_device, CAMERA_EP, clusters.CameraAvStreamManagement.types.TriStateAutoEnum.AUTO)
      })
    end
  end
)

test.register_coroutine_test(
  "Set enabled commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
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
        mock_device.id,
        { capability = v.capability, component = "main", command = i, args = { "enabled" } },
      })
      test.socket.matter:__expect_send({
        mock_device.id, v.attr:write(mock_device, CAMERA_EP, true)
      })
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = v.capability, component = "main", command = i, args = { "disabled" } },
      })
      test.socket.matter:__expect_send({
        mock_device.id, v.attr:write(mock_device, CAMERA_EP, false)
      })
    end
  end
)

test.register_coroutine_test(
  "Set image rotation command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "imageControl", component = "main", command = "setImageRotation", args = { 10 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.ImageRotation:write(mock_device, CAMERA_EP, 10)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "imageControl", component = "main", command = "setImageRotation", args = { 257 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.ImageRotation:write(mock_device, CAMERA_EP, 257)
    })
  end
)

test.register_coroutine_test(
  "Set mute commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "speaker", command = "setMute", args = { "muted" } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "speaker", command = "setMute", args = { "unmuted" } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device, CAMERA_EP, false)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "speaker", command = "mute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "speaker", command = "unmute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.SpeakerMuted:write(mock_device, CAMERA_EP, false)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "microphone", command = "setMute", args = { "muted" } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "microphone", command = "setMute", args = { "unmuted" } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device, CAMERA_EP, false)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "microphone", command = "mute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioMute", component = "microphone", command = "unmute", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.MicrophoneMuted:write(mock_device, CAMERA_EP, false)
    })
  end
)

test.register_coroutine_test(
  "Set Volume command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    local max_vol = 200
    local min_vol = 5
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMaxLevel:build_test_report_data(mock_device, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.SpeakerMinLevel:build_test_report_data(mock_device, CAMERA_EP, min_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMaxLevel:build_test_report_data(mock_device, CAMERA_EP, max_vol)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.server.attributes.MicrophoneMinLevel:build_test_report_data(mock_device, CAMERA_EP, min_vol)
    })
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioVolume", component = "speaker", command = "setVolume", args = { 0 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(mock_device, CAMERA_EP, 5)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioVolume", component = "speaker", command = "setVolume", args = { 35 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(mock_device, CAMERA_EP, 73)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioVolume", component = "microphone", command = "setVolume", args = { 77 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(mock_device, CAMERA_EP, 155)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioVolume", component = "microphone", command = "setVolume", args = { 100 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(mock_device, CAMERA_EP, 200)
    })

    ---- test volumeUp command
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:build_test_report_data(mock_device, CAMERA_EP, 103)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("speaker", capabilities.audioVolume.volume(50))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioVolume", component = "speaker", command = "volumeUp", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(mock_device, CAMERA_EP, 104)
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:build_test_report_data(mock_device, CAMERA_EP, 104)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("speaker", capabilities.audioVolume.volume(51))
    )

    -- test volumeDown command
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:build_test_report_data(mock_device, CAMERA_EP, 200)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("microphone", capabilities.audioVolume.volume(100))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "audioVolume", component = "microphone", command = "volumeDown", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(mock_device, CAMERA_EP, 198)
    })
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:build_test_report_data(mock_device, CAMERA_EP, 198)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("microphone", capabilities.audioVolume.volume(99))
    )
  end
)

test.register_coroutine_test(
  "Set Mode command should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    local mode_to_enum_map = {
      ["low"] = clusters.Global.types.ThreeLevelAutoEnum.LOW,
      ["medium"] = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM,
      ["high"] = clusters.Global.types.ThreeLevelAutoEnum.HIGH,
      ["auto"] = clusters.Global.types.ThreeLevelAutoEnum.AUTO
    }
    for i, v in pairs(mode_to_enum_map) do
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "mode", component = "speaker", command = "setMode", args = { i } },
      })
      test.socket.matter:__expect_send({
        mock_device.id, clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:write(mock_device, CAMERA_EP, v)
      })
    end
  end
)

test.register_coroutine_test(
  "Set Status LED commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "statusLed", command = "on", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(mock_device, CAMERA_EP, true)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "statusLed", command = "off", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(mock_device, CAMERA_EP, false)
    })
  end
)

test.register_coroutine_test(
  "Set Relative PTZ commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "panRelative", args = { 10 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(mock_device, CAMERA_EP, 10, 0, 0)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "tiltRelative", args = { -35 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(mock_device, CAMERA_EP, 0, -35, 0)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "zoomRelative", args = { 80 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(mock_device, CAMERA_EP, 0, 0, 80)
    })
  end
)

test.register_coroutine_test(
  "Set PTZ commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setPanTiltZoom", args = { 10, 20, 30 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device, CAMERA_EP, 10, 20, 30)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device, CAMERA_EP, {pan = 10, tilt = 20, zoom = 30})
    })
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.pan(10))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tilt(20))
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoom(30))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setPan", args = { 50 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device, CAMERA_EP, 50, 20, 30)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device, CAMERA_EP, {pan = 50, tilt = 20, zoom = 30})
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.pan(50))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setTilt", args = { -44 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device, CAMERA_EP, 50, -44, 30)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device, CAMERA_EP, {pan = 50, tilt = -44, zoom = 30})
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.tilt(-44))
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "setZoom", args = { 5 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(mock_device, CAMERA_EP, 50, -44, 5)
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition:build_test_report_data(
        mock_device, CAMERA_EP, {pan = 50, tilt = -44, zoom = 5})
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.zoom(5))
    )
  end
)

test.register_coroutine_test(
  "Preset commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "savePreset", args = { 1, "Preset 1" } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSavePreset(mock_device, CAMERA_EP, 1, "Preset 1")
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "removePreset", args = { 1 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRemovePreset(mock_device, CAMERA_EP, 1)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "mechanicalPanTiltZoom", component = "main", command = "moveToPreset", args = { 2 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZMoveToPreset(mock_device, CAMERA_EP, 2)
    })
  end
)

test.register_coroutine_test(
  "Sound commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "sounds", component = "main", command = "setSelectedSound", args = { 1 } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.Chime.attributes.SelectedChime:write(mock_device, CAMERA_EP, 1)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "sounds", component = "main", command = "playSound", args = {} },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.Chime.server.commands.PlayChimeSound(mock_device, CAMERA_EP)
    })
  end
)

test.register_coroutine_test(
  "Zone Management zone commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    local use_map = {
      ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
      ["focus"] = clusters.ZoneManagement.types.ZoneUseEnum.FOCUS,
      ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
    }
    for i, v in pairs(use_map) do
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "zoneManagement", component = "main", command = "newZone", args = {
          i .. " zone", {{value = {x = 0, y = 0}}, {value = {x = 1920, y = 1080}} }, i, "blue"
        }}
      })
      test.socket.matter:__expect_send({
        mock_device.id, clusters.ZoneManagement.server.commands.CreateTwoDCartesianZone(mock_device, CAMERA_EP,
          clusters.ZoneManagement.types.TwoDCartesianZoneStruct(
            {
              name = i .. " zone",
              use = v,
              vertices = {
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 0, y = 0}),
                clusters.ZoneManagement.types.TwoDCartesianVertexStruct({x = 1920, y = 1080})
              },
              color = "blue"
            }
          )
        )
      })
    end
    local zone_id = 1
    for i, v in pairs(use_map) do
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "zoneManagement", component = "main", command = "updateZone", args = {
          zone_id, "updated " .. i .. " zone", {{value = {x = 50, y = 50}}, {value = {x = 1000, y = 1000}} }, i, "red"
        }}
      })
      test.socket.matter:__expect_send({
        mock_device.id, clusters.ZoneManagement.server.commands.UpdateTwoDCartesianZone(mock_device, CAMERA_EP,
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
        mock_device.id,
        { capability = "zoneManagement", component = "main", command = "removeZone", args = { i } }
      })
      test.socket.matter:__expect_send({
        mock_device.id, clusters.ZoneManagement.server.commands.RemoveZone(mock_device, CAMERA_EP, i)
      })
    end
  end
)

test.register_coroutine_test(
  "Zone Management zone commands should send the appropriate commands - missing optional color argument",
  function()
    update_device_profile()
    test.wait_for_events()
    local use_map = {
      ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
      ["focus"] = clusters.ZoneManagement.types.ZoneUseEnum.FOCUS,
      ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
    }
    for i, v in pairs(use_map) do
      test.socket.capability:__queue_receive({
        mock_device.id,
        { capability = "zoneManagement", component = "main", command = "newZone", args = {
          i .. " zone", {{value = {x = 0, y = 0}}, {value = {x = 1920, y = 1080}} }, i
        }}
      })
      test.socket.matter:__expect_send({
        mock_device.id, clusters.ZoneManagement.server.commands.CreateTwoDCartesianZone(mock_device, CAMERA_EP,
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
        mock_device.id,
        { capability = "zoneManagement", component = "main", command = "updateZone", args = {
          zone_id, "updated " .. i .. " zone", {{value = {x = 50, y = 50}}, {value = {x = 1000, y = 1000}} }, i, "red"
        }}
      })
      test.socket.matter:__expect_send({
        mock_device.id, clusters.ZoneManagement.server.commands.UpdateTwoDCartesianZone(mock_device, CAMERA_EP,
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
        mock_device.id,
        { capability = "zoneManagement", component = "main", command = "removeZone", args = { i } }
      })
      test.socket.matter:__expect_send({
        mock_device.id, clusters.ZoneManagement.server.commands.RemoveZone(mock_device, CAMERA_EP, i)
      })
    end
  end
)

test.register_coroutine_test(
  "Zone Management trigger commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()

    -- Create the trigger
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "zoneManagement", component = "main", command = "createOrUpdateTrigger", args = {
        1, 10, 3, 15, 3, 5
      }}
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.ZoneManagement.server.commands.CreateOrUpdateTrigger(mock_device, CAMERA_EP, {
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
      mock_device.id,
      clusters.ZoneManagement.attributes.Triggers:build_test_report_data(
        mock_device, CAMERA_EP, {
          clusters.ZoneManagement.types.ZoneTriggerControlStruct({
            zone_id = 1, initial_duration = 10, augmentation_duration = 3, max_duration = 15, blind_duration = 3, sensitivity = 5
          })
        }
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.zoneManagement.triggers({{
        zoneId = 1, initialDuration = 10, augmentationDuration = 3, maxDuration = 15, blindDuration = 3, sensitivity = 5
      }}))
    )
    test.wait_for_events()

    -- Update trigger, note that some arguments are optional. In this case,
    -- blindDuration is not specified in the capability command.

    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "zoneManagement", component = "main", command = "createOrUpdateTrigger", args = {
          1, 8, 7, 25, 3, 1
      }}
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.ZoneManagement.server.commands.CreateOrUpdateTrigger(mock_device, CAMERA_EP, {
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
      mock_device.id,
      { capability = "zoneManagement", component = "main", command = "removeTrigger", args = { 1 } }
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.ZoneManagement.server.commands.RemoveTrigger(mock_device, CAMERA_EP, 1)
    })
  end
)

test.register_coroutine_test(
  "Stream management commands should send the appropriate commands",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        3,
        "liveStream",
        "Stream 3",
        { width = 1920, height = 1080, fps = 30 },
        { upperLeftVertex = {x = 0, y = 0}, lowerRightVertex = {x = 1920, y = 1080} },
        "enabled",
        "disabled"
      }}
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.server.commands.VideoStreamModify(mock_device, CAMERA_EP,
        3, true, false
      )
    })
  end
)

test.register_coroutine_test(
  "Stream management setStream command should modify an existing stream",
  function()
    update_device_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams:build_test_report_data(
        mock_device, CAMERA_EP, {
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
      mock_device:generate_test_message("main", capabilities.videoStreamSettings.videoStreams({
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
            watermark = "enabled",
            onScreenDisplay = "disabled"
          }
        }
      }))
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "videoStreamSettings", component = "main", command = "setStream", args = {
        1,
        "liveStream",
        "Stream 1",
        { width = 640, height = 360, fps = 30 },
        { upperLeftVertex = {x = 0, y = 0}, lowerRightVertex = {x = 640, y = 360} },
        "disabled",
        "enabled"
      }}
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.server.commands.VideoStreamModify(mock_device, CAMERA_EP,
        1, false, true
      )
    })
  end
)

-- run the tests
test.run_registered_tests()
