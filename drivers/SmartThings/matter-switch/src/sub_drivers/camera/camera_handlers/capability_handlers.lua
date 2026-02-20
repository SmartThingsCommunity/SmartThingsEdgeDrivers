-- Copyright © 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local camera_fields = require "sub_drivers.camera.camera_utils.fields"
local camera_utils = require "sub_drivers.camera.camera_utils.utils"
local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local utils = require "st.utils"

local CameraCapabilityHandlers = {}

CameraCapabilityHandlers.set_enabled_factory = function(attribute)
  return function(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    device:send(attribute:write(device, endpoint_id, cmd.args.state == "enabled"))
  end
end

CameraCapabilityHandlers.set_night_vision_factory = function(attribute)
  return function(driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    for i, v in pairs(camera_fields.tri_state_map) do
      if v == cmd.args.mode then
        device:send(attribute:write(device, endpoint_id, i))
        return
      end
    end
    device.log.warn(string.format("Capability command sent with unknown value: (%s)", cmd.args.mode))
  end
end

function CameraCapabilityHandlers.handle_set_image_rotation(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local degrees = utils.clamp_value(cmd.args.rotation, 0, 359)
  device:send(clusters.CameraAvStreamManagement.attributes.ImageRotation:write(device, endpoint_id, degrees))
end

CameraCapabilityHandlers.handle_mute_commands_factory = function(command)
  return function(driver, device, cmd)
    local attr
    if cmd.component == camera_fields.profile_components.speaker then
      attr = clusters.CameraAvStreamManagement.attributes.SpeakerMuted
    elseif cmd.component == camera_fields.profile_components.microphone then
      attr = clusters.CameraAvStreamManagement.attributes.MicrophoneMuted
    else
      device.log.warn(string.format("Capability command sent from unknown component: (%s)", cmd.component))
      return
    end
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

function CameraCapabilityHandlers.handle_set_volume(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local max_volume = device:get_field(camera_fields.MAX_VOLUME_LEVEL .. "_" .. cmd.component) or camera_fields.ABS_VOL_MAX
  local min_volume = device:get_field(camera_fields.MIN_VOLUME_LEVEL .. "_" .. cmd.component) or camera_fields.ABS_VOL_MIN
  -- Convert from [0, 100] to [min_volume, max_volume] before writing attribute
  local volume_range = max_volume - min_volume
  local volume = utils.round(cmd.args.volume * volume_range / 100.0 + min_volume)
  if cmd.component == camera_fields.profile_components.speaker then
    device:send(clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(device, endpoint_id, volume))
  elseif cmd.component == camera_fields.profile_components.microphone then
    device:send(clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(device, endpoint_id, volume))
  else
    device.log.warn(string.format("Capability command sent from unknown component: (%s)", cmd.component))
  end
end

function CameraCapabilityHandlers.handle_volume_up(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local max_volume = device:get_field(camera_fields.MAX_VOLUME_LEVEL .. "_" .. cmd.component) or camera_fields.ABS_VOL_MAX
  local min_volume = device:get_field(camera_fields.MIN_VOLUME_LEVEL .. "_" .. cmd.component) or camera_fields.ABS_VOL_MIN
  local volume = device:get_latest_state(cmd.component, capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME)
  if not volume or volume >= max_volume then return end
  -- Convert from [0, 100] to [min_volume, max_volume] before writing attribute
  local volume_range = max_volume - min_volume
  local converted_volume = utils.round((volume + 1) * volume_range / 100.0 + min_volume)
  if cmd.component == camera_fields.profile_components.speaker then
    device:send(clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(device, endpoint_id, converted_volume))
  elseif cmd.component == camera_fields.profile_components.microphone then
    device:send(clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(device, endpoint_id, converted_volume))
  end
end

function CameraCapabilityHandlers.handle_volume_down(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local max_volume = device:get_field(camera_fields.MAX_VOLUME_LEVEL .. "_" .. cmd.component) or camera_fields.ABS_VOL_MAX
  local min_volume = device:get_field(camera_fields.MIN_VOLUME_LEVEL .. "_" .. cmd.component) or camera_fields.ABS_VOL_MIN
  local volume = device:get_latest_state(cmd.component, capabilities.audioVolume.ID, capabilities.audioVolume.volume.NAME)
  if not volume or volume <= min_volume then return end
  -- Convert from [0, 100] to [min_volume, max_volume] before writing attribute
  local volume_range = max_volume - min_volume
  local converted_volume = utils.round((volume - 1) * volume_range / 100.0 + min_volume)
  if cmd.component == camera_fields.profile_components.speaker then
    device:send(clusters.CameraAvStreamManagement.attributes.SpeakerVolumeLevel:write(device, endpoint_id, converted_volume))
  elseif cmd.component == camera_fields.profile_components.microphone then
    device:send(clusters.CameraAvStreamManagement.attributes.MicrophoneVolumeLevel:write(device, endpoint_id, converted_volume))
  end
end

function CameraCapabilityHandlers.handle_set_status_light_mode(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local level_auto_value
  if cmd.args.mode == "low" then level_auto_value = "LOW"
  elseif cmd.args.mode == "medium" then level_auto_value = "MEDIUM"
  elseif cmd.args.mode == "high" then level_auto_value = "HIGH"
  elseif cmd.args.mode == "auto" then level_auto_value = "AUTO" end
  if not level_auto_value then
    device.log.warn(string.format("Invalid mode received from setMode command: %s", cmd.args.mode))
    return
  end
  device:send(clusters.CameraAvStreamManagement.attributes.StatusLightBrightness:write(device, endpoint_id,
    clusters.Global.types.ThreeLevelAutoEnum[level_auto_value]))
end

function CameraCapabilityHandlers.handle_status_led_on(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(device, endpoint_id, true))
end

function CameraCapabilityHandlers.handle_status_led_off(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvStreamManagement.attributes.StatusLightEnabled:write(device, endpoint_id, false))
end

function CameraCapabilityHandlers.handle_audio_recording(driver, device, cmd)
  -- TODO: Allocate audio stream if it doesn't exist
  local component = device.profile.components[cmd.component]
  device:emit_component_event(component, capabilities.audioRecording.audioRecording(cmd.args.state))
end

CameraCapabilityHandlers.ptz_relative_move_factory = function(index)
  return function (driver, device, cmd)
    local endpoint_id = device:component_to_endpoint(cmd.component)
    local pan_delta = index == camera_fields.PAN_IDX and cmd.args.delta or 0
    local tilt_delta = index == camera_fields.TILT_IDX and cmd.args.delta or 0
    local zoom_delta = index == camera_fields.ZOOM_IDX and cmd.args.delta or 0
    device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRelativeMove(
      device, endpoint_id, pan_delta, tilt_delta, zoom_delta
    ))
  end
end

CameraCapabilityHandlers.ptz_set_position_factory = function(command)
  return function (driver, device, cmd)
    local ptz_map = camera_utils.get_ptz_map(device)
    if command == capabilities.mechanicalPanTiltZoom.commands.setPanTiltZoom then
      ptz_map[camera_fields.PAN_IDX].current = cmd.args.pan
      ptz_map[camera_fields.TILT_IDX].current = cmd.args.tilt
      ptz_map[camera_fields.ZOOM_IDX].current = cmd.args.zoom
    elseif command == capabilities.mechanicalPanTiltZoom.commands.setPan then
      ptz_map[camera_fields.PAN_IDX].current = cmd.args.pan
    elseif command == capabilities.mechanicalPanTiltZoom.commands.setTilt then
      ptz_map[camera_fields.TILT_IDX].current = cmd.args.tilt
    else
      ptz_map[camera_fields.ZOOM_IDX].current = cmd.args.zoom
    end
    for _, v in pairs(ptz_map) do
      v.current = utils.clamp_value(v.current, v.range.minimum, v.range.maximum)
    end
    local endpoint_id = device:component_to_endpoint(cmd.component)
    device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSetPosition(device, endpoint_id,
      ptz_map[camera_fields.PAN_IDX].current, ptz_map[camera_fields.TILT_IDX].current, ptz_map[camera_fields.ZOOM_IDX].current
    ))
  end
end

function CameraCapabilityHandlers.handle_save_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZSavePreset(
    device, endpoint_id, cmd.args.id, cmd.args.label
  ))
end

function CameraCapabilityHandlers.handle_remove_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZRemovePreset(device, endpoint_id, cmd.args.id))
end

function CameraCapabilityHandlers.handle_move_to_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.MPTZMoveToPreset(device, endpoint_id, cmd.args.id))
end

function CameraCapabilityHandlers.handle_new_zone(driver, device, cmd)
  local zone_uses = {
    ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
    ["focus"] = camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.FOCUSZONES) and
      clusters.ZoneManagement.types.ZoneUseEnum.FOCUS or clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY,
    ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
  }
  local vertices = {}
  for _, v in pairs(cmd.args.polygonVertices or {}) do
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

function CameraCapabilityHandlers.handle_update_zone(driver, device, cmd)
  local zone_uses = {
    ["motion"] = clusters.ZoneManagement.types.ZoneUseEnum.MOTION,
    ["focus"] = camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.FOCUSZONES) and
      clusters.ZoneManagement.types.ZoneUseEnum.FOCUS or clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY,
    ["privacy"] = clusters.ZoneManagement.types.ZoneUseEnum.PRIVACY
  }
  if not cmd.args.name or not cmd.args.polygonVertices or not cmd.args.use or not cmd.args.color then
    local zones = device:get_latest_state(
      camera_fields.profile_components.main, capabilities.zoneManagement.ID, capabilities.zoneManagement.zones.NAME
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
  for _, v in pairs(cmd.args.polygonVertices or {}) do
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

function CameraCapabilityHandlers.handle_remove_zone(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ZoneManagement.server.commands.RemoveZone(device, endpoint_id, cmd.args.zoneId))
end

function CameraCapabilityHandlers.handle_create_or_update_trigger(driver, device, cmd)
  if not cmd.args.augmentationDuration or not cmd.args.maxDuration or not cmd.args.blindDuration or
    (camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) and
      not cmd.args.sensitivity) then
    local triggers = device:get_latest_state(
      camera_fields.profile_components.main, capabilities.zoneManagement.ID, capabilities.zoneManagement.triggers.NAME
    ) or {}
    local found_trigger = false
    for _, v in pairs(triggers) do
      if v.zoneId == cmd.args.zoneId then
        if not cmd.args.augmentationDuration then cmd.args.augmentationDuration = v.augmentationDuration end
        if not cmd.args.maxDuration then cmd.args.maxDuration = v.maxDuration end
        if not cmd.args.blindDuration then cmd.args.blindDuration = v.blindDuration end
        if camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) and
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

