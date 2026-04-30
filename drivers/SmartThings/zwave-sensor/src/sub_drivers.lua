-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local lazy_load_if_possible = require("lazy_load_subdriver")

return {
    lazy_load_if_possible("zooz-4-in-1-sensor"),
    lazy_load_if_possible("vision-motion-detector"),
    lazy_load_if_possible("fibaro-flood-sensor"),
    lazy_load_if_possible("aeotec-water-sensor"),
    lazy_load_if_possible("glentronics-water-leak-sensor"),
    lazy_load_if_possible("homeseer-multi-sensor"),
    lazy_load_if_possible("fibaro-door-window-sensor"),
    lazy_load_if_possible("sensative-strip"),
    lazy_load_if_possible("enerwave-motion-sensor"),
    lazy_load_if_possible("aeotec-multisensor"),
    lazy_load_if_possible("zwave-water-leak-sensor"),
    lazy_load_if_possible("everspring-motion-light-sensor"),
    lazy_load_if_possible("ezmultipli-multipurpose-sensor"),
    lazy_load_if_possible("fibaro-motion-sensor"),
    lazy_load_if_possible("v1-contact-event"),
    lazy_load_if_possible("timed-tamper-clear"),
    lazy_load_if_possible("wakeup-no-poll"),
    lazy_load_if_possible("firmware-version"),
    lazy_load_if_possible("apiv6_bugfix"),
}
