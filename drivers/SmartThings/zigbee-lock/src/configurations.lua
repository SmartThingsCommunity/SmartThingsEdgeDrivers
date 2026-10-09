-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"

local DoorLock = clusters.DoorLock

local devices = {
  LOCK_WITHOUT_CODES = {
    FINGERPRINTS = {
      { model = "E261-KR0B0Z0-HA" },
      { mfr = "Danalock", model = "V3-BTZB" }
    },
    CONFIGURATION = {
      {
        cluster = DoorLock.ID,
        attribute = DoorLock.attributes.LockState.ID,
        minimum_interval = 0,
        maximum_interval = 3600,
        data_type = DoorLock.attributes.LockState.base_type,
        reportable_change = 1
      }
    }
  }
}

local configurations = {}

configurations.get_device_configuration = function(zigbee_device)
  for _, device in pairs(devices) do
    for _, fingerprint in pairs(device.FINGERPRINTS) do
      if zigbee_device:get_manufacturer() == fingerprint.mfr and zigbee_device:get_model() == fingerprint.model then
        return device.CONFIGURATION
      end
    end
  end
  return nil
end

return configurations