function CameraCapabilityHandlers.handle_remove_trigger(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ZoneManagement.server.commands.RemoveTrigger(device, endpoint_id, cmd.args.zoneId))
end

function CameraCapabilityHandlers.handle_set_sensitivity(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  if not camera_utils.feature_supported(device, clusters.ZoneManagement.ID, clusters.ZoneManagement.types.Feature.PER_ZONE_SENSITIVITY) then
    device:send(clusters.ZoneManagement.attributes.Sensitivity:write(device, endpoint_id, cmd.args.id))
  else
    device.log.warn(string.format("Can't set global zone sensitivity setting, per zone sensitivity enabled."))
  end
end

function CameraCapabilityHandlers.handle_play_sound(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.Chime.server.commands.PlayChimeSound(device, endpoint_id))
end

function CameraCapabilityHandlers.handle_set_selected_sound(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.Chime.attributes.SelectedChime:write(device, endpoint_id, cmd.args.id))
end

function CameraCapabilityHandlers.handle_set_stream(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)

  local watermark_enabled, on_screen_display_enabled
  if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID,
    clusters.CameraAvStreamManagement.types.Feature.WATERMARK) then
    if cmd.args.watermark ~= nil then
      watermark_enabled = cmd.args.watermark == "enabled"
    end
  end
  if camera_utils.feature_supported(device, clusters.CameraAvStreamManagement.ID,
    clusters.CameraAvStreamManagement.types.Feature.ON_SCREEN_DISPLAY) then
    if cmd.args.onScreenDisplay ~= nil then
      on_screen_display_enabled = cmd.args.onScreenDisplay == "enabled"
    end
  end

  local current_streams = device:get_latest_state("main", capabilities.videoStreamSettings.ID,
    capabilities.videoStreamSettings.videoStreams.NAME)
  local current_stream
  for _, stream in ipairs(current_streams or {}) do
    if stream.streamId == cmd.args.streamId then
      current_stream = stream.data
      break
    end
  end

  local needs_reallocation = false
  if cmd.args.type ~= nil and current_stream ~= nil and current_stream.type ~= cmd.args.type then
    needs_reallocation = true
  elseif cmd.args.resolution ~= nil and current_stream then
    if current_stream.resolution.width ~= cmd.args.resolution.width or
       current_stream.resolution.height ~= cmd.args.resolution.height or
       current_stream.resolution.fps ~= cmd.args.resolution.fps then
      needs_reallocation = true
    end
  elseif current_stream == nil and (cmd.args.type ~= nil or cmd.args.resolution ~= nil) then
    needs_reallocation = true
  end

  local viewport_changed = false
  if cmd.args.viewport ~= nil and
    camera_utils.feature_supported(device, clusters.CameraAvSettingsUserLevelManagement.ID,
      clusters.CameraAvSettingsUserLevelManagement.types.Feature.DIGITALPTZ) then
    if current_stream ~= nil and current_stream.viewport ~= nil then
      if current_stream.viewport.upperLeftVertex.x ~= cmd.args.viewport.upperLeftVertex.x or
        current_stream.viewport.upperLeftVertex.y ~= cmd.args.viewport.upperLeftVertex.y or
        current_stream.viewport.lowerRightVertex.x ~= cmd.args.viewport.lowerRightVertex.x or
        current_stream.viewport.lowerRightVertex.y ~= cmd.args.viewport.lowerRightVertex.y then
        viewport_changed = true
      end
    elseif current_stream == nil or current_stream.viewport == nil then
      viewport_changed = true
    end

    if viewport_changed then
      device:send(clusters.CameraAvSettingsUserLevelManagement.server.commands.DPTZSetViewport(device, endpoint_id,
        cmd.args.streamId,
        clusters.Global.types.ViewportStruct({
          x1 = cmd.args.viewport.upperLeftVertex.x,
          x2 = cmd.args.viewport.lowerRightVertex.x,
          y1 = cmd.args.viewport.upperLeftVertex.y,
          y2 = cmd.args.viewport.lowerRightVertex.y
        })
      ))
    end
  end

  local label_changed = cmd.args.label ~= nil and cmd.args.label ~= current_stream.label

  if needs_reallocation then
    local stream_params = {
      endpoint_id = endpoint_id,
      type = cmd.args.type,
      label = cmd.args.label,
      resolution = cmd.args.resolution,
      watermark_enabled = watermark_enabled,
      on_screen_display_enabled = on_screen_display_enabled
    }

    device:set_field(camera_fields.PENDING_STREAM_ALLOCATION, stream_params)

    device:send(clusters.CameraAvStreamManagement.server.commands.VideoStreamDeallocate(device, endpoint_id,
      cmd.args.streamId
    ))
  elseif viewport_changed or label_changed then
    local updated_streams = {}
    for _, stream in ipairs(current_streams or {}) do
      if stream.streamId == cmd.args.streamId then
        local updated_stream = {
          streamId = stream.streamId,
          data = {}
        }
        for i, v in pairs(stream.data) do
          updated_stream.data[i] = v
        end
        if cmd.args.label ~= nil then
          updated_stream.data.label = cmd.args.label
        end
        if cmd.args.viewport ~= nil then
          updated_stream.data.viewport = cmd.args.viewport
        end
        table.insert(updated_streams, updated_stream)
      else
        table.insert(updated_streams, stream)
      end
    end
    device:emit_event(capabilities.videoStreamSettings.videoStreams(updated_streams))
  else
    device:send(clusters.CameraAvStreamManagement.server.commands.VideoStreamModify(device, endpoint_id,
      cmd.args.streamId, watermark_enabled, on_screen_display_enabled
    ))
  end
end

function CameraCapabilityHandlers.handle_set_default_viewport(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.CameraAvStreamManagement.attributes.Viewport:write(
    device, endpoint_id, clusters.Global.types.ViewportStruct({
      x1 = cmd.args.upperLeftVertex.x,
      x2 = cmd.args.lowerRightVertex.x,
      y1 = cmd.args.upperLeftVertex.y,
      y2 = cmd.args.lowerRightVertex.y
    })
  ))
end

return CameraCapabilityHandlers
