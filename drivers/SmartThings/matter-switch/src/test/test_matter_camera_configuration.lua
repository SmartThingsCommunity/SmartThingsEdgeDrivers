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

local CAMERA_EP_ID = 1
local CAMERA_EP = {
    endpoint_id = CAMERA_EP_ID,
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
      }
    },
    device_types = {
      {device_type_id = switch_fields.DEVICE_TYPE_ID.CAMERA, device_type_revision = 1}
    }
  }

local FLOODLIGHT_EP_ID = 3
local FLOODLIGHT_EP = {
  endpoint_id = FLOODLIGHT_EP_ID,
  clusters = {
    {cluster_id = clusters.OnOff.ID, cluster_type = "SERVER"},
    {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER", feature_map = 2},
  },
  device_types = {
    {device_type_id = switch_fields.DEVICE_TYPE_ID.LIGHT.DIMMABLE, device_type_revision = 2}
  }
}

local CHIME_EP_ID = 2
local CHIME_EP = {
  endpoint_id = CHIME_EP_ID,
  clusters = {
    {
      cluster_id = clusters.Chime.ID,
      cluster_type = "SERVER"
    },
  },
  device_types = {
    {device_type_id = switch_fields.DEVICE_TYPE_ID.CHIME, device_type_revision = 1} -- Chime
  }
}

local DOORBELL_EP_ID = 3
local DOORBELL_EP = {
  endpoint_id = DOORBELL_EP_ID,
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
    {device_type_id = switch_fields.DEVICE_TYPE_ID.DOORBELL, device_type_revision = 1}
  }
}

local chime_subscriptions = {
  clusters.Chime.attributes.InstalledChimeSounds,
  clusters.Chime.attributes.SelectedChime
}

local doorbell_subscriptions = {
  clusters.Switch.server.events.InitialPress,
  clusters.Switch.server.events.LongPress,
  clusters.Switch.server.events.ShortRelease,
  clusters.Switch.server.events.MultiPressComplete
}

local floodlight_subscriptions = {
  clusters.OnOff.attributes.OnOff,
  clusters.LevelControl.attributes.CurrentLevel,
  clusters.LevelControl.attributes.MaxLevel,
  clusters.LevelControl.attributes.MinLevel,
  clusters.CameraAvStreamManagement.attributes.StatusLightEnabled, -- also required due to switch cluster catching it
}

local status_led_subscriptions = {
  clusters.CameraAvStreamManagement.attributes.StatusLightEnabled,
  clusters.CameraAvStreamManagement.attributes.StatusLightBrightness
}

local camera_subscriptions = {
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
}

local function create_subscription(device, with_camera, with_status_led, with_floodlight, with_doorbell, with_chime)
  local subscribe_request = clusters.CameraAvStreamManagement.attributes.AttributeList:subscribe(device)
  subscribe_request:merge(cluster_base.subscribe(device, nil, camera_fields.CameraAVSMFeatureMapAttr.cluster, camera_fields.CameraAVSMFeatureMapAttr.ID))
  subscribe_request:merge(cluster_base.subscribe(device, nil, camera_fields.CameraAVSULMFeatureMapAttr.cluster, camera_fields.CameraAVSULMFeatureMapAttr.ID))
  subscribe_request:merge(cluster_base.subscribe(device, nil, camera_fields.ZoneManagementFeatureMapAttr.cluster, camera_fields.ZoneManagementFeatureMapAttr.ID))
  local merge_subscriptions = function(cluster_list)
    for _, attr in ipairs(cluster_list) do
      subscribe_request:merge(attr:subscribe(device))
    end
   end
  if with_camera then merge_subscriptions(camera_subscriptions) end
  if with_status_led then merge_subscriptions(status_led_subscriptions) end
  if with_floodlight then merge_subscriptions(floodlight_subscriptions) end
  if with_doorbell then merge_subscriptions(doorbell_subscriptions) end
  if with_chime then merge_subscriptions(chime_subscriptions) end
  return subscribe_request
end

