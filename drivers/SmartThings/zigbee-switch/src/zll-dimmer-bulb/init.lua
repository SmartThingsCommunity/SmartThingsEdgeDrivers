-- Copyright 2025 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.zigbee.zcl.clusters"
local colorTemperature_defaults = require "st.zigbee.defaults.colorTemperature_defaults"

local OnOff = clusters.OnOff
local Level = clusters.Level

local function do_configure(driver, device)
  device:configure()
end

local function device_added(driver, device)
  device:refresh()
end

local function handle_switch_on(driver, device, cmd)
  device:send(OnOff.commands.On(device))

  device.thread:call_with_delay(2, function(d)
    device:refresh()
  end)
end

local function handle_switch_off(driver, device, cmd)
  device:send(OnOff.commands.Off(device))

  device.thread:call_with_delay(2, function(d)
    device:refresh()
  end)
end

local function handle_set_level(driver, device, cmd)
  local level = math.floor(cmd.args.level / 100.0 * 254)
  device:send(Level.commands.MoveToLevelWithOnOff(device, level, cmd.args.rate or 0xFFFF))

  device.thread:call_with_delay(2, function(d)
    device:refresh()
  end)
end

local function handle_set_color_temperature(driver, device, cmd)
  colorTemperature_defaults.set_color_temperature(driver, device, cmd)

  local function query_device()
    device:refresh()
  end
  device.thread:call_with_delay(2, query_device)
end

local zll_dimmer_bulb = {
  NAME = "ZLL Dimmer Bulb",
  lifecycle_handlers = {
    doConfigure = do_configure,
    added = device_added
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level
    },
    [capabilities.colorTemperature.ID] = {
      [capabilities.colorTemperature.commands.setColorTemperature.NAME] = handle_set_color_temperature
    }
  },
  can_handle = require("zll-dimmer-bulb.can_handle"),
}

return zll_dimmer_bulb
