-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local camera_fields = require "sub_drivers.camera.utils.fields"
local camera_utils = require "sub_drivers.camera.utils.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local camera_cfg = require "sub_drivers.camera.utils.device_configuration"
local fields = require "switch_utils.fields"
local utils = require "st.utils"

local CameraAttributeHandlers = {}

CameraAttributeHandlers.enabled_state_factory = function(attribute)
  return function(driver, device, ib, response)
    device:emit_event_for_endpoint(ib, attribute(ib.data.value and "enabled" or "disabled"))
    if attribute == capabilities.imageControl.imageFlipHorizontal then
      camera_utils.update_supported_attributes(device, ib, capabilities.imageControl, "imageFlipHorizontal")
    elseif attribute == capabilities.imageControl.imageFlipVertical then
      camera_utils.update_supported_attributes(device, ib, capabilities.imageControl, "imageFlipVertical")
    elseif attribute == capabilities.cameraPrivacyMode.hardPrivacyMode then
      camera_utils.update_supported_attributes(device, ib, capabilities.cameraPrivacyMode, "hardPrivacyMode")
    end
  end
end

CameraAttributeHandlers.night_vision_factory = function(attribute)
  return function(driver, device, ib, response)
    if camera_fields.tri_state_map[ib.data.value] then
      device:emit_event_for_endpoint(ib, attribute(camera_fields.tri_state_map[ib.data.value]))
      if attribute == capabilities.nightVision.illumination then
        local _ = device:get_latest_state(camera_fields.profile_components.main, capabilities.nightVision.ID, capabilities.nightVision.supportedAttributes.NAME) or
          device:emit_event_for_endpoint(ib, capabilities.nightVision.supportedAttributes({"illumination"}))
      end
    end
  end
end

function CameraAttributeHandlers.image_rotation_handler(driver, device, ib, response)
  local degrees = utils.clamp_value(ib.data.value, 0, 359)
  device:emit_event_for_endpoint(ib, capabilities.imageControl.imageRotation(degrees))
  camera_utils.update_supported_attributes(device, ib, capabilities.imageControl, "imageRotation")
end

function CameraAttributeHandlers.two_way_talk_support_handler(driver, device, ib, response)
  local two_way_talk_supported = ib.data.value == clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.HALF_DUPLEX or
    ib.data.value == clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.FULL_DUPLEX
  device:emit_event_for_endpoint(ib, capabilities.webrtc.talkback(two_way_talk_supported))
  if two_way_talk_supported then
    device:emit_event_for_endpoint(ib, capabilities.webrtc.talkbackDuplex(
      ib.data.value == clusters.CameraAvStreamManagement.types.TwoWayTalkSupportTypeEnum.HALF_DUPLEX and "halfDuplex" or "fullDuplex"
    ))
  end
end

function CameraAttributeHandlers.muted_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.audioMute.mute(ib.data.value and "muted" or "unmuted"))
end

function CameraAttributeHandlers.volume_level_handler(driver, device, ib, response)
  local component = device:endpoint_to_component(ib)
  local max_volume = device:get_field(camera_fields.MAX_VOLUME_LEVEL .. "_" .. component) or camera_fields.ABS_VOL_MAX
  local min_volume = device:get_field(camera_fields.MIN_VOLUME_LEVEL .. "_" .. component) or camera_fields.ABS_VOL_MIN
  -- Convert from [min_volume, max_volume] to [0, 100] before emitting capability
  local limited_range = max_volume - min_volume
  local normalized_volume = utils.round((ib.data.value - min_volume) * 100.0 / limited_range)
  device:emit_event_for_endpoint(ib, capabilities.audioVolume.volume(normalized_volume))
end

function CameraAttributeHandlers.max_volume_level_handler(driver, device, ib, response)
  local component = device:endpoint_to_component(ib)
  local max_volume = ib.data.value
  local min_volume = device:get_field(camera_fields.MIN_VOLUME_LEVEL .. "_" .. component)
  if max_volume > camera_fields.ABS_VOL_MAX or (min_volume and max_volume <= min_volume) then
    device.log.warn(string.format("Device reported invalid maximum (%d) %s volume level range value", ib.data.value, component))
    max_volume = camera_fields.ABS_VOL_MAX
  end
  device:set_field(camera_fields.MAX_VOLUME_LEVEL .. "_" .. component, max_volume)
