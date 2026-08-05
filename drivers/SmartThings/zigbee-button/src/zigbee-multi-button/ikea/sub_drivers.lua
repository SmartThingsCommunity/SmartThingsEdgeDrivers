-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_sub_driver = require "lazy_load_subdriver"

local sub_drivers = {
    lazy_load_sub_driver("zigbee-multi-button.ikea.TRADFRI_remote_control"),
    lazy_load_sub_driver("zigbee-multi-button.ikea.TRADFRI_on_off_switch"),
    lazy_load_sub_driver("zigbee-multi-button.ikea.TRADFRI_open_close_remote")
}

return sub_drivers
