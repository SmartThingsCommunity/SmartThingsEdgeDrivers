-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.matter.clusters"
local version = require "version"

if version.api < 20 then
  clusters.ClosureControl = require "embedded_clusters.ClosureControl"
  clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"
end

local fields = require "sub_drivers.closure.closure_utils.fields"
local closure_utils = require "sub_drivers.closure.closure_utils.utils"

local ClosureCapabilityHandlers = {}

-- close covering (or door/gate)
function ClosureCapabilityHandlers.handle_close(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local reverse = device:get_field(fields.REVERSE_POLARITY)
  local req = reverse and
    clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN
    ) or
    clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED
    )
  device:send(req)
end

-- open covering (or door/gate)
function ClosureCapabilityHandlers.handle_open(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  local reverse = device:get_field(fields.REVERSE_POLARITY)
  local req = reverse and
    clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED
    ) or
    clusters.ClosureControl.server.commands.MoveTo(
      device, endpoint_id, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN
    )
  device:send(req)
end

-- pause / stop covering
function ClosureCapabilityHandlers.handle_pause(driver, device, cmd)
  local endpoint_id = device:component_to_endpoint(cmd.component)
  device:send(clusters.ClosureControl.server.commands.Stop(device, endpoint_id))
end

-- move to shade level 0-100 for covering Closure devices
function ClosureCapabilityHandlers.handle_shade_level(driver, device, cmd)
  local dim_eps = closure_utils.get_closure_dimension_eps(device)
  local endpoint_id = #dim_eps == 1 and dim_eps[1] or device:component_to_endpoint(cmd.component)
  if endpoint_id then
    device:send(clusters.ClosureDimension.server.commands.SetTarget(
      device, endpoint_id, cmd.args.shadeLevel * 100
    ))
  end
end

-- move to level 0-100 for door/gate/garage-door Closure devices
function ClosureCapabilityHandlers.handle_level(driver, device, cmd)
  local dim_eps = closure_utils.get_closure_dimension_eps(device)
  local endpoint_id = #dim_eps == 1 and dim_eps[1] or device:component_to_endpoint(cmd.component)
  device:send(clusters.ClosureDimension.server.commands.SetTarget(
    device, endpoint_id, cmd.args.level * 100
  ))
end

return ClosureCapabilityHandlers