end

function CameraAttributeHandlers.min_volume_level_handler(driver, device, ib, response)
  local component = device:endpoint_to_component(ib)
  local min_volume = ib.data.value
  local max_volume = device:get_field(camera_fields.MAX_VOLUME_LEVEL .. "_" .. component)
  if min_volume < camera_fields.ABS_VOL_MIN or (max_volume and min_volume >= max_volume) then
    device.log.warn(string.format("Device reported invalid minimum (%d) %s volume level range value", ib.data.value, component))
    min_volume = camera_fields.ABS_VOL_MIN
  end
  device:set_field(camera_fields.MIN_VOLUME_LEVEL .. "_" .. component, min_volume)
end

function CameraAttributeHandlers.status_light_enabled_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, ib.data.value and capabilities.switch.switch.on() or capabilities.switch.switch.off())
end

function CameraAttributeHandlers.status_light_brightness_handler(driver, device, ib, response)
  local component = device:endpoint_to_component(ib)
  local _ = device:get_latest_state(component, capabilities.mode.ID, capabilities.mode.supportedModes.NAME) or
    device:emit_event_for_endpoint(ib, capabilities.mode.supportedModes({"low", "medium", "high", "auto"}, {visibility = {displayed = false}}))
  local _ = device:get_latest_state(component, capabilities.mode.ID, capabilities.mode.supportedArguments.NAME) or
    device:emit_event_for_endpoint(ib, capabilities.mode.supportedArguments({"low", "medium", "high", "auto"}, {visibility = {displayed = false}}))
  local mode = "auto"
  if ib.data.value == clusters.Global.types.ThreeLevelAutoEnum.LOW then
    mode = "low"
  elseif ib.data.value == clusters.Global.types.ThreeLevelAutoEnum.MEDIUM then
    mode = "medium"
  elseif ib.data.value == clusters.Global.types.ThreeLevelAutoEnum.HIGH then
    mode = "high"
  end
  device:emit_event_for_endpoint(ib, capabilities.mode.mode(mode))
end

function CameraAttributeHandlers.rate_distortion_trade_off_points_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local resolutions = {}
  local max_encoded_pixel_rate = device:get_field(camera_fields.MAX_ENCODED_PIXEL_RATE)
  local max_fps = device:get_field(camera_fields.MAX_FRAMES_PER_SECOND)
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
      local fps = camera_utils.compute_fps(max_encoded_pixel_rate, width, height, max_fps)
      if fps > 0 then
        resolutions[#resolutions].fps = fps
      end
    end
  end
  if emit_capability then
    device:emit_event_for_endpoint(ib, capabilities.videoStreamSettings.supportedResolutions(resolutions))
  end
  device:set_field(camera_fields.SUPPORTED_RESOLUTIONS, resolutions)
end

function CameraAttributeHandlers.max_encoded_pixel_rate_handler(driver, device, ib, response)
  local resolutions = device:get_field(camera_fields.SUPPORTED_RESOLUTIONS)
  local max_fps = device:get_field(camera_fields.MAX_FRAMES_PER_SECOND)
  local emit_capability = resolutions ~= nil and max_fps ~= nil
  if emit_capability then
    for _, v in pairs(resolutions or {}) do
      local fps = camera_utils.compute_fps(ib.data.value, v.width, v.height, max_fps)
      if fps > 0 then
        v.fps = fps
      end
    end
    device:emit_event_for_endpoint(ib, capabilities.videoStreamSettings.supportedResolutions(resolutions))
  end
  device:set_field(camera_fields.MAX_ENCODED_PIXEL_RATE, ib.data.value)
end

function CameraAttributeHandlers.video_sensor_parameters_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local resolutions = device:get_field(camera_fields.SUPPORTED_RESOLUTIONS)
  local max_encoded_pixel_rate = device:get_field(camera_fields.MAX_ENCODED_PIXEL_RATE)
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
    if sensor_width and sensor_height then
      device:emit_event_for_endpoint(ib, capabilities.cameraViewportSettings.videoSensorParameters({
        width = sensor_width,
        height = sensor_height,
        maxFPS = max_fps
      }))
    end
    if emit_capability then
      for _, v in pairs(resolutions or {}) do
        local fps = camera_utils.compute_fps(max_encoded_pixel_rate, v.width, v.height, max_fps)
        if fps > 0 then
          v.fps = fps
        end
      end
      device:emit_event_for_endpoint(ib, capabilities.videoStreamSettings.supportedResolutions(resolutions))
    end
    device:set_field(camera_fields.MAX_FRAMES_PER_SECOND, max_fps)
  end
end

function CameraAttributeHandlers.min_viewport_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.cameraViewportSettings.minViewportResolution({
    width = ib.data.elements.width.value,
    height = ib.data.elements.height.value
  }))
