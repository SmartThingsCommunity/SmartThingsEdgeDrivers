-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- DEBUG ONLY, do not merge: walks every User Code slot on a Yale lock and logs the slots
-- that are not empty, to find which slot holds the master code. Started by a refresh.
-- Reports consumed by the scan are not added to the lockUsers/lockCredentials tables.

--- @type st.zwave.CommandClass.UserCode
local UserCode   = (require "st.zwave.CommandClass.UserCode")({ version = 1 })
local lock_utils = require "lock_utils.utils"

local YALE_MFR = 0x0129
local FIRST_SLOT = 1
local LAST_SLOT = 255
local RESPONSE_TIMEOUT = 5 -- seconds to wait for a slot's report before moving on
local BUSY_RETRY_DELAY = 5 -- seconds to wait while another lock operation is in progress

local SCAN_INDEX = "debugScanCodeIndex"
local SCAN_TIMER = "debugScanCodeTimer"
local SCAN_FOUND = "debugScanCodesFound"
local SCAN_NO_RESPONSE = "debugScanCodesNoResponse"

local debug_code_scan = {}

local function cancel_timer(device)
  local timer = device:get_field(SCAN_TIMER)
  if timer then
    device.thread:cancel_timer(timer)
    device:set_field(SCAN_TIMER, nil)
  end
end

local function finish(device)
  local found = device:get_field(SCAN_FOUND) or {}
  local no_response = device:get_field(SCAN_NO_RESPONSE) or {}
  device.log.info(string.format("debug code scan: complete, %d non-empty slot(s): [%s]",
    #found, table.concat(found, ", ")))
  if #no_response > 0 then
    device.log.info(string.format("debug code scan: %d slot(s) did not respond: [%s]",
      #no_response, table.concat(no_response, ", ")))
  end
  device:set_field(SCAN_INDEX, nil)
  device:set_field(SCAN_FOUND, nil)
  device:set_field(SCAN_NO_RESPONSE, nil)
end

local request_slot

local function advance(device)
  cancel_timer(device)
  local next_slot = device:get_field(SCAN_INDEX) + 1
  if next_slot > LAST_SLOT then
    finish(device)
  else
    device:set_field(SCAN_INDEX, next_slot)
    request_slot(device)
  end
end

request_slot = function(device)
  local slot = device:get_field(SCAN_INDEX)
  if slot == nil then return end
  if lock_utils.is_device_busy(device) then
    -- another operation (e.g. the post-pairing sync) is using UserCode reports, so wait for it to finish
    device:set_field(SCAN_TIMER, device.thread:call_with_delay(BUSY_RETRY_DELAY, function()
      device:set_field(SCAN_TIMER, nil)
      request_slot(device)
    end))
    return
  end
  device:send(UserCode:Get({ user_identifier = slot }))
  device:set_field(SCAN_TIMER, device.thread:call_with_delay(RESPONSE_TIMEOUT, function()
    device:set_field(SCAN_TIMER, nil) -- this timer has fired, so there is nothing to cancel
    local no_response = device:get_field(SCAN_NO_RESPONSE) or {}
    table.insert(no_response, slot)
    device:set_field(SCAN_NO_RESPONSE, no_response)
    advance(device)
  end))
end

function debug_code_scan.start(device)
  if device.zwave_manufacturer_id ~= YALE_MFR or device:get_field(SCAN_INDEX) ~= nil then return end
  device.log.info(string.format("debug code scan: starting, slots %d-%d", FIRST_SLOT, LAST_SLOT))
  device:set_field(SCAN_INDEX, FIRST_SLOT)
  device:set_field(SCAN_FOUND, {})
  device:set_field(SCAN_NO_RESPONSE, {})
  request_slot(device)
end

-- Returns true if the report was for the slot currently being scanned and was consumed.
function debug_code_scan.handle_report(device, cmd)
  local slot = device:get_field(SCAN_INDEX)
  if slot == nil or cmd.args.user_identifier ~= slot or lock_utils.is_device_busy(device) then
    return false
  end
  local status = cmd.args.user_id_status
  if status ~= UserCode.user_id_status.AVAILABLE then
    device.log.info(string.format("debug code scan: slot %d status=%s code=%q",
      slot, UserCode._reflect_user_id_status[status] or tostring(status), tostring(cmd.args.user_code)))
    local found = device:get_field(SCAN_FOUND) or {}
    table.insert(found, slot)
    device:set_field(SCAN_FOUND, found)
  end
  advance(device)
  return true
end

return debug_code_scan
