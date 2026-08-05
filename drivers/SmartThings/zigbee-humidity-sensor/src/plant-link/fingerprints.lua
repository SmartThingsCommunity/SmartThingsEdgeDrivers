-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local zcl_clusters = require "st.zigbee.zcl.clusters"
local PLANT_LINK_MANUFACTURER_SPECIFIC_CLUSTER = 0xFC08

local ZIGBEE_HUMIDITY_SENSOR_FINGERPRINTS = {
    { mfr = "", model = "", cluster_id = PLANT_LINK_MANUFACTURER_SPECIFIC_CLUSTER },
    { mfr = "", model = "", cluster_id = zcl_clusters.ElectricalMeasurement.ID }
}

return ZIGBEE_HUMIDITY_SENSOR_FINGERPRINTS
