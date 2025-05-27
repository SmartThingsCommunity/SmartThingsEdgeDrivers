local log = require "log"

local Driver = require "st.driver"
local SonosDriver = require "sonos_driver"

local driver_template = SonosDriver.new_driver_template()

--- @type SonosDriver
local driver = Driver("Sonos", driver_template)

-- Clean these up, as we no longer want them persisting.
if driver.datastore["_field_cache"] ~= nil then
  driver.datastore["_field_cache"] = nil
end

-- Clean these up, as we no longer want them persisting.
if driver.datastore["dni_to_device_id"] ~= nil then
  driver.datastore["dni_to_device_id"] = nil
end

-- Kick off a scan right away to attempt to populate some information
driver:call_with_delay(3, driver.scan_for_ssdp_updates, "Sonos SSDP Initial Scan")

-- re-scan every 10 minutes
local SSDP_SCAN_INTERVAL_SECONDS = 600
driver:call_on_schedule(
  SSDP_SCAN_INTERVAL_SECONDS,
  driver.scan_for_ssdp_updates,
  "Sonos SSDP Scan Task"
)

log.info("Starting Sonos run loop")
driver:run()
log.info("Exiting Sonos run loop")
