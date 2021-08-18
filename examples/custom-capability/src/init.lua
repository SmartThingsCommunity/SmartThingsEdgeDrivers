local log = require "log"
local capabilities = require "st.capabilities"
local ZigbeeDriver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local switch_defaults = require "st.zigbee.defaults.switch_defaults"
local clusters = require "st.zigbee.zcl.clusters"
local fancySwitch = capabilities["your_namespace.fancySwitch"]

-- Capability command handlers

local function fancy_on_handler(driver, device, command)
  log.error("fancy_on_handler")
  switch_defaults.on(driver, device, command)
end

local function fancy_off_handler(driver, device, command)
  log.error("fancy_off_handler")
  switch_defaults.off(driver, device, command)
end

local function fancy_set_handler(driver, device, command)
  log.error("fancy_set_handler")
  if command.args.state == "On" then
    switch_defaults.on(driver, device, command)
  elseif command.args.state == "Off" then
     switch_defaults.off(driver, device, command)
  end
end

-- Protocol handlers

local function custom_on_off_attr_handler(driver, device, value, zb_rx)
  log.error("custom_on_off_attr_handler")
  device:emit_event(value.value and fancySwitch.fancySwitch.On() or fancySwitch.fancySwitch.Off())
end

-- Lifecycle handlers

local device_added = function(self, device)
  log.error("device_added")
  device:emit_event(fancySwitch.fancySwitch.On())
end

local zigbee_fancy_switch_driver_template = {
  supported_capabilities = {
    fancySwitch,
  },
  zigbee_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = custom_on_off_attr_handler
      }
    }
  },
  capability_handlers = {
    [fancySwitch.ID] = {
      [fancySwitch.commands.fancyOn.NAME] = fancy_on_handler,
      [fancySwitch.commands.fancyOff.NAME] = fancy_off_handler,
      [fancySwitch.commands.fancySet.NAME] = fancy_set_handler,
    }
  },
  cluster_configurations = {
    {
      cluster = clusters.OnOff,
      attribute = clusters.OnOff.attributes.OnOff,
      minimum_interval = 0,
      maximum_interval = 300,
    }
  },
  lifecycle_handlers = {
    added = device_added,
  }
}

defaults.register_for_default_handlers(zigbee_fancy_switch_driver_template, zigbee_fancy_switch_driver_template.supported_capabilities)
local zigbee_fancy_switch = ZigbeeDriver("zigbee_fancy_switch", zigbee_fancy_switch_driver_template)
zigbee_fancy_switch:run()