local expected_metadata = {
  optional_component_capabilities = {
    {"main", {
        "videoCapture2", "cameraViewportSettings", "videoStreamSettings",
        "localMediaStorage", "audioRecording", "cameraPrivacyMode",
        "imageControl", "hdr", "nightVision",
        "mechanicalPanTiltZoom", "zoneManagement", "webrtc",
      }
    },
    {"speaker", {"audioMute", "audioVolume"}},
    {"microphone", {"audioMute", "audioVolume"}}
  },
  profile = "camera"
}

local expected_metadata_with_status_led = {
  optional_component_capabilities = {
    {"main", {
        "videoCapture2", "cameraViewportSettings", "videoStreamSettings",
        "localMediaStorage", "audioRecording", "cameraPrivacyMode",
        "imageControl", "hdr", "nightVision",
        "mechanicalPanTiltZoom", "zoneManagement", "webrtc",
      }
    },
    {"statusLed", {"switch", "mode"}},
    {"speaker", {"audioMute", "audioVolume"}},
    {"microphone", {"audioMute", "audioVolume"}}
  },
  profile = "camera"
}

local mock_device = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("camera.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware = 1, software = 1},
  endpoints = { CAMERA_EP }
})

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  test.socket.matter:__expect_send({ mock_device.id, create_subscription(mock_device, false) })
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

local function mock_initial_camera_update(device, updated_optional_component_capabilities, updated_subscription, with_doorbell_events)
  local updated_device_profile = t_utils.get_profile_definition(
    "camera.yml", {enabled_optional_capabilities = updated_optional_component_capabilities}
  )
  test.socket.device_lifecycle:__queue_receive(device:generate_info_changed({ profile = updated_device_profile }))
  if with_doorbell_events then
    test.socket.capability:__expect_send(device:generate_test_message("doorbell", capabilities.button.button.pushed({state_change = false})))
  end
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.webrtc.supportedFeatures(
      {audio="sendrecv", bundle=true, order="audio/video", supportTrickleICE=true, turnSource="player", video="recvonly"}
    ))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.mechanicalPanTiltZoom.supportedAttributes(
      {"pan", "panRange", "tilt", "tiltRange", "zoom", "zoomRange", "presets", "maxPresets"}
    ))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.zoneManagement.supportedFeatures(
      {"triggerAugmentation", "perZoneSensitivity"}
    ))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.localMediaStorage.supportedAttributes(
      {"localVideoRecording"}
    ))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.audioRecording.audioRecording("enabled"))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.videoStreamSettings.supportedFeatures(
      {"liveStreaming", "clipRecording", "perStreamViewports", "watermark", "onScreenDisplay"}
    ))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.cameraPrivacyMode.supportedAttributes(
      {"softRecordingPrivacyMode", "softLivestreamPrivacyMode"}
    ))
  )
  test.socket.capability:__expect_send(
    device:generate_test_message("main", capabilities.cameraPrivacyMode.supportedCommands(
      {"setSoftRecordingPrivacyMode", "setSoftLivestreamPrivacyMode"}
    ))
  )
  test.socket.matter:__expect_send({device.id, updated_subscription})
  if with_doorbell_events then
    test.socket.matter:__expect_send({device.id, clusters.Switch.attributes.MultiPressMax:read(device, DOORBELL_EP_ID)})
  end
  test.wait_for_events()
end

test.register_coroutine_test(
  "Initial profile update should trigger appropriate capability updates and subscriptions",
  function ()
    mock_initial_camera_update(mock_device, expected_metadata.optional_component_capabilities, create_subscription(mock_device, true))
  end,
  {
    min_api_version = 17
  }
)

