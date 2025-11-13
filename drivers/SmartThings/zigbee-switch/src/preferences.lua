-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local clusters = require "st.zigbee.zcl.clusters"
local cluster_base = require "st.zigbee.cluster_base"
local data_types = require "st.zigbee.data_types"

local devices = {
  AQARA_LIGHT = {
    MATCHING_MATRIX = {
        { mfr = "LUMI", model = "lumi.light.acn004" },
        { mfr = "LUMI", model = "lumi.light.cwacn1" }
      },
    PARAMETERS = {
      ["stse.restorePowerState"] = function(device, value)
        return cluster_base.write_manufacturer_specific_attribute(device, 0xFCC0,
          0x0201, 0x115F, data_types.Boolean, value)
      end,
      ["stse.turnOffIndicatorLight"] = function(device, value)
        return cluster_base.write_manufacturer_specific_attribute(device, 0xFCC0,
          0x0203, 0x115F, data_types.Boolean, value)
      end,
      ["stse.lightFadeInTimeInSec"] = function(device, value)
        local raw_value = value * 10 -- value unit: 1sec, transition time unit: 100ms
        return clusters.Level.attributes.OnTransitionTime:write(device, raw_value)
      end,
      ["stse.lightFadeOutTimeInSec"] = function(device, value)
        local raw_value = value * 10 -- value unit: 1sec, transition time unit: 100ms
        return clusters.Level.attributes.OffTransitionTime:write(device, raw_value)
      end
    }
  },
  AQARA_LIGHT_BULB = {
    MATCHING_MATRIX = {{ mfr = "Aqara", model = "lumi.light.acn014" }},
    PARAMETERS = {
      ["stse.restorePowerState"] = function(device, value)
        return cluster_base.write_manufacturer_specific_attribute(device, 0xFCC0,
          0x0201, 0x115F, data_types.Boolean, value)
      end
    }
  }
}
local preferences = {}

preferences.update_preferences = function(driver, device, args)
  local prefs = preferences.get_device_parameters(device)
  if prefs ~= nil then
    for id, value in pairs(device.preferences) do
      if not (args and args.old_st_store and args.old_st_store.preferences) or (args.old_st_store.preferences[id] ~= value and prefs and prefs[id]) then
        local message = prefs[id](device, value)
        device:send(message)
      end
    end
  end
end

preferences.sync_preferences = function(driver, device)
  local prefs = preferences.get_device_parameters(device)
  if prefs ~= nil then
    for id, value in pairs(device.preferences) do
      if prefs and prefs[id] then
        local message = prefs[id](device, value)
        device:send(message)
      end
    end
  end
end

preferences.get_device_parameters = function(zigbee_device)
  local mfr   = zigbee_device:get_manufacturer()
  local model = zigbee_device:get_model()

  for _, device in pairs(devices) do
    for _, fp in ipairs(device.MATCHING_MATRIX) do
      if fp.mfr == mfr and fp.model == model then
        return device.PARAMETERS
      end
    end
  end

  return nil
end

return preferences
