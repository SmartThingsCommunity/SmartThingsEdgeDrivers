-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

-- DEBUG ONLY, do not merge: on refresh, reads PIN slot 0 (the Zigbee master code slot) on
-- Yale locks and logs what the lock reports for it, to see whether a master code is set.

local clusters    = require "st.zigbee.zcl.clusters"
local LockCluster = clusters.DoorLock

local YALE_MANUFACTURERS = { ["Yale"] = true, ["ASSA ABLOY iRevo"] = true }
local MASTER_CODE_SLOT = 0
local READ_PENDING = "debugMasterCodeReadPending"

local debug_master_code = {}

function debug_master_code.read(device)
  if not YALE_MANUFACTURERS[device:get_manufacturer()] then return end
  device:set_field(READ_PENDING, true)
  -- the lock only includes the PIN in GetPINCodeResponse when this is set
  device:send(LockCluster.attributes.SendPINOverTheAir:write(device, true))
  device:send(LockCluster.server.commands.GetPINCode(device, MASTER_CODE_SLOT))
end

-- Logs the response to debug_master_code.read. Returns true if the caller should not process
-- the response further, which is the case unless a code scan is also checking slot 0.
function debug_master_code.handle_response(device, zb_rx, scanning_slot)
  local body = zb_rx.body.zcl_body
  if not device:get_field(READ_PENDING) or body.user_id.value ~= MASTER_CODE_SLOT then
    return false
  end
  device:set_field(READ_PENDING, nil)
  device.log.info(string.format("debug master code: slot 0 %s, %s, code=%q",
    tostring(body.user_status), tostring(body.user_type), tostring(body.code.value)))
  return scanning_slot ~= MASTER_CODE_SLOT
end

return debug_master_code
