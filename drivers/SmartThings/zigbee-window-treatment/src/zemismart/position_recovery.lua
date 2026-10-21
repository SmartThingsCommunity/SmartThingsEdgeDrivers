-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local WindowCovering = (require "st.zigbee.zcl.clusters").WindowCovering
local zcl_commands = require "st.zigbee.zcl.global_commands"
local recovery = {}
local PENDING_ZERO = "_zemismartPendingZero"
local PARTIAL_TIMER = "_zemismartPartial"
-- Bound the delay for a genuine remote close when the corrective read has no reply.
local ZERO_CHECK_SECONDS = 2

function recovery.cancel(device)
  local pending = device:get_field(PENDING_ZERO)
  device:set_field(PENDING_ZERO, nil)
  if pending then
    pending.active = false
    if pending.timer then pcall(device.thread.cancel_timer, device.thread, pending.timer) end
  end
end

local function cancel_partial_timer(device)
  local pending = device:get_field(PARTIAL_TIMER)
  device:set_field(PARTIAL_TIMER, nil)
  if pending then
    pending.active = false
    if pending.timer then pcall(device.thread.cancel_timer, device.thread, pending.timer) end
  end
end

local function publish_static(device, component, level)
  cancel_partial_timer(device)
  device:emit_component_event(component, capabilities.windowShadeLevel.shadeLevel(level))
  local shade = capabilities.windowShade.windowShade
  device:emit_component_event(component,
    level == 0 and shade.closed() or level == 100 and shade.open() or shade.partially_open())
end

local function position_handler(_, device, value, zb_rx)
  local component = { id = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value) }
  local level = value.value
  local previous = device:get_latest_state(component.id, "windowShadeLevel", "shadeLevel")
  if level == previous then return end
  cancel_partial_timer(device)
  if level == 0 or level == 100 then
    publish_static(device, component, level)
    return
  end
  -- Use the standard shade position-delta and two-second settling behavior.
  device:emit_component_event(component, capabilities.windowShadeLevel.shadeLevel(level))
  local shade = capabilities.windowShade.windowShade
  device:emit_component_event(component,
    level > (previous or 0) and shade.opening() or shade.closing())
  local pending = { active = true }
  device:set_field(PARTIAL_TIMER, pending)
  pending.timer = device.thread:call_with_delay(2, function()
    -- Timer cancellation cannot retract a callback already queued on the device thread.
    if not pending.active then return end
    pending.active = false
    device:set_field(PARTIAL_TIMER, nil)
    device:emit_component_event(component, shade.partially_open())
  end)
end

function recovery.removed(device)
  recovery.cancel(device)
  cancel_partial_timer(device)
end


function recovery.position_handler(driver, device, value, zb_rx)
  local component = { id = device:get_component_id_for_endpoint(zb_rx.address_header.src_endpoint.value) }
  local level = value.value
  local last_level = device:get_latest_state(component.id, "windowShadeLevel", "shadeLevel")
  local state = device:get_latest_state(component.id, "windowShade", "windowShade")
  local command_id = zb_rx.body.zcl_header.cmd.value
  local is_read = command_id == zcl_commands.ReadAttributeResponse.ID
  local pending = device:get_field(PENDING_ZERO)

  if level > 100 then
    recovery.cancel(device)
    cancel_partial_timer(device)
    device:emit_component_event(component, capabilities.windowShade.windowShade.unknown())
    return
  end

  if pending then
    -- Repeated zero reports neither extend the window nor send additional reads.
    if not is_read and level == 0 then return end
    recovery.cancel(device)
  elseif command_id == zcl_commands.ReportAttribute.ID and level == 0
      and last_level ~= nil and last_level > 0
      and state ~= "opening" and state ~= "closing" and state ~= "unknown" then
    -- This firmware can report zero at power restoration while the motor is stationary.
    -- Keep the previous state for one read; do not infer movement from the transient zero.
    pending = { active = true }
    device:set_field(PENDING_ZERO, pending)
    pending.timer = device.thread:call_with_delay(ZERO_CHECK_SECONDS, function()
      if not pending.active then return end
      if device:get_field(PENDING_ZERO) ~= pending then return end
      pending.active = false
      device:set_field(PENDING_ZERO, nil)
      -- Without a correction, retain the actual report (including a real remote close).
      position_handler(driver, device, value, zb_rx)
    end)
    device:send_to_component(component.id,
      WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
    return
  end

  if state == "unknown" or (is_read and last_level == nil) then
    -- One valid static value restores Unknown, including an unchanged cached level.
    publish_static(device, component, level)
  else
    -- A changed nonzero correction still uses the original level to infer direction.
    position_handler(driver, device, value, zb_rx)
  end
end

return recovery
