-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-------------------------------------------------------------------------------------
-- Matter Camera Sub Driver
-------------------------------------------------------------------------------------

local attribute_handlers = require "sub_drivers.camera.camera_handlers.attribute_handlers"
local button_cfg = require("switch_utils.device_configuration").ButtonCfg
local camera_cfg = require "sub_drivers.camera.camera_utils.device_configuration"
local camera_fields = require "sub_drivers.camera.camera_utils.fields"
local camera_utils = require "sub_drivers.camera.camera_utils.utils"
local capabilities = require "st.capabilities"
local capability_handlers = require "sub_drivers.camera.camera_handlers.capability_handlers"
local clusters = require "st.matter.clusters"
local event_handlers = require "sub_drivers.camera.camera_handlers.event_handlers"
local fields = require "switch_utils.fields"
local switch_utils = require "switch_utils.utils"

local CameraLifecycleHandlers = {}

function CameraLifecycleHandlers.device_init(driver, device)
  device:set_component_to_endpoint_fn(camera_utils.component_to_endpoint)
  device:set_endpoint_to_component_fn(switch_utils.endpoint_to_component)
  device:extend_device("emit_event_for_endpoint", switch_utils.emit_event_for_endpoint)
  if device:get_field(fields.IS_PARENT_CHILD_DEVICE) then
    device:set_find_child(switch_utils.find_child)
  end
  device:extend_device("subscribe", camera_utils.subscribe)
  device:subscribe()
end

function CameraLifecycleHandlers.do_configure(driver, device)
  camera_utils.update_camera_component_map(device)
  if #device:get_endpoints(clusters.CameraAvStreamManagement.ID) == 0 then
    camera_cfg.match_profile(device, false, false)
  end
  camera_cfg.create_child_devices(driver, device)
  camera_cfg.initialize_camera_capabilities(device)
end

function CameraLifecycleHandlers.info_changed(driver, device, event, args)
  if camera_utils.profile_changed(device.profile.components, args.old_st_store.profile.components) then
    camera_cfg.initialize_camera_capabilities(device)
    if #switch_utils.get_endpoints_by_device_type(device, fields.DEVICE_TYPE_ID.DOORBELL) > 0 then
      button_cfg.configure_buttons(device)
    end
    device:subscribe()
  end
end

function CameraLifecycleHandlers.added() end

