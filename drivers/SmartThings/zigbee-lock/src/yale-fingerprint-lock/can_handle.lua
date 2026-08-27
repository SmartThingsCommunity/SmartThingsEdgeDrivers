-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local yale_fingerprint_lock_models = function(opts, driver, device)
  local consts = require "lock_utils.constants"
  local slga_migrated = device:get_field(consts.DRIVER_STATE.SLGA_MIGRATED) or false
  if not slga_migrated then return false end
  local FINGERPRINTS = require("yale-fingerprint-lock.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
      if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model then
          return true, require("yale-fingerprint-lock")
      end
  end
  return false
end

return yale_fingerprint_lock_models