end

function CameraAttributeHandlers.allocated_video_streams_handler(driver, device, ib, response)
  if not ib.data.elements then return end
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
    local viewport = device:get_field(camera_fields.VIEWPORT)
    if viewport then
      video_stream.data.viewport = viewport
    end
    if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.WATERMARK) then
      video_stream.data.watermark = stream.watermark_enabled.value and "enabled" or "disabled"
    end
    if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID, clusters.CameraAvStreamManagement.types.Feature.ON_SCREEN_DISPLAY) then
      video_stream.data.onScreenDisplay = stream.osd_enabled.value and "enabled" or "disabled"
    end
    table.insert(streams, video_stream)
  end
  if #streams > 0 then
    device:emit_event_for_endpoint(ib, capabilities.videoStreamSettings.videoStreams(streams))
  end
end

function CameraAttributeHandlers.viewport_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.cameraViewportSettings.defaultViewport({
    upperLeftVertex = { x = ib.data.elements.x1.value, y = ib.data.elements.y1.value },
    lowerRightVertex = { x = ib.data.elements.x2.value, y = ib.data.elements.y2.value },
  }))
end

function CameraAttributeHandlers.ptz_position_handler(driver, device, ib, response)
  local ptz_map = camera_utils.get_ptz_map(device)
  local emit_event = function(idx, value)
    if value ~= ptz_map[idx].current then
      device:emit_event_for_endpoint(ib, ptz_map[idx].attribute(
        utils.clamp_value(value, ptz_map[idx].range.minimum, ptz_map[idx].range.maximum)
      ))
    end
  end
  if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPAN) then
    emit_event(camera_fields.PAN_IDX, ib.data.elements.pan.value)
  end
  if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MTILT) then
    emit_event(camera_fields.TILT_IDX, ib.data.elements.tilt.value)
  end
  if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MZOOM) then
    emit_event(camera_fields.ZOOM_IDX, ib.data.elements.zoom.value)
  end
end

function CameraAttributeHandlers.ptz_presets_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local presets = {}
  for _, v in ipairs(ib.data.elements) do
    local preset = v.elements
    local pan, tilt, zoom = 0, 0, 1
    if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MPAN) then
      pan = preset.settings.elements.pan.value
    end
    if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MTILT) then
      tilt = preset.settings.elements.tilt.value
    end
    if camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID, clusters.CameraAvSettingsUserLevelManagement.types.Feature.MZOOM) then
      zoom = preset.settings.elements.zoom.value
    end
    table.insert(presets, { id = preset.preset_id.value, label = preset.name.value, pan = pan, tilt = tilt, zoom = zoom })
  end
  device:emit_event_for_endpoint(ib, capabilities.mechanicalPanTiltZoom.presets(presets))
end

function CameraAttributeHandlers.max_presets_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.mechanicalPanTiltZoom.maxPresets(ib.data.value))
end

function CameraAttributeHandlers.zoom_max_handler(driver, device, ib, response)
  if ib.data.value <= camera_fields.ABS_ZOOM_MAX then
    device:emit_event_for_endpoint(ib, capabilities.mechanicalPanTiltZoom.zoomRange({ value = { minimum = 1, maximum = ib.data.value } }))
  else
    device.log.warn(string.format("Device reported invalid maximum zoom (%d)", ib.data.value))
  end
end