test.register_coroutine_test(
  "Reports mapping to EnabledState capability data type should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device, CAMERA_EP_ID, {
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID),
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID)
      })
    })
    mock_device:expect_metadata_update(expected_metadata_with_status_led)
    test.wait_for_events()
    mock_initial_camera_update(mock_device, expected_metadata_with_status_led.optional_component_capabilities, create_subscription(mock_device, true, true))
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
        v.cluster:build_test_report_data(mock_device, CAMERA_EP_ID, true)
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
        v.cluster:build_test_report_data(mock_device, CAMERA_EP_ID, false)
      })
      test.socket.capability:__expect_send(
        mock_device:generate_test_message("main", v.capability("disabled"))
      )
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Status Light Enabled reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device, CAMERA_EP_ID, {
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID),
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID)
      })
    })
    mock_device:expect_metadata_update(expected_metadata_with_status_led)
    test.wait_for_events()
    mock_initial_camera_update(mock_device, expected_metadata_with_status_led.optional_component_capabilities, create_subscription(mock_device, true, true))
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:build_test_report_data(mock_device, CAMERA_EP_ID, true)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.switch.switch.on())
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:build_test_report_data(mock_device, CAMERA_EP_ID, false)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.switch.switch.off())
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Status Light Brightness reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device, CAMERA_EP_ID, {
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID),
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID)
      })
    })
    mock_device:expect_metadata_update(expected_metadata_with_status_led)
    test.wait_for_events()
    mock_initial_camera_update(mock_device, expected_metadata_with_status_led.optional_component_capabilities, create_subscription(mock_device, true, true))
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:build_test_report_data(
        mock_device, CAMERA_EP_ID, clusters.Global.types.ThreeLevelAutoEnum.LOW)
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
        mock_device, CAMERA_EP_ID, clusters.Global.types.ThreeLevelAutoEnum.MEDIUM)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.mode("medium"))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:build_test_report_data(
        mock_device, CAMERA_EP_ID, clusters.Global.types.ThreeLevelAutoEnum.HIGH)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.mode("high"))
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:build_test_report_data(
        mock_device, CAMERA_EP_ID, clusters.Global.types.ThreeLevelAutoEnum.AUTO)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("statusLed", capabilities.mode.mode("auto"))
    )
  end,
  {
     min_api_version = 17
  }
)


test.register_coroutine_test(
  "Set Mode command should send the appropriate commands",
  function()
    mock_initial_camera_update(mock_device, expected_metadata_with_status_led.optional_component_capabilities, create_subscription(mock_device, true, true))
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
        mock_device.id, clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:write(mock_device, CAMERA_EP_ID, v)
      })
    end
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Set Status LED commands should send the appropriate commands",
  function()
    mock_initial_camera_update(mock_device, expected_metadata_with_status_led.optional_component_capabilities, create_subscription(mock_device, true, true))
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "statusLed", command = "on", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(mock_device, CAMERA_EP_ID, true)
    })
    test.socket.capability:__queue_receive({
      mock_device.id,
      { capability = "switch", component = "statusLed", command = "off", args = { } },
    })
    test.socket.matter:__expect_send({
      mock_device.id, clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(mock_device, CAMERA_EP_ID, false)
    })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Camera profile should not update for an unchanged Status Light AttributeList report",
  function()
    local camera_cfg = require("sub_drivers.camera.camera_utils.device_configuration")
    local original_reconcile = camera_cfg.reconcile_profile_and_capabilities
    camera_cfg.reconcile_profile_and_capabilities = function(...) return false end

    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device, CAMERA_EP_ID, {
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID),
        uint32(clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID)
      })
    })
    test.wait_for_events()
    camera_cfg.reconcile_profile_and_capabilities = original_reconcile
  end,
  {
     min_api_version = 17
  }
)


local expected_metadata_with_doorbell_chime = {
  optional_component_capabilities = {
    {"main", {
        "videoCapture2", "cameraViewportSettings", "videoStreamSettings",
        "localMediaStorage", "audioRecording", "cameraPrivacyMode",
        "imageControl", "hdr", "nightVision",
        "mechanicalPanTiltZoom", "zoneManagement", "webrtc",
        "sounds" -- chime specific capability
      }
    },
    {"speaker", {"audioMute", "audioVolume"}},
    {"microphone", {"audioMute", "audioVolume"}},
    {"doorbell", {"button"}} -- doorbell specific component and capability
  },
  profile = "camera"
}

local mock_device_doorbell_chime_camera = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("camera.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware =   1, software = 1},
  endpoints = { CAMERA_EP, DOORBELL_EP, CHIME_EP }
})

