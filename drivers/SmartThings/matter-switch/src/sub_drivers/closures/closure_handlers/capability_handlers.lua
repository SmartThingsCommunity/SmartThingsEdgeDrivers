-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local closure_fields = require "sub_drivers.closures.closure_utils.fields"

clusters.ClosureControl = require "embedded_clusters.ClosureControl"

local ClosureCapabilityHandlers = {}

function ClosureCapabilityHandlers.handle_preset(driver, device, cmd)
  local lift_value = device:get_latest_state(
    "main", capabilities.windowShadePreset.ID, capabilities.windowShadePreset.position.NAME
  ) or closure_fields.DEFAULT_PRESET_LEVEL
  local hundredths_lift_percent = (100 - lift_value) * 100
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.WindowCovering.server.commands.GoToLiftPercentage(
    device, endpoint_id, hundredths_lift_percent
  ))
end

function ClosureCapabilityHandlers.handle_set_preset(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:set_field(closure_fields.PRESET_LEVEL_KEY, cmd.args.position)
  device:emit_event_for_endpoint(endpoint_id, capabilities.windowShadePreset.position(cmd.args.position))
end

function ClosureCapabilityHandlers.handle_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req
  if #device:get_endpoints(clusters.WindowCovering.ID) > 0 then
    req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
    if device:get_field(closure_fields.REVERSE_POLARITY) then
      req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
    end
  else -- ClosureControl cluster
    req = clusters.ClosureControl.server.commands.MoveTo(device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED)
    if device:get_field(closure_fields.REVERSE_POLARITY) then
      req = clusters.ClosureControl.server.commands.MoveTo(device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN)
    end
  end
  device:send(req)
end

function ClosureCapabilityHandlers.handle_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req
  if #device:get_endpoints(clusters.WindowCovering.ID) > 0 then
    req = clusters.WindowCovering.server.commands.UpOrOpen(device, endpoint_id)
    if device:get_field(closure_fields.REVERSE_POLARITY) then
      req = clusters.WindowCovering.server.commands.DownOrClose(device, endpoint_id)
    end
  else -- ClosureControl cluster
    req = clusters.ClosureControl.server.commands.MoveTo(device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN)
    if device:get_field(closure_fields.REVERSE_POLARITY) then
      req = clusters.ClosureControl.server.commands.MoveTo(device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED)
    end
  end
  device:send(req)
end

function ClosureCapabilityHandlers.handle_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local req = clusters.WindowCovering.server.commands.StopMotion(device, endpoint_id)
  if #device:get_endpoints(clusters.ClosureControl.ID) > 0 then
    req = clusters.ClosureControl.server.commands.Stop(device, endpoint_id)
  end
  device:send(req)
end

function ClosureCapabilityHandlers.handle_shade_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local lift_percentage_value = 100 - cmd.args.shadeLevel
  local hundredths_lift_percentage = lift_percentage_value * 100
  local req = clusters.WindowCovering.server.commands.GoToLiftPercentage(
    device, endpoint_id, hundredths_lift_percentage
  )
  device:send(req)
end

function ClosureCapabilityHandlers.handle_shade_tilt_level(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local tilt_percentage_value = 100 - cmd.args.level
  local hundredths_tilt_percentage = tilt_percentage_value * 100
  local req = clusters.WindowCovering.server.commands.GoToTiltPercentage(
    device, endpoint_id, hundredths_tilt_percentage
  )
  device:send(req)
end

return ClosureCapabilityHandlers
