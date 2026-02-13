-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0
local version = require "version"

local lazy_load_if_possible = require "lazy_load_subdriver"

return {
    lazy_load_if_possible("non_zigbee_devices"),
    lazy_load_if_possible("hanssem"),
    lazy_load_if_possible("aqara"),
    lazy_load_if_possible("aqara-light"),
    lazy_load_if_possible("ezex"),
    lazy_load_if_possible("rexense"),
    lazy_load_if_possible("sinope"),
    lazy_load_if_possible("sinope-dimmer"),
    lazy_load_if_possible("zigbee-dimmer-power-energy"),
    lazy_load_if_possible("zigbee-metering-plug-power-consumption-report"),
    lazy_load_if_possible("jasco"),
    lazy_load_if_possible("multi-switch-no-master"),
    lazy_load_if_possible("zigbee-dual-metering-switch"),
    lazy_load_if_possible("rgb-bulb"),
    lazy_load_if_possible("zigbee-dimming-light"),
    lazy_load_if_possible("white-color-temp-bulb"),
    lazy_load_if_possible("rgbw-bulb"),
    (version.api < 16) and lazy_load_if_possible("zll-dimmer-bulb") or nil,
    lazy_load_if_possible("ikea-xy-color-bulb"),
    lazy_load_if_possible("zll-polling"),
    lazy_load_if_possible("zigbee-switch-power"),
    lazy_load_if_possible("ge-link-bulb"),
    lazy_load_if_possible("bad_on_off_data_type"),
    lazy_load_if_possible("robb"),
    lazy_load_if_possible("wallhero"),
    lazy_load_if_possible("inovelli"), -- Combined driver for both VZM31-SN and VZM32-SN
    lazy_load_if_possible("laisiao"),
    lazy_load_if_possible("tuya-multi"),
    lazy_load_if_possible("frient"),
    lazy_load_if_possible("frient-IO")
}
