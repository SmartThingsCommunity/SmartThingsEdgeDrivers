-- SinuxSoft (c) 2025
-- Licensed under the Apache License, Version 2.0

local MatterDriver = require "st.matter.driver"
local log = require "log"

local function bridge_init(driver, device)
  device:subscribe()
end

local matter_driver = MatterDriver("britzyhub-matter", {
  lifecycle_handlers = {
    init = bridge_init,
  },
  sub_drivers = {
    require ("elevator"),
    require ("gas-valve"),
    require ("vent"),
  }
})

log.info_with({hub_logs=true}, string.format("Starting %s driver, with dispatcher: %s", matter_driver.NAME, matter_driver.matter_dispatcher))
matter_driver:run()