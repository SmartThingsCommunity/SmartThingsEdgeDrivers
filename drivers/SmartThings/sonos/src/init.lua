local api_version = require("version").api
local cosock = require "cosock"

if type(cosock.bus) == "nil" then
  local cosock_bus = require "cosock.bus"
  cosock.bus = cosock_bus
end

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

-- API Version 14 was the version that came out with 0.57.x
--
-- In API >= 14, the SSDP task will start when the driver receives the startup state.
-- To support older versions of hub core, we start the SSDP task before the run loop,
-- where we won't be using the startup state handling.
if api_version < 14 then
  driver:start_ssdp_event_task()
end

log.info("Starting Sonos run loop")
driver:run()
log.info("Exiting Sonos run loop")
