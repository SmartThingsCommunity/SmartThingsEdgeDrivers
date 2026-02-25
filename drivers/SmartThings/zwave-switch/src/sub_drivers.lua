
-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require "lazy_load_subdriver"

return {
    lazy_load_if_possible("eaton-accessory-dimmer"),
    lazy_load_if_possible("inovelli"),
    lazy_load_if_possible("dawon-smart-plug"),
    lazy_load_if_possible("inovelli-2-channel-smart-plug"),
    lazy_load_if_possible("zwave-dual-switch"),
    lazy_load_if_possible("eaton-anyplace-switch"),
    lazy_load_if_possible("fibaro-wall-plug-us"),
    lazy_load_if_possible("dawon-wall-smart-switch"),
    lazy_load_if_possible("zooz-power-strip"),
    lazy_load_if_possible("aeon-smart-strip"),
    lazy_load_if_possible("qubino-switches"),
    lazy_load_if_possible("fibaro-double-switch"),
    lazy_load_if_possible("fibaro-single-switch"),
    lazy_load_if_possible("eaton-5-scene-keypad"),
    lazy_load_if_possible("ecolink-switch"),
    lazy_load_if_possible("multi-metering-switch"),
    lazy_load_if_possible("zooz-zen-30-dimmer-relay"),
    lazy_load_if_possible("multichannel-device"),
    lazy_load_if_possible("aeotec-smart-switch"),
    lazy_load_if_possible("aeotec-heavy-duty"),
    lazy_load_if_possible("philio-dimmer-switch")
}
