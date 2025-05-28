---@module 'result'
require "result" {
  register_globals = true,
}

local Driver = require "st.driver"
local SonosDriver = require "sonos_driver"
local log = require "log"

local driver_template = SonosDriver.new_driver_template()

---@type SonosDriver
local driver = Driver("Sonos", driver_template)

-- Clean these up, as we no longer want them persisting.
if driver.datastore["_field_cache"] ~= nil then
  driver.datastore["_field_cache"] = nil
end

-- Clean these up, as we no longer want them persisting.
if driver.datastore["dni_to_device_id"] ~= nil then
  driver.datastore["dni_to_device_id"] = nil
end

log.info "Starting Sonos run loop"
driver:run()
log.info "Exiting Sonos run loop"