local camera_handler = {
  NAME = "Camera Handler",
  lifecycle_handlers = {
    init = CameraLifecycleHandlers.device_init,
    infoChanged = CameraLifecycleHandlers.info_changed,
    doConfigure = CameraLifecycleHandlers.do_configure,
    driverSwitched = CameraLifecycleHandlers.do_configure,
    added = CameraLifecycleHandlers.added
  },
  matter_handlers = {
    attr = {
      [clusters.CameraAvStreamManagement.ID] = {
        [clusters.CameraAvStreamManagement.attributes.HDRModeEnabled.ID] = attribute_handlers.enabled_state_factory(capabilities.hdr.hdr),
        [clusters.CameraAvStreamManagement.attributes.NightVision.ID] = attribute_handlers.night_vision_factory(capabilities.nightVision.nightVision),
        [clusters.CameraAvStreamManagement.attributes.NightVisionIllum.ID] = attribute_handlers.night_vision_factory(capabilities.nightVision.illumination),
        [clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal.ID] = attribute_handlers.enabled_state_factory(capabilities.imageControl.imageFlipHorizontal),
        [clusters.CameraAvStreamManagement.attributes.ImageFlipVertical.ID] = attribute_handlers.enabled_state_factory(capabilities.imageControl.imageFlipVertical),
        [clusters.CameraAvStreamManagement.attributes.ImageRotation.ID] = attribute_handlers.image_rotation_handler,
        [clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled.ID] = attribute_handlers.enabled_state_factory(capabilities.cameraPrivacyMode.softRecordingPrivacyMode),
        [clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled.ID] = attribute_handlers.enabled_state_factory(capabilities.cameraPrivacyMode.softLivestreamPrivacyMode),
        [clusters.CameraAvStreamManagement.attributes.HardPrivacyModeOn.ID] = attribute_handlers.enabled_state_factory(capabilities.cameraPrivacyMode.hardPrivacyMode),
        [clusters.CameraAvStreamManagement.attributes.TwoWayTalkSupport.ID] = attribute_handlers.two_way_talk_support_handler,
        [clusters.CameraAvStreamManagement.attributes.SpeakerMuted.ID] = attribute_handlers.muted_handler,
        [clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel.ID] = attribute_handlers.volume_level_handler,
        [clusters.CameraAvStreamManagement.attributes.SpeakerMaxLevel.ID] = attribute_handlers.max_volume_level_handler,
        [clusters.CameraAvStreamManagement.attributes.SpeakerMinLevel.ID] = attribute_handlers.min_volume_level_handler,
        [clusters.CameraAvStreamManagement.attributes.MicrophoneMuted.ID] = attribute_handlers.muted_handler,
        [clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel.ID] = attribute_handlers.volume_level_handler,
        [clusters.CameraAvStreamManagement.attributes.MicrophoneMaxLevel.ID] = attribute_handlers.max_volume_level_handler,
        [clusters.CameraAvStreamManagement.attributes.MicrophoneMinLevel.ID] = attribute_handlers.min_volume_level_handler,
        [clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID] = attribute_handlers.status_light_enabled_handler,
        [clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID] = attribute_handlers.status_light_brightness_handler,
        [clusters.CameraAvStreamManagement.attributes.RateDistortionTradeOffPoints.ID] = attribute_handlers.rate_distortion_trade_off_points_handler,
        [clusters.CameraAvStreamManagement.attributes.MaxEncodedPixelRate.ID] = attribute_handlers.max_encoded_pixel_rate_handler,
        [clusters.CameraAvStreamManagement.attributes.VideoSensorParams.ID] = attribute_handlers.video_sensor_parameters_handler,
        [clusters.CameraAvStreamManagement.attributes.MinViewportResolution.ID] = attribute_handlers.min_viewport_handler,
        [clusters.CameraAvStreamManagement.attributes.AllocatedVideoStreams.ID] = attribute_handlers.allocated_video_streams_handler,
        [clusters.CameraAvStreamManagement.attributes.Viewport.ID] = attribute_handlers.viewport_handler,
        [clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled.ID] = attribute_handlers.enabled_state_factory(capabilities.localMediaStorage.localSnapshotRecording),
        [clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled.ID] = attribute_handlers.enabled_state_factory(capabilities.localMediaStorage.localVideoRecording),
        [clusters.CameraAvStreamManagement.attributes.AttributeList.ID] = attribute_handlers.camera_av_stream_management_attribute_list_handler
      },
      [clusters.CameraAvSettingsUserLevelManagement.ID] = {
        [clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPosition.ID] = attribute_handlers.ptz_position_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.MPTZPresets.ID] = attribute_handlers.ptz_presets_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.MaxPresets.ID] = attribute_handlers.max_presets_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.ZoomMax.ID] = attribute_handlers.zoom_max_handler,
        [clusters.CameraAvSettingsUserLevelManagement.attributes.PanMax.ID] = attribute_handlers.pt_range_handler_factory(capabilities.mechanicalPanTiltZoom.panRange, camera_fields.pt_range_fields[camera_fields.PAN_IDX].max),
        [clusters.CameraAvSettingsUserLevelManagement.attributes.PanMin.ID] = attribute_handlers.pt_range_handler_factory(capabilities.mechanicalPanTiltZoom.panRange, camera_fields.pt_range_fields[camera_fields.PAN_IDX].min),
        [clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMax.ID] = attribute_handlers.pt_range_handler_factory(capabilities.mechanicalPanTiltZoom.tiltRange, camera_fields.pt_range_fields[camera_fields.TILT_IDX].max),
        [clusters.CameraAvSettingsUserLevelManagement.attributes.TiltMin.ID] = attribute_handlers.pt_range_handler_factory(capabilities.mechanicalPanTiltZoom.tiltRange, camera_fields.pt_range_fields[camera_fields.TILT_IDX].min)
      },
      [clusters.ZoneManagement.ID] = {
        [clusters.ZoneManagement.attributes.MaxZones.ID] = attribute_handlers.max_zones_handler,
        [clusters.ZoneManagement.attributes.Zones.ID] = attribute_handlers.zones_handler,
        [clusters.ZoneManagement.attributes.Triggers.ID] = attribute_handlers.triggers_handler,
        [clusters.ZoneManagement.attributes.SensitivityMax.ID] = attribute_handlers.sensitivity_max_handler,
        [clusters.ZoneManagement.attributes.Sensitivity.ID] = attribute_handlers.sensitivity_handler,
      },
      [clusters.Chime.ID] = {
        [clusters.Chime.attributes.InstalledChimeSounds.ID] = attribute_handlers.installed_chime_sounds_handler,
        [clusters.Chime.attributes.SelectedChime.ID] = attribute_handlers.selected_chime_handler
      }
    },
    event = {
      [clusters.ZoneManagement.ID] = {
        [clusters.ZoneManagement.events.ZoneTriggered.ID] = event_handlers.zone_triggered_handler,
        [clusters.ZoneManagement.events.ZoneStopped.ID] = event_handlers.zone_stopped_handler
      }
    }
  },
  capability_handlers = {
    [capabilities.hdr.ID] = {
      [capabilities.hdr.commands.setHdr.NAME] = capability_handlers.set_enabled_factory(clusters.CameraAvStreamManagement.attributes.HDRModeEnabled)
    },
    [capabilities.nightVision.ID] = {
      [capabilities.nightVision.commands.setNightVision.NAME] = capability_handlers.set_night_vision_factory(clusters.CameraAvStreamManagement.attributes.NightVision),
      [capabilities.nightVision.commands.setIllumination.NAME] = capability_handlers.set_night_vision_factory(clusters.CameraAvStreamManagement.attributes.NightVisionIllum)
    },
    [capabilities.imageControl.ID] = {
      [capabilities.imageControl.commands.setImageFlipHorizontal.NAME] = capability_handlers.set_enabled_factory(clusters.CameraAvStreamManagement.attributes.ImageFlipHorizontal),
      [capabilities.imageControl.commands.setImageFlipVertical.NAME] = capability_handlers.set_enabled_factory(clusters.CameraAvStreamManagement.attributes.ImageFlipVertical),
      [capabilities.imageControl.commands.setImageRotation.NAME] = capability_handlers.handle_set_image_rotation
    },
    [capabilities.cameraPrivacyMode.ID] = {
      [capabilities.cameraPrivacyMode.commands.setSoftLivestreamPrivacyMode.NAME] = capability_handlers.set_enabled_factory(clusters.CameraAvStreamManagement.attributes.SoftLivestreamPrivacyModeEnabled),
      [capabilities.cameraPrivacyMode.commands.setSoftRecordingPrivacyMode.NAME] = capability_handlers.set_enabled_factory(clusters.CameraAvStreamManagement.attributes.SoftRecordingPrivacyModeEnabled)
    },
    [capabilities.audioMute.ID] = {
      [capabilities.audioMute.commands.setMute.NAME] = capability_handlers.handle_mute_commands_factory(capabilities.audioMute.commands.setMute.NAME),
      [capabilities.audioMute.commands.mute.NAME] = capability_handlers.handle_mute_commands_factory(capabilities.audioMute.commands.mute.NAME),
      [capabilities.audioMute.commands.unmute.NAME] = capability_handlers.handle_mute_commands_factory(capabilities.audioMute.commands.unmute.NAME)
    },
    [capabilities.audioVolume.ID] = {
      [capabilities.audioVolume.commands.setVolume.NAME] = capability_handlers.handle_set_volume,
      [capabilities.audioVolume.commands.volumeUp.NAME] = capability_handlers.handle_volume_up,
      [capabilities.audioVolume.commands.volumeDown.NAME] = capability_handlers.handle_volume_down
    },
    [capabilities.mode.ID] = {
      [capabilities.mode.commands.setMode.NAME] = capability_handlers.handle_set_status_light_mode
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = capability_handlers.handle_status_led_on,
      [capabilities.switch.commands.off.NAME] = capability_handlers.handle_status_led_off
    },
    [capabilities.audioRecording.ID] = {
      [capabilities.audioRecording.commands.setAudioRecording.NAME] = capability_handlers.handle_audio_recording
    },
    [capabilities.mechanicalPanTiltZoom.ID] = {
      [capabilities.mechanicalPanTiltZoom.commands.panRelative.NAME] = capability_handlers.ptz_relative_move_factory(camera_fields.PAN_IDX),
      [capabilities.mechanicalPanTiltZoom.commands.tiltRelative.NAME] = capability_handlers.ptz_relative_move_factory(camera_fields.TILT_IDX),
      [capabilities.mechanicalPanTiltZoom.commands.zoomRelative.NAME] = capability_handlers.ptz_relative_move_factory(camera_fields.ZOOM_IDX),
      [capabilities.mechanicalPanTiltZoom.commands.setPan.NAME] = capability_handlers.ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setPan),
      [capabilities.mechanicalPanTiltZoom.commands.setTilt.NAME] = capability_handlers.ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setTilt),
      [capabilities.mechanicalPanTiltZoom.commands.setZoom.NAME] = capability_handlers.ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setZoom),
      [capabilities.mechanicalPanTiltZoom.commands.setPanTiltZoom.NAME] = capability_handlers.ptz_set_position_factory(capabilities.mechanicalPanTiltZoom.commands.setPanTiltZoom),
      [capabilities.mechanicalPanTiltZoom.commands.savePreset.NAME] = capability_handlers.handle_save_preset,
      [capabilities.mechanicalPanTiltZoom.commands.removePreset.NAME] = capability_handlers.handle_remove_preset,
      [capabilities.mechanicalPanTiltZoom.commands.moveToPreset.NAME] = capability_handlers.handle_move_to_preset
    },
    [capabilities.zoneManagement.ID] = {
      [capabilities.zoneManagement.commands.newZone.NAME] = capability_handlers.handle_new_zone,
      [capabilities.zoneManagement.commands.updateZone.NAME] = capability_handlers.handle_update_zone,
      [capabilities.zoneManagement.commands.removeZone.NAME] = capability_handlers.handle_remove_zone,
      [capabilities.zoneManagement.commands.createOrUpdateTrigger.NAME] = capability_handlers.handle_create_or_update_trigger,
      [capabilities.zoneManagement.commands.removeTrigger.NAME] = capability_handlers.handle_remove_trigger,
      [capabilities.zoneManagement.commands.setSensitivity.NAME] = capability_handlers.handle_set_sensitivity
    },
    [capabilities.sounds.ID] = {
      [capabilities.sounds.commands.playSound.NAME] = capability_handlers.handle_play_sound,
      [capabilities.sounds.commands.setSelectedSound.NAME] = capability_handlers.handle_set_selected_sound
    },
    [capabilities.videoStreamSettings.ID] = {
      [capabilities.videoStreamSettings.commands.setStream.NAME] = capability_handlers.handle_set_stream
    },
    [capabilities.cameraViewportSettings.ID] = {
      [capabilities.cameraViewportSettings.commands.setDefaultViewport.NAME] = capability_handlers.handle_set_default_viewport
    },
    [capabilities.localMediaStorage.ID] = {
      [capabilities.localMediaStorage.commands.setLocalSnapshotRecording.NAME] = capability_handlers.set_enabled_factory(clusters.CameraAvStreamManagement.attributes.LocalSnapshotRecordingEnabled),
      [capabilities.localMediaStorage.commands.setLocalVideoRecording.NAME] = capability_handlers.set_enabled_factory(clusters.CameraAvStreamManagement.attributes.LocalVideoRecordingEnabled)
    }
  },
  can_handle = require("sub_drivers.camera.can_handle")
}

return camera_handler
