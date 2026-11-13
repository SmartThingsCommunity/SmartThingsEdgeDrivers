-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local WindowCovering = (require "st.zigbee.zcl.clusters").WindowCovering
local shade_utils = require "window_shade_utils"
local log = require "log"

local confirmation = {}
local CHECK = "_zemismartPositionCheck"
local TRUST = "_zemismartTrustedPosition"
local MOTION = "_zemismartMotionContext"
local AUTO_RECOVERY = "_zemismartAutoRecovery"
local PARTIAL_GENERATION = "_zemismartPartialGeneration"
local PARTIAL_TIMER = "partial_open_timer"
-- Engineering consistency policy; these are not certification or travel-time limits.
local RESPONSE_SECONDS = 10
local SAMPLE_SEPARATION_SECONDS = 2
local SESSION_SECONDS = 30
local MAX_READS = 3
local PROGRESS_SILENCE_SECONDS = 30
local PARTIAL_SETTLE_SECONDS = 2

local function cancel_timer(device, timer)
  if timer then
    -- The callback may already be queued. Generation checks remain authoritative.
    pcall(device.thread.cancel_timer, device.thread, timer)
  end
end

function confirmation.cancel(device)
  local check = device:get_field(CHECK)
  device:set_field(CHECK, nil)
  if check then
    check.timer_token = nil
    check.total_token = nil
    cancel_timer(device, check.timer)
    cancel_timer(device, check.total_timer)
    check.timer = nil
    check.total_timer = nil
  end
end

local function cancel_partial(device)
  local timer = device:get_field(PARTIAL_TIMER)
  local generation = device:get_field(PARTIAL_GENERATION)
  if generation then generation.active = false end
  device:set_field(PARTIAL_GENERATION, nil)
  device:set_field(PARTIAL_TIMER, nil)
  cancel_timer(device, timer)
end

local function cancel_motion(device)
  local motion = device:get_field(MOTION)
  device:set_field(MOTION, nil)
  if motion then
    motion.lease = nil
    cancel_timer(device, motion.timer)
    motion.timer = nil
  end
end

local function untrust(device, reason)
  device:set_field(TRUST, nil)
  cancel_motion(device)
  cancel_partial(device)
  shade_utils.clear_step_target(device)
  if device:get_latest_state("main", "windowShade", "windowShade") ~= "unknown" then
    log.warn_with({ hub_logs = true }, "ZM25Z position is unconfirmed: " .. reason)
    device:emit_event(capabilities.windowShade.windowShade.unknown())
  end
end

function confirmation.position_is_known(device)
  return device:get_field(TRUST) ~= nil
end

function confirmation.command_failed(device)
  confirmation.cancel(device)
  untrust(device, "local motion command could not be sent")
end

local start_check
local function fail_check(device, reason)
  confirmation.cancel(device)
  untrust(device, reason)
end

local function publish_static(device, level)
  confirmation.cancel(device)
  cancel_partial(device)
  device:set_field(TRUST, { level = level })
  device:set_field(AUTO_RECOVERY, 1)
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  local shade = capabilities.windowShade.windowShade
  device:emit_event(level == 0 and shade.closed()
    or level == 100 and shade.open() or shade.partially_open())
end

start_check = function(driver, device, component, mode)
  if device:get_field(CHECK) then return end
  component = component or "main"
  local check = {
    component = component, endpoint = device:get_endpoint_for_component_id(component),
    mode = mode or "static", reads = 0, round = 0, observations = 0,
    seen_sequences = {}, deadline = os.time() + SESSION_SECONDS,
  }
  device:set_field(CHECK, check)
  local send_read
  local function schedule(delay, callback)
    local remaining = check.deadline - os.time()
    if remaining <= 0 then fail_check(device, "read consistency budget exhausted"); return end
    local token = {}
    check.timer_token = token
    check.timer = device.thread:call_with_delay(math.min(delay, remaining), function()
      if check.timer_token ~= token then return end
      if device:get_field(CHECK) ~= check then return end
      check.timer_token = nil
      check.timer = nil
      if os.time() >= check.deadline then
        fail_check(device, "read consistency budget exhausted")
      else
        callback()
      end
    end)
  end
  send_read = function()
    if check.reads >= MAX_READS then
      fail_check(device, "insufficient consistent read observations")
      return
    end
    local ok, err = pcall(function()
      device:send_to_component(component,
        WindowCovering.attributes.CurrentPositionLiftPercentage:read(device))
    end)
    if not ok then
      confirmation.cancel(device)
      untrust(device, "local position read could not be sent")
      error(err)
    end
    check.reads = check.reads + 1
    check.round = check.round + 1
    check.pending = true
    schedule(RESPONSE_SECONDS, function() check.pending = false; send_read() end)
  end
  check.next_read = function()
    check.timer_token = nil
    cancel_timer(device, check.timer)
    check.timer = nil
    schedule(SAMPLE_SEPARATION_SECONDS, send_read)
  end
  send_read()
  if device:get_field(CHECK) == check then
    local token = {}
    check.total_token = token
    check.total_timer = device.thread:call_with_delay(SESSION_SECONDS, function()
      if check.total_token ~= token then return end
      if device:get_field(CHECK) ~= check then return end
      check.total_timer = nil
      check.total_token = nil
      fail_check(device, "read consistency budget exhausted")
    end)
  end
end

function confirmation.start(driver, device, component)
  if device:get_field(CHECK) then return end -- Repeated triggers do not extend the budget.
  device:set_field(AUTO_RECOVERY, 1)
  start_check(driver, device, component, device:get_field(MOTION) and "motion" or "static")
end

