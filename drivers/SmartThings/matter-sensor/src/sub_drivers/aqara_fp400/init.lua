-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local Fp400LifecycleHandlers = {}

-- overwrite to avoid unnecessary metadata update calls
function Fp400LifecycleHandlers.do_configure() end

-- overwrite to avoid unnecessary metadata update calls
function Fp400LifecycleHandlers.driver_switched(driver, device)
  device:try_update_metadata({provisioning_state = "PROVISIONED"})
end

local aqara_fp400_handler = {
  NAME = "aqara-fp400",
  lifecycle_handlers = {
    doConfigure = Fp400LifecycleHandlers.do_configure,
    driverSwitched = Fp400LifecycleHandlers.driver_switched,
  },
  can_handle = require("sub_drivers.aqara_fp400.can_handle"),
}

return aqara_fp400_handler
