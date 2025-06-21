-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local MatterDriver = require "st.matter.driver"
local log = require "log"

local matter_driver = MatterDriver("britzyhub-matter", {
  sub_drivers = {
    --require ("air-conditioner"),
    require ("elevator"),
    require ("gas-valve"),
    require ("ventilator"),
  }
})

log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()