-- Copyright 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
--- @type st.zwave.CommandClass.SwitchBinary
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({ version = 2 })

local FIREAVERT_APPLIANCE_SHUTOFF_FINGERPRINTS = {
    { manufacturerId = 0x045D, productType = 0x0004, productId = 0x1601 } -- FireAvert Appliance Shutoff - Gas
}
--- Determine whether the passed device is a FireAvert shutoff device. All devices use the same driver.
local function can_handle_fireavert_appliance_shutoff_gas(opts, driver, device, ...)
    local isDevice = false
    for _, fingerprint in ipairs(FIREAVERT_APPLIANCE_SHUTOFF_FINGERPRINTS) do
        if device:id_match(fingerprint.manufacturerId, fingerprint.productType, fingerprint.productId) then
            isDevice = true
            break
        end
    end
    if true == isDevice then
        local subdriver = require("fireavert-appliance-shutoff-gas")
        return true, subdriver
    else return false end
end

--- Handle a Valve Close command from the application.
---
--- @param driver st.zwave.Driver
--- @param device st.zwave.Device
--- @param command ST close valve command
local function st_close_valve(driver, device, command)
  device:send(SwitchBinary:Set({
      target_value = SwitchBinary.value.OFF_DISABLE,
      duration = 0
    })
  )
  -- Refresh valve state
  device:send(SwitchBinary:Get({}))
end

--- Configuration lifecycle event handler.
---
--- Send refresh GETs and manufacturer-specific configuration for
--- the FireAvert Appliance Shutoff device
---
--- @param self st.zwave.Driver
--- @param device st.zwave.Device
local function do_configure(self, device)
  device:refresh()
end

local fireavert_appliance_shutoff_g = {
  capability_handlers = {
    [capabilities.safetyValve.ID] = {
      [capabilities.safetyValve.commands.close.NAME] = st_close_valve
    }
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  NAME = "FireAvert Appliance Shutoff - Gas",
  can_handle = can_handle_fireavert_appliance_shutoff_gas
}

return fireavert_appliance_shutoff_g
