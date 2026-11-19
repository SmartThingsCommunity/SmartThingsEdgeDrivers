-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local capabilities = require "st.capabilities"
local LockCluster = clusters.DoorLock
local LockCredentials = capabilities.lockCredentials
local LockUsers = capabilities.lockUsers

local YALE_FINGERPRINT_MAX_CODES = 0x1E

local handle_number_of_pin_users_supported = function(driver, device, value)
  device:emit_event(LockCredentials.pinUsersSupported(YALE_FINGERPRINT_MAX_CODES))
  device:emit_event(LockUsers.totalUsersSupported(YALE_FINGERPRINT_MAX_CODES))
end

local fixed_pin_capacity_driver = {
  NAME = "Yale Fixed PIN Capacity",
  zigbee_handlers = {
    attr = {
      [LockCluster.ID] = {
        [LockCluster.attributes.NumberOfPINUsersSupported.ID] = handle_number_of_pin_users_supported
      }
    }
  },
  can_handle = require("yale.use-fixed-pin-capacity.can_handle")
}

return fixed_pin_capacity_driver
