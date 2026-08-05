-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local is_zigbee_plant_link_humidity_sensor = function(opts, driver, device)
  local FINGERPRINTS = require("plant-link.fingerprints")
  for _, fingerprint in ipairs(FINGERPRINTS) do
    if device:get_manufacturer() == fingerprint.mfr and device:get_model() == fingerprint.model and device:supports_server_cluster(fingerprint.cluster_id) then
      return true, require("plant-link")
    end
  end

  return false
end

return is_zigbee_plant_link_humidity_sensor