CameraAttributeHandlers.pt_range_handler_factory = function(attribute, limit_field)
  return function(driver, device, ib, response)
    device:set_field(limit_field, ib.data.value)
    local field = string.find(limit_field, "PAN") and "PAN" or "TILT"
    local min = device:get_field(camera_fields.pt_range_fields[field].min)
    local max = device:get_field(camera_fields.pt_range_fields[field].max)
    if min ~= nil and max ~= nil then
      local abs_min = field == "PAN" and camera_fields.ABS_PAN_MIN or camera_fields.ABS_TILT_MIN
      local abs_max = field == "PAN" and camera_fields.ABS_PAN_MAX or camera_fields.ABS_TILT_MAX
      if min < max and min >= abs_min and max <= abs_max then
        device:emit_event_for_endpoint(ib, attribute({ value = { minimum = min, maximum = max } }))
        device:set_field(camera_fields.pt_range_fields[field].min, nil)
        device:set_field(camera_fields.pt_range_fields[field].max, nil)
      else
        device.log.warn(string.format("Device reported invalid minimum (%d) and maximum (%d) %s " ..
          "range values (should be between %d and %d)", min, max, string.lower(field), abs_min, abs_max))
      end
    end
  end
end

function CameraAttributeHandlers.max_zones_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.zoneManagement.maxZones(ib.data.value))
end

function CameraAttributeHandlers.zones_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local zones = {}
  for _, v in ipairs(ib.data.elements) do
    local zone = v.elements
    local zone_id = zone.zone_id.value
    local zone_type = zone.zone_type.value
    local zone_source = zone.zone_source.value
    local zone_vertices = {}
    if camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.TWO_DIMENSIONAL_CARTESIAN_ZONE) and
      zone_type == clusters.ZoneManagement.types.ZoneTypeEnum.TWODCART_ZONE then
      local zone_name = zone.two_d_cartesian_zone.elements.name.value
      local zone_use = zone.two_d_cartesian_zone.elements.use.value
      for _, vertex in pairs(zone.two_d_cartesian_zone.elements.vertices.elements or {}) do
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
  device:emit_event_for_endpoint(ib, capabilities.zoneManagement.zones({value = zones}))
end

function CameraAttributeHandlers.triggers_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local triggers = {}
  for _, v in ipairs(ib.data.elements) do
    local trigger = v.elements
    table.insert(triggers, {
      zoneId = trigger.zone_id.value,
      initialDuration = trigger.initial_duration.value,
      augmentationDuration = trigger.augmentation_duration.value,
      maxDuration = trigger.max_duration.value,
      blindDuration = trigger.blind_duration.value,
      sensitivity = camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) and trigger.sensitivity.value
    })
  end
  device:emit_event_for_endpoint(ib, capabilities.zoneManagement.triggers(triggers))
end

function CameraAttributeHandlers.sensitivity_max_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.zoneManagement.sensitivityRange({minimum = 1, maximum = ib.data.value},
    {visibility = {displayed = false}}))
end

function CameraAttributeHandlers.sensitivity_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.zoneManagement.sensitivity(ib.data.value, {visibility = {displayed = false}}))
end

function CameraAttributeHandlers.installed_chime_sounds_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local installed_chimes = {}
  for _, v in ipairs(ib.data.elements) do
    local chime = v.elements
    table.insert(installed_chimes, {id = chime.chime_id.value, label = chime.name.value})
  end
  device:emit_event_for_endpoint(ib, capabilities.sounds.supportedSounds(installed_chimes, {visibility = {displayed = false}}))
end

function CameraAttributeHandlers.selected_chime_handler(driver, device, ib, response)
  device:emit_event_for_endpoint(ib, capabilities.sounds.selectedSound(ib.data.value))
end

function CameraAttributeHandlers.camera_av_stream_management_attribute_list_handler(driver, device, ib, response)
  if not ib.data.elements then return end
  local status_light_enabled_present, status_light_brightness_present = false, false
  local attribute_ids = {}
  for _, attr in ipairs(ib.data.elements) do
    if attr.value == clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID then
      status_light_enabled_present = true
      table.insert(attribute_ids, clusters.CameraAvStreamManagement.attributes.StatusLightEnabled.ID)
    elseif attr.value == clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID then
      status_light_brightness_present = true
      table.insert(attribute_ids, clusters.CameraAvStreamManagement.attributes.StatusLightBrightness.ID)
    end
  end
  local component_map = device:get_field(fields.COMPONENT_TO_ENDPOINT_MAP) or {}
  component_map.statusLed = {
    endpoint_id = ib.endpoint_id,
    cluster_id = ib.cluster_id,
    attribute_ids = attribute_ids,
  }
  device:set_field(fields.COMPONENT_TO_ENDPOINT_MAP, component_map, {persist=true})
  camera_cfg.match_profile(device, status_light_enabled_present, status_light_brightness_present)
end

return CameraAttributeHandlers