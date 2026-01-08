-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"

local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local access_control_event = Notification.event.access_control

local lock_utils = require "new_lock_utils"

local function notification_report_handler(self, device, cmd)
  local event
  if (cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL) then
    local event_code = cmd.args.event
    if event_code == access_control_event.AUTO_LOCK_NOT_FULLY_LOCKED_OPERATION then
      event = capabilities.lock.lock.unlocked()
    elseif event_code == access_control_event.NEW_USER_CODE_ADDED then
      local active_credential = device:get_field(lock_utils.ACTIVE_CREDENTIAL)
      local command = device:get_field(lock_utils.COMMAND_NAME)
      if command ~= nil and command.name == lock_utils.ADD_CREDENTIAL and active_credential ~= nil then
        device:send(UserCode:Get({ user_identifier = active_credential.credentialIndex }))
        return
      end
    elseif event_code == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION then
      -- All other codes are deleted when the master code is changed
      for _, credential in pairs(lock_utils.get_credentials(device)) do
        lock_utils.delete_credential(device, credential.credentialIndex)
      end
      lock_utils.send_events(device)
      return
    end
  end

  if event ~= nil then
    device:emit_event(event)
  else
    lock_utils.door_operation_event_handler(self, device, cmd)
    lock_utils.base_driver_code_event_handler(self, device, cmd)
  end
end

-- Used doConfigure instead of added to not overwrite parent driver's added_handler
local function do_configure(self, device)
  -- taken directly from DTH
  -- Samsung locks won't allow you to enter the pairing menu when locked, so it must be unlocked
  device:emit_event(capabilities.lock.lock.unlocked())
end

local samsung_lock = {
  zwave_handlers = {
    [cc.NOTIFICATION] = {
      [Notification.REPORT] = notification_report_handler
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure
  },
  NAME = "Samsung Lock",
  can_handle = require("using-new-capabilities.samsung-lock.can_handle"),
}

return samsung_lock
