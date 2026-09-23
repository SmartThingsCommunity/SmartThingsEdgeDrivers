local log = require "log"
local discovery = {}


local metadata_nexController = {
  type = "LAN",
  -- the DNI must be unique across your hub, using static ID here so that we
  -- only ever have a single instance of this "device"
  device_network_id = "XC101U_1_A",
  label = "[A] Nexmosphere controller",
  profile = "NexMother.v1",
  manufacturer = "Nexmosphere",
  model = "v1",
  vendor_provided_label = nil
}

-- handle discovery events, normally you'd try to discover devices on your
-- network in a loop until calling `should_continue()` returns false.
function discovery.handle_discovery(driver, _should_continue)
  log.info("☆☆☆ Starting LAN UDP discovery ☆☆☆")
  driver:try_create_device(metadata_nexController)
end
return discovery