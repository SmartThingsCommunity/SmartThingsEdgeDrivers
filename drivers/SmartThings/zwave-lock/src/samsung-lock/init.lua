-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local cc = require "st.zwave.CommandClass"

local Notification = (require "st.zwave.CommandClass.Notification")({version=3})
local UserCode = (require "st.zwave.CommandClass.UserCode")({version=1})
local access_control_event = Notification.event.access_control

local consts          = require "lock_utils.constants"
local tables          = require "lock_utils.tables"
local zwave_handlers  = require "lock_handlers.zwave_responses"

local function notification_report_handler(self, device, cmd)
  local event
  if (cmd.args.notification_type == Notification.notification_type.ACCESS_CONTROL) then
    local event_code = cmd.args.event
    if event_code == access_control_event.AUTO_LOCK_NOT_FULLY_LOCKED_OPERATION then
      event = capabilities.lock.lock.unlocked()
    elseif event_code == access_control_event.NEW_USER_CODE_ADDED then
      local credential_args = device:get_field(consts.DRIVER_STATE.CREDENTIAL_ARGS_IN_USE)
      local command_in_progress = device:get_field(consts.DRIVER_STATE.COMMAND_IN_PROGRESS)
      if command_in_progress == consts.LOCK_CREDENTIALS.ADD and credential_args ~= nil then
        device:send(UserCode:Get({ user_identifier = credential_args.credentialIndex }))
        return
      end
    elseif event_code == access_control_event.NEW_PROGRAM_CODE_ENTERED_UNIQUE_CODE_FOR_LOCK_CONFIGURATION then
      -- All other codes are deleted when the master code is changed
      tables.delete_all_entries(device, "credentials")
      tables.delete_all_entries(device, "users")
      return
    end
  end

  if event ~= nil then
    device:emit_event(event)
  else
    zwave_handlers.door_operation_event_handler(self, device, cmd)
    zwave_handlers.code_event_handler(self, device, cmd)
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
  can_handle = require("samsung-lock.can_handle"),
}

return samsung_lock