local function test_init_doorbell_chime_camera()
  test.mock_device.add_test_device(mock_device_doorbell_chime_camera)
  test.socket.device_lifecycle:__queue_receive({ mock_device_doorbell_chime_camera.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_doorbell_chime_camera.id, "init" })
  test.socket.matter:__expect_send({ mock_device_doorbell_chime_camera.id, create_subscription(mock_device_doorbell_chime_camera) })
  test.socket.device_lifecycle:__queue_receive({ mock_device_doorbell_chime_camera.id, "doConfigure" })
  mock_device_doorbell_chime_camera:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end


test.register_coroutine_test(
  "Button events should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device_doorbell_chime_camera, CAMERA_EP_ID, {uint32(0)})
    })
    mock_device_doorbell_chime_camera:expect_metadata_update(expected_metadata_with_doorbell_chime)
    test.socket.matter:__expect_send({mock_device_doorbell_chime_camera.id, clusters.Switch.attributes.MultiPressMax:read(mock_device_doorbell_chime_camera, DOORBELL_EP_ID)})
    test.wait_for_events()
    mock_initial_camera_update(mock_device_doorbell_chime_camera, expected_metadata_with_doorbell_chime.optional_component_capabilities,
      create_subscription(mock_device_doorbell_chime_camera, true, false, false, true, true), true
    )

    test.socket.matter:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      clusters.Switch.server.events.InitialPress:build_test_event_report(mock_device_doorbell_chime_camera, DOORBELL_EP_ID, {new_position = 1})
    })
    test.socket.matter:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      clusters.Switch.server.events.MultiPressComplete:build_test_event_report(mock_device_doorbell_chime_camera, DOORBELL_EP_ID, {
        new_position = 1,
        total_number_of_presses_counted = 2,
        previous_position = 0
      })
    })
    test.socket.capability:__expect_send(
      mock_device_doorbell_chime_camera:generate_test_message("doorbell", capabilities.button.button.double({state_change = true}))
    )
  end,
  {
    test_init = test_init_doorbell_chime_camera
  },
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Sound commands should send the appropriate commands",
  function()
    test.socket.matter:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device_doorbell_chime_camera, CAMERA_EP_ID, {uint32(0)})
    })
    mock_device_doorbell_chime_camera:expect_metadata_update(expected_metadata_with_doorbell_chime)
    test.socket.matter:__expect_send({mock_device_doorbell_chime_camera.id, clusters.Switch.attributes.MultiPressMax:read(mock_device_doorbell_chime_camera, DOORBELL_EP_ID)})
    test.wait_for_events()
    mock_initial_camera_update(mock_device_doorbell_chime_camera, expected_metadata_with_doorbell_chime.optional_component_capabilities,
      create_subscription(mock_device_doorbell_chime_camera, true, false, false, true, true), true
    )

    test.socket.capability:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      { capability = "sounds", component = "main", command = "setSelectedSound", args = { 1 } },
    })
    test.socket.matter:__expect_send({
      mock_device_doorbell_chime_camera.id, clusters.Chime.attributes.SelectedChime:write(mock_device_doorbell_chime_camera, CAMERA_EP_ID, 1)
    })
    test.socket.capability:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      { capability = "sounds", component = "main", command = "playSound", args = {} },
    })
    test.socket.matter:__expect_send({
      mock_device_doorbell_chime_camera.id, clusters.Chime.server.commands.PlayChimeSound(mock_device_doorbell_chime_camera, CAMERA_EP_ID)
    })
  end,
  {
    test_init = test_init_doorbell_chime_camera
  },
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Chime reports should generate appropriate events",
  function()
    test.socket.matter:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device_doorbell_chime_camera, CAMERA_EP_ID, {uint32(0)})
    })
    mock_device_doorbell_chime_camera:expect_metadata_update(expected_metadata_with_doorbell_chime)
    test.socket.matter:__expect_send({mock_device_doorbell_chime_camera.id, clusters.Switch.attributes.MultiPressMax:read(mock_device_doorbell_chime_camera, DOORBELL_EP_ID)})
    test.wait_for_events()
    mock_initial_camera_update(mock_device_doorbell_chime_camera, expected_metadata_with_doorbell_chime.optional_component_capabilities,
      create_subscription(mock_device_doorbell_chime_camera, true, false, false, true, true), true
    )

    test.socket.matter:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      clusters.Chime.attributes.InstalledChimeSounds:build_test_report_data(mock_device_doorbell_chime_camera, CAMERA_EP_ID, {
        clusters.Chime.types.ChimeSoundStruct({chime_id = 1, name = "Sound 1"}),
        clusters.Chime.types.ChimeSoundStruct({chime_id = 2, name = "Sound 2"})
      })
    })
    test.socket.capability:__expect_send(
      mock_device_doorbell_chime_camera:generate_test_message("main", capabilities.sounds.supportedSounds({
        {id = 1, label = "Sound 1"},
        {id = 2, label = "Sound 2"},
      }, {visibility = {displayed = false}}))
    )
    test.socket.matter:__queue_receive({
      mock_device_doorbell_chime_camera.id,
      clusters.Chime.attributes.SelectedChime:build_test_report_data(mock_device_doorbell_chime_camera, CAMERA_EP_ID, 2)
    })
    test.socket.capability:__expect_send(mock_device_doorbell_chime_camera:generate_test_message("main", capabilities.sounds.selectedSound(2)))
  end,
  {
    test_init = test_init_doorbell_chime_camera
  },
  {
     min_api_version = 17
  }
)