local function passive_check(driver, device)
  if device:get_field(CHECK) then return end
  if (device:get_field(AUTO_RECOVERY) or 0) <= 0 then return end
  device:set_field(AUTO_RECOVERY, 0)
  start_check(driver, device, "main", "static")
end

local function end_motion(driver, device, reason)
  confirmation.cancel(device)
  untrust(device, reason)
  device:set_field(AUTO_RECOVERY, 0)
  start_check(driver, device, "main", "static")
end

local function renew_motion(driver, device, motion)
  cancel_timer(device, motion.timer)
  local lease = {}
  motion.lease = lease
  motion.timer = device.thread:call_with_delay(PROGRESS_SILENCE_SECONDS, function()
    if motion.lease ~= lease then return end
    if device:get_field(MOTION) ~= motion then return end
    motion.timer = nil
    end_motion(driver, device, "no new directional progress")
  end)
end

function confirmation.motion_sent(driver, device, target)
  local trusted = device:get_field(TRUST)
  if not trusted then return end
  local previous = device:get_field(MOTION)
  local check = device:get_field(CHECK)
  if check then
    check.mode = "motion"
    check.observations = 0
    check.value = nil
  end
  if previous then
    -- A new target is not evidence of progress; keep the original silence timer.
    previous.start = trusted.level
    previous.last = trusted.level
    previous.target = target
    return
  end
  local motion = {
    start = trusted.level, last = trusted.level, target = target,
  }
  device:set_field(MOTION, motion)
  renew_motion(driver, device, motion)
end

function confirmation.pause_sent(driver, device)
  local check = device:get_field(CHECK)
  if check and check.mode == "motion" then confirmation.cancel(device); check = nil end
  untrust(device, "stop requires a new static observation")
  if check then
    check.observations = 0
    check.value = nil
    check.pending = false
    check.next_read()
  end
  confirmation.start(driver, device, "main")
end

local function publish_progress(device, level, direction)
  cancel_partial(device)
  device:set_field(TRUST, { level = level })
  device:emit_event(capabilities.windowShadeLevel.shadeLevel(level))
  local shade = capabilities.windowShade.windowShade
  device:emit_event(direction > 0 and shade.opening() or shade.closing())
  local generation = { active = true }
  device:set_field(PARTIAL_GENERATION, generation)
  local timer = device.thread:call_with_delay(PARTIAL_SETTLE_SECONDS, function()
    if not generation.active then return end
    if device:get_field(PARTIAL_GENERATION) ~= generation then return end
    generation.active = false
    device:set_field(PARTIAL_GENERATION, nil)
    device:set_field(PARTIAL_TIMER, nil)
    if device:get_field(TRUST) then device:emit_event(shade.partially_open()) end
  end)
  device:set_field(PARTIAL_TIMER, timer)
end

function confirmation.position_handler(driver, device, value, zb_rx)
  local endpoint = zb_rx.address_header.src_endpoint.value
  if endpoint ~= device:get_endpoint_for_component_id("main") then return end
  local level = value.value
  local check = device:get_field(CHECK)
  if type(level) ~= "number" or level < 0 or level > 100 or level % 1 ~= 0 then
    if check and check.mode == "motion" then confirmation.cancel(device); check = nil end
    untrust(device, level == 0xFF and "device position unavailable" or "invalid position value")
    if check then check.observations = 0; check.value = nil end
    passive_check(driver, device)
    return
  end
  local is_read = zb_rx.body.zcl_header.cmd.value == 0x01
  local motion = device:get_field(MOTION)
  if motion and device:get_field(TRUST) then
    if level == motion.target then
      end_motion(driver, device, "target report requires static read confirmation")
      return
    end
    local direction = motion.target > motion.start and 1 or -1
    local in_range = direction > 0 and level >= motion.last and level < motion.target
      or direction < 0 and level <= motion.last and level > motion.target
    if not in_range then
      end_motion(driver, device, "position conflicts with the current motion")
      return
    end
    if is_read or level ~= motion.last then confirmation.cancel(device) end
    if level ~= motion.last then
      motion.last = level
      renew_motion(driver, device, motion)
      publish_progress(device, level, direction)
    end
    return
  end

  local trusted = device:get_field(TRUST)
  if not is_read then
    if trusted and level ~= trusted.level then untrust(device, "unsolicited conflicting position") end
    check = device:get_field(CHECK)
    if check and check.value ~= nil and check.value ~= level then
      check.observations = 0
      check.value = nil
    end
    if not device:get_field(TRUST) then passive_check(driver, device) end
    return -- Reports alone cannot establish or restore trust.
  end

  check = device:get_field(CHECK)
  if not check or check.mode ~= "static" or not check.pending then return end
  local sequence = zb_rx.body.zcl_header.seqno.value
  if check.seen_sequences[sequence] then return end
  check.seen_sequences[sequence] = true -- Session-local deduplication, never sequence ordering.
  check.pending = false
  check.timer_token = nil
  cancel_timer(device, check.timer)
  check.timer = nil
  if trusted and level ~= trusted.level then untrust(device, "read differs from the trusted position") end
  if check.value == level then check.observations = check.observations + 1
  else check.value = level; check.observations = 1 end
  if check.observations >= 2 then publish_static(device, level)
  else check.next_read() end
end

function confirmation.initialize(driver, device)
  confirmation.cancel(device)
  untrust(device, "startup requires read confirmation")
  device:set_field(AUTO_RECOVERY, 1)
  start_check(driver, device, "main", "static")
end

function confirmation.removed(driver, device)
  confirmation.cancel(device)
  device:set_field(TRUST, nil)
  device:set_field(AUTO_RECOVERY, 0)
  cancel_motion(device)
  cancel_partial(device)
  shade_utils.clear_step_target(device)
end

return confirmation
