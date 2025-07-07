local log = require "log"
local cosock = require "cosock"

--- @class SonosDiscovery
local Discovery = {}

---The discovery loop's only job is to refresh the SSDP search task constantly while
---discovery is active. Actual handling of discovery events happens on a background thread.
---
---@see SonosDriver.ssdp_event_thread_handle
---
---@param driver SonosDriver
---@param _ table
---@param should_continue fun(): boolean
function Discovery.discover(driver, _, should_continue)
  log.info("Starting Sonos Discovery")
  while should_continue() do
    if not driver.ssdp_task then
      log.warn("No SSDP task for driver currently running, cannot perform discovery")
    else
      log.trace("Refreshing search queries on background ssdp task")
      driver.ssdp_task:refresh()
    end
    cosock.socket.sleep(5)
  end
end

return Discovery
