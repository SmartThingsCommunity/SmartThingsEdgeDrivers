-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass
local cc = require "st.zwave.CommandClass"
--- @type st.zwave.CommandClass.Version
local Version = (require "st.zwave.CommandClass.Version")({ version = 1 })
--- @type st.zwave.CommandClass.WakeUp
local WakeUp = (require "st.zwave.CommandClass.WakeUp")({ version = 1 })


--Runs upstream handlers (ex zwave_handlers)
local function call_parent_handler(handlers, self, device, event, args)
  for _, func in ipairs(handlers or {}) do
    func(self, device, event, args)
  end
end

--Request version if not populated yet
local function send_version_get(driver, device)
  if device:get_latest_state("main", capabilities.firmwareUpdate.ID, capabilities.firmwareUpdate.currentVersion.NAME) == nil then
    device:send(Version:Get({}))
  end
end

local function version_report(driver, device, cmd)
  local major = cmd.args.application_version
  local minor = cmd.args.application_sub_version
  local fmtFirmwareVersion = string.format("%d.%02d", major, minor)
  device:emit_event(capabilities.firmwareUpdate.currentVersion({ value = fmtFirmwareVersion }))
end

local function wakeup_notification(driver, device, cmd)
  send_version_get(driver, device)
  --Call parent WakeUp functions
  call_parent_handler(driver.zwave_handlers[cc.WAKE_UP][WakeUp.NOTIFICATION], driver, device, cmd)
end

local function added_handler(driver, device)
  --Call main function
  driver.lifecycle_handlers.added(driver, device)
  --Extras for this sub_driver
  send_version_get(driver, device)
end

local firmware_version = {
  NAME = "firmware_version",
  can_handle = require("firmware-version.can_handle"),

  lifecycle_handlers = {
    added = added_handler,
  },
  zwave_handlers = {
    [cc.VERSION] = {
      [Version.REPORT] = version_report
    },
    [cc.WAKE_UP] = {
      [WakeUp.NOTIFICATION] = wakeup_notification
    }
  }
}

return firmware_version