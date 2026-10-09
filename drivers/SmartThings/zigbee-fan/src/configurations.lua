-- Copyright 2024 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"

local OnOff = clusters.OnOff
local Level = clusters.Level
local FanControl = clusters.FanControl

local devices = {
  ITM_FAN_LIGHT = {
    FINGERPRINTS = {
      { mfr = "Samsung Electronics", model = "SAMSUNG-ITM-Z-003" },
    },
    CONFIGURATION = {
      {
        cluster = OnOff.ID,
        attribute = OnOff.attributes.OnOff.ID,
        minimum_interval = 0,
        maximum_interval = 600,
        data_type = OnOff.attributes.OnOff.base_type
      },
      {
        cluster = Level.ID,
        attribute = Level.attributes.CurrentLevel.ID,
        minimum_interval = 1,
        maximum_interval = 600,
        data_type = Level.attributes.CurrentLevel.base_type,
        reportable_change = 1
      },
      {
        cluster = FanControl.ID,
        attribute = FanControl.attributes.FanMode.ID,
        minimum_interval = 1,
        maximum_interval = 600,
        data_type = FanControl.attributes.FanMode.base_type
      }
    }
  },
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
