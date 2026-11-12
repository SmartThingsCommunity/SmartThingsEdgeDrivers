-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities      = require "st.capabilities"
local LockCodesDefaults = require "st.zwave.defaults.lockCodes"

local migrate_codes     = require "legacy-handlers.migrate"
local yale_admin        = require "yale-lock.admin"

-- Migrate a Yale lock, mapping its admin code slot to the admin code user.
local function yale_migrate(driver, device, cmd)
  migrate_codes(driver, device, yale_admin.SLOT)

  -- lockCodes only holds the admin code if SmartThings set it and the lock confirmed it as a user code. A factory
  -- admin code, or one a Yale ZW3 confirmed with the "master code changed" notification, is read back instead.
  -- This is because the legacy handlers never read the admin code explicitly. Furthermore, if the lock was
  -- running the newer ZW3 module, the legacy driver did not have the corresponding handling for saving
  -- an admin code after a "Master Code Changed" response.
  if LockCodesDefaults.get_lock_codes(device)[tostring(yale_admin.SLOT)] == nil then
    yale_admin.read_admin_code(device)
  end
end

local legacy_yale_lock = {
  capability_handlers = {
    [capabilities.lockCodes.ID] = {
      [capabilities.lockCodes.commands.migrate.NAME] = yale_migrate
    },
  },
  NAME = "Legacy Yale Lock",
  can_handle = require("legacy-handlers.yale-lock.can_handle"),
}

return legacy_yale_lock
