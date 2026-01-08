-- Copyright © 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"

local do_refresh = function(self, device)
  local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
  local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
  device:send(DoorLock:OperationGet({}))
  device:send(Battery:Get({}))
end

local SCAN_CODES_CHECK_INTERVAL = 30

local function periodic_codes_state_verification(driver, device)
  local scan_codes_state = device:get_latest_state("main", capabilities.lockCodes.ID, capabilities.lockCodes.scanCodes.NAME)
  if scan_codes_state == "Scanning" then
    driver:inject_capability_command(device,
            { capability = capabilities.lockCodes.ID,
              command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
              args = {}
            }
    )
    device.thread:call_with_delay(
      SCAN_CODES_CHECK_INTERVAL,
      function(d)
        periodic_codes_state_verification(driver, device)
      end
    )
  end
end

local do_added = function(driver, device)
  -- this variable should only be present for test cases trying to test the old capabilities.
  if device.useOldCapabilityForTesting == nil then
    if device:supports_capability_by_id(capabilities.LockCodes.ID) then
      device:emit_event(capabilities.LockCodes.migrated(true, { visibility = { displayed = false } }))
      -- make the driver call this command again, it will now be handled in new capabilities.
      driver.lifecycle_dispatcher:dispatch(driver, device, "added")
    end
  else
    -- added handler from using old capabilities
    driver:inject_capability_command(device,
        { capability = capabilities.lockCodes.ID,
          command = capabilities.lockCodes.commands.reloadAllCodes.NAME,
          args = {} })
    device.thread:call_with_delay(
        SCAN_CODES_CHECK_INTERVAL,
        function()
          periodic_codes_state_verification(driver, device)
        end
    )
    local DoorLock = (require "st.zwave.CommandClass.DoorLock")({ version = 1 })
    local Battery = (require "st.zwave.CommandClass.Battery")({ version = 1 })
    device:send(DoorLock:OperationGet({}))
    device:send(Battery:Get({}))
    if (device:supports_capability(capabilities.tamperAlert)) then
      device:emit_event(capabilities.tamperAlert.tamper.clear())
    end
  end
end

local function time_get_handler(driver, device, cmd)
  local Time = (require "st.zwave.CommandClass.Time")({ version = 1 })
  local time = os.date("*t")
  device:send_to_component(
    Time:Report({
      hour_local_time = time.hour,
      minute_local_time = time.min,
      second_local_time = time.sec
    }),
    device:endpoint_to_component(cmd.src_channel)
  )
end

local driver_template = {
  supported_capabilities = {
    capabilities.lock,
    capabilities.lockCodes,
    capabilities.lockUsers,
    capabilities.lockCredentials,
    capabilities.battery,
    capabilities.tamperAlert
  },
  lifecycle_handlers = {
    added = do_added
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  zwave_handlers = {
    [cc.TIME] = {
      [0x01] = time_get_handler -- used by DanaLock
    }
  },
  sub_drivers = {
    require("sub_drivers")
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
local lock = ZwaveDriver("zwave_lock", driver_template)
lock:run()
