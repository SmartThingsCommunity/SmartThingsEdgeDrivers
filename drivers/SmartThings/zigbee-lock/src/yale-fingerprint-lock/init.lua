-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local LockCluster = clusters.DoorLock
local LockCodes = capabilities.lockCodes

local YALE_FINGERPRINT_MAX_CODES = 0x1E



local handle_max_codes = function(driver, device, value)
  device:emit_event(LockCodes.maxCodes(YALE_FINGERPRINT_MAX_CODES), { visibility = { displayed = false } })
end

local yale_fingerprint_lock_driver = {
  NAME = "YALE Fingerprint Lock",
  zigbee_handlers = {
    attr = {
      [LockCluster.ID] = {
        [LockCluster.attributes.NumberOfPINUsersSupported.ID] = handle_max_codes
      }
    }
  },
  can_handle = require("yale-fingerprint-lock.can_handle"),
}

return yale_fingerprint_lock_driver