local mock_device_floodlight_camera = test.mock_device.build_test_matter_device({
  profile = t_utils.get_profile_definition("camera.yml"),
  manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
  matter_version = {hardware = 1, software = 1},
  endpoints = { CAMERA_EP, FLOODLIGHT_EP }
})

local floodlight_child_device_data = {
  profile = t_utils.get_profile_definition("light-level.yml"),
  device_network_id = string.format("%s:%d", mock_device_floodlight_camera.id, FLOODLIGHT_EP_ID),
  parent_device_id = mock_device_floodlight_camera.id,
  parent_assigned_child_key = string.format("%d", FLOODLIGHT_EP_ID)
}
local mock_floodlight_child = test.mock_device.build_test_child_device(floodlight_child_device_data)

local function test_init_floodlight_camera()
  test.mock_device.add_test_device(mock_device_floodlight_camera)
  test.socket.device_lifecycle:__queue_receive({ mock_device_floodlight_camera.id, "added" })
  test.socket.device_lifecycle:__queue_receive({ mock_device_floodlight_camera.id, "init" })
  test.socket.matter:__expect_send({ mock_device_floodlight_camera.id, create_subscription(mock_device_floodlight_camera) })
  test.socket.matter:__expect_send({ mock_device_floodlight_camera.id, clusters.LevelControl.attributes.Options:write(mock_device_floodlight_camera, FLOODLIGHT_EP_ID, clusters.LevelControl.types.OptionsBitmap.EXECUTE_IF_OFF) })
  test.socket.device_lifecycle:__queue_receive({ mock_device_floodlight_camera.id, "doConfigure" })
  mock_device_floodlight_camera:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end


test.register_coroutine_test(
  "Child Floodlight device should be created when OnOff cluster is present on a separate endpoint",
  function()
    test.mock_device.add_test_device(mock_floodlight_child)
    test.socket.matter:__queue_receive({
      mock_device_floodlight_camera.id,
      clusters.CameraAvStreamManagement.attributes.AttributeList:build_test_report_data(mock_device_floodlight_camera, CAMERA_EP_ID, {uint32(0)})
    })
    mock_device_floodlight_camera:expect_device_create({
      type = "EDGE_CHILD",
      label = "Floodlight 1",
      profile = "light-level",
      parent_device_id = mock_device_floodlight_camera.id,
      parent_assigned_child_key = string.format("%d", FLOODLIGHT_EP_ID)
    })
    mock_device_floodlight_camera:expect_metadata_update(expected_metadata)
    test.wait_for_events()
    mock_initial_camera_update(mock_device_floodlight_camera, expected_metadata.optional_component_capabilities, create_subscription(mock_device_floodlight_camera, true, false, true))
  end,
  {
    test_init = test_init_floodlight_camera
  },
  {
     min_api_version = 17
  }
)


test.run_registered_tests()
