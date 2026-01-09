-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0


local capabilities = require "st.capabilities"
--- @type st.zwave.defaults
local defaults = require "st.zwave.defaults"
--- @type st.zwave.Driver
local ZwaveDriver = require "st.zwave.driver"
local Basic = (require "st.zwave.CommandClass.Basic")({version = 1})
local SwitchBinary = (require "st.zwave.CommandClass.SwitchBinary")({version = 1})

local function do_refresh(self, device)
  device:send(SwitchBinary:Get({}))
end

local function device_added(self, device)
  do_refresh(self,device)
end

local function info_changed(self, device, event, args)
  do_refresh(self,device)
end

local function switch_off(driver, device)
  device:send(Basic:Set({value = SwitchBinary.value.OFF_DISABLE}))
  device:send(SwitchBinary:Get({}))
end

local function momentary_switch_on(driver, device)
  device:send(Basic:Set({value = SwitchBinary.value.ON_ENABLE}))
  device:send(SwitchBinary:Get({}))
  driver:call_with_delay(3, function() switch_off(driver, device) end)
end

-------------------------------------------------------------------------------------------
-- Register message handlers and run driver
-------------------------------------------------------------------------------------------
local driver_template = {
  supported_capabilities = {
    capabilities.momentary,
    capabilities.switch,
    capabilities.refresh
  },
  capability_handlers = {
    [capabilities.momentary.ID] = {
      [capabilities.momentary.commands.push.NAME] = momentary_switch_on
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = momentary_switch_on,
      [capabilities.switch.commands.off.NAME] = switch_off
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = do_refresh
    }
  },
  lifecycle_handlers = {
    added = device_added,
    infoChanged = info_changed
  }
}

defaults.register_for_default_handlers(driver_template, driver_template.supported_capabilities)
--- @type st.zwave.Driver
local switch = ZwaveDriver("zwave_virtual_momentary_switch", driver_template)
switch:run()
